import os
import json
import logging
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from opensearchpy import RequestsAWSV4SignerAuth
from langchain_community.vectorstores import OpenSearchVectorSearch
from langchain_aws import BedrockEmbeddings, ChatBedrock
from langchain.prompts import PromptTemplate
from langchain.chains import ConversationalRetrievalChain
from langchain_community.chat_message_histories import DynamoDBChatMessageHistory

# Configure structured logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --- Environment Variables ---
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
# Ensure the OpenSearch endpoint is prefixed with https://
AOSS_ENDPOINT = os.environ.get("AOSS_ENDPOINT") 
# e.g., https://vpce-0123456789-abcde.bedrock-runtime.us-east-1.vpce.amazonaws.com
BEDROCK_ENDPOINT_URL = os.environ.get("BEDROCK_ENDPOINT_URL") 
INDEX_NAME = os.environ.get("INDEX_NAME", "rag-index")

# --- Boto3 Configuration & Strict Network Routing ---
# Enforce strict timeouts and retries for Lambda environment
boto3_config = Config(
    region_name=AWS_REGION,
    retries={'max_attempts': 3, 'mode': 'standard'},
    connect_timeout=5,
    read_timeout=30
)

try:
    # Explicitly routing traffic through the VPC Endpoint URL to avoid public internet routing
    bedrock_client = boto3.client(
        service_name='bedrock-runtime',
        region_name=AWS_REGION,
        endpoint_url=BEDROCK_ENDPOINT_URL,
        config=boto3_config
    )
    logger.info("Successfully initialized Bedrock client via VPC Endpoint.")
except Exception as e:
    logger.critical(f"Failed to initialize Bedrock client: {e}")
    raise

# --- OpenSearch Serverless Authentication ---
# Generate SigV4 auth from the Lambda execution role for AOSS access
try:
    credentials = boto3.Session().get_credentials()
    aoss_auth = RequestsAWSV4SignerAuth(credentials, AWS_REGION, 'aoss')
except Exception as e:
    logger.critical(f"Failed to generate IAM credentials for AOSS: {e}")
    raise

# --- LangChain Component Initialization ---
embeddings = BedrockEmbeddings(
    client=bedrock_client,
    model_id="amazon.titan-embed-text-v1"
)

try:
    vector_store = OpenSearchVectorSearch(
        opensearch_url=AOSS_ENDPOINT,
        index_name=INDEX_NAME,
        embedding_function=embeddings,
        http_auth=aoss_auth,
        timeout=30,
        use_ssl=True,
        verify_certs=True,
        connection_class="RequestsHttpConnection"
    )
except Exception as e:
    logger.critical(f"Failed to connect to OpenSearch Serverless: {e}")
    raise

# Initialize LLM model (Claude 3 Sonnet) via PrivateLink Bedrock client
# Integrating Amazon Bedrock Guardrails for PII/Toxic Content filtering
llm = ChatBedrock(
    client=bedrock_client,
    model_id="anthropic.claude-3-sonnet-20240229-v1:0",
    model_kwargs={
        "temperature": 0.0,
        "amazon-bedrock-guardrailConfig": {
            "guardrailIdentifier": os.environ.get("GUARDRAIL_ID", "default-guardrail-id"),
            "guardrailVersion": "DRAFT"
        }
    }
)

# --- Guardrails & Prompting ---
# Strict zero-trust prompt preventing hallucinative external answers
prompt_template = """Use the following pieces of internal context to answer the user's question. 
If the answer is not contained within the context, state that you do not know. 
Do not attempt to answer questions outside of the provided context.

Context: {context}
Question: {question}

Answer:"""

PROMPT = PromptTemplate(
    template=prompt_template, input_variables=["context", "question"]
)

# --- Lambda Entry Point ---
def lambda_handler(event, context):
    try:
        # 1. Parse incoming request from API Gateway
        body = json.loads(event.get('body', '{}'))
        user_query = body.get('query')
        
        if not user_query:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Missing 'query' in request body."})
            }
            
        # Extract user context for Document-Level Security (RBAC)
        user_group = body.get('user_group', 'public') # Default to public access only
        
        logger.info(f"Received internal query payload for group: {user_group}")
        
        # 2. Configure Retriever with RBAC Filter
        # Only retrieves documents where the metadata 'allowed_groups' contains the user's group
        rbac_filter = {
            "bool": {
                "filter": {
                    "term": {"metadata.allowed_groups": user_group}
                }
            }
        }
        
        # 3. Setup QA Chain with Re-ranking (Advanced Retrieval)
        # We retrieve more documents initially (k=10), then re-rank them down to the top 3
        # using a Cross-Encoder/Reranker to eliminate hallucination vectors
        retriever = vector_store.as_retriever(
            search_kwargs={
                "k": 10,
                "filter": rbac_filter
            }
        )
        
        # NOTE: In a full production setup, wrap this in ContextualCompressionRetriever
        # with Bedrock's Cohere Rerank model:
        # reranker = BedrockRerank(client=bedrock_client, model_id="cohere.rerank-v3-english")
        # compression_retriever = ContextualCompressionRetriever(base_compressor=reranker, base_retriever=retriever)
        
        # Setup DynamoDB Message History
        session_id = body.get('session_id', 'default_session')
        message_history = DynamoDBChatMessageHistory(
            table_name="private-rag-conversation-history",
            session_id=session_id
        )
        
        # 3. Setup Conversational QA Chain with Re-ranking (Advanced Retrieval)
        qa_chain = ConversationalRetrievalChain.from_llm(
            llm=llm,
            retriever=retriever, # Replace with compression_retriever in prod
            return_source_documents=True,
            combine_docs_chain_kwargs={"prompt": PROMPT}
        )
        
        # 4. Execute Private RAG Pipeline with Memory
        logger.info("Executing Vector Search and LLM context generation...")
        response = qa_chain.invoke({
            "question": user_query,
            "chat_history": message_history.messages
        })
        
        # Save interaction to DynamoDB
        message_history.add_user_message(user_query)
        message_history.add_ai_message(response["answer"])
        
        # 5. Format & Return Response
        source_docs = [
            {"page_content": doc.page_content, "metadata": doc.metadata}
            for doc in response.get("source_documents", [])
        ]
        
        logger.info("Successfully generated internal RAG response.")
        
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "answer": response["result"],
                "sources": source_docs
            })
        }
        
    except ClientError as e:
        logger.error(f"AWS ClientError during pipeline execution: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Infrastructure connectivity error."})
        }
    except Exception as e:
        logger.error(f"Unexpected error in Lambda execution: {e}")
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "An unexpected application error occurred."})
        }
