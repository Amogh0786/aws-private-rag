import os
import boto3
import urllib.parse
import logging
from opensearchpy import RequestsAWSV4SignerAuth
from langchain_community.vectorstores import OpenSearchVectorSearch
from langchain_aws import BedrockEmbeddings
from langchain_community.document_loaders import PyPDFLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment Variables
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
AOSS_ENDPOINT = os.environ.get("AOSS_ENDPOINT")
# CRITICAL FIX: Ensure AOSS_ENDPOINT has https:// prefix (Terraform output sometimes omits it)
if AOSS_ENDPOINT and not AOSS_ENDPOINT.startswith("https://"):
    AOSS_ENDPOINT = f"https://{AOSS_ENDPOINT}"
    
BEDROCK_ENDPOINT_URL = os.environ.get("BEDROCK_ENDPOINT_URL")
INDEX_NAME = os.environ.get("INDEX_NAME", "rag-index")

# Initialize AWS Clients
s3_client = boto3.client('s3', region_name=AWS_REGION)
bedrock_client = boto3.client('bedrock-runtime', region_name=AWS_REGION, endpoint_url=BEDROCK_ENDPOINT_URL)

credentials = boto3.Session().get_credentials()
aoss_auth = RequestsAWSV4SignerAuth(credentials, AWS_REGION, 'aoss')

embeddings = BedrockEmbeddings(client=bedrock_client, model_id="amazon.titan-embed-text-v1")

def lambda_handler(event, context):
    logger.info(f"Received ingestion event: {event}")
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')
        
        local_file_path = f"/tmp/{os.path.basename(key)}"
        
        try:
            # 1. Download file from S3 Drop Bucket
            logger.info(f"Downloading {key} from bucket {bucket}")
            s3_client.download_file(bucket, key, local_file_path)
            
            # 2. Extract and Chunk Text
            logger.info("Extracting and chunking PDF text...")
            loader = PyPDFLoader(local_file_path)
            documents = loader.load()
            
            text_splitter = RecursiveCharacterTextSplitter(
                chunk_size=1000, 
                chunk_overlap=150
            )
            docs = text_splitter.split_documents(documents)
            
            # 3. Generate Embeddings & Push to OpenSearch
            logger.info(f"Uploading {len(docs)} document chunks to OpenSearch Vector Store...")
            OpenSearchVectorSearch.from_documents(
                docs,
                embeddings,
                opensearch_url=AOSS_ENDPOINT,
                index_name=INDEX_NAME,
                http_auth=aoss_auth,
                timeout=60,
                use_ssl=True,
                verify_certs=True,
                connection_class="RequestsHttpConnection"
            )
            
            logger.info(f"Successfully processed and ingested {key}!")
            
        except Exception as e:
            logger.error(f"Error processing document {key}: {str(e)}")
            raise
