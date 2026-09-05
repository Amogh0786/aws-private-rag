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
from langchain.chains import RetrievalQA

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
llm = ChatBedrock(
    client=bedrock_client,
    model_id="anthropic.claude-3-sonnet-20240229-v1:0",
    model_kwargs={"temperature": 0.0}
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
            
        logger.info(f"Received internal query payload.")
        
        # 2. Configure Retriever
        retriever = vector_store.as_retriever(
            search_kwargs={"k": 4} # Retrieve top 4 most relevant chunks
        )
        
        # 3. Setup QA Chain
        qa_chain = RetrievalQA.from_chain_type(
            llm=llm,
            chain_type="stuff",
            retriever=retriever,
            return_source_documents=True,
            chain_type_kwargs={"prompt": PROMPT}
        )
        
        # 4. Execute Private RAG Pipeline
        logger.info("Executing Vector Search and LLM context generation...")
        response = qa_chain.invoke({"query": user_query})
        
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
