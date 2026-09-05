# Encryption Policy (Required before collection creation)
resource "aws_opensearchserverless_security_policy" "encryption_policy" {
  name        = "rag-encryption-policy"
  type        = "encryption"
  description = "Encryption policy for RAG vector DB"
  policy      = jsonencode({
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/rag-vector-store"]
      }
    ]
    AWSOwnedKey = true
  })
}

# AOSS VPC Endpoint (PrivateLink for OpenSearch Serverless)
resource "aws_opensearchserverless_vpc_endpoint" "aoss_endpoint" {
  name               = "rag-aoss-vpce"
  vpc_id             = var.vpc_id
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.vpc_endpoints_sg_id]
}

# Network Policy (Restricts access to only our VPC Endpoint)
resource "aws_opensearchserverless_security_policy" "network_policy" {
  name        = "rag-network-policy"
  type        = "network"
  description = "Network policy for RAG vector DB"
  policy      = jsonencode([
    {
      Description = "VPC access for collection"
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/rag-vector-store"]
        }
      ]
      AllowFromPublic = false
      SourceVPCEs     = [aws_opensearchserverless_vpc_endpoint.aoss_endpoint.id]
    }
  ])
}

# OpenSearch Serverless Collection (Vector Engine)
resource "aws_opensearchserverless_collection" "vector_db" {
  name             = "rag-vector-store"
  type             = "VECTORSEARCH"
  description      = "Private vector database for RAG"
  
  depends_on = [
    aws_opensearchserverless_security_policy.encryption_policy,
    aws_opensearchserverless_security_policy.network_policy
  ]
}

# Lambda / Compute IAM Role
resource "aws_iam_role" "rag_compute_role" {
  name = "rag-compute-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Data Access Policy (Grants Lambda role permission to read/write vectors)
resource "aws_opensearchserverless_security_policy" "data_access_policy" {
  name        = "rag-data-policy"
  type        = "data"
  description = "Data access policy for Lambda role"
  policy      = jsonencode([
    {
      Rules = [
        {
          ResourceType = "collection"
          Resource     = ["collection/rag-vector-store"]
          Permission   = [
            "aoss:CreateCollectionItems",
            "aoss:DeleteCollectionItems",
            "aoss:UpdateCollectionItems",
            "aoss:DescribeCollectionItems"
          ]
        },
        {
          ResourceType = "index"
          Resource     = ["index/rag-vector-store/*"]
          Permission   = [
            "aoss:CreateIndex",
            "aoss:DeleteIndex",
            "aoss:UpdateIndex",
            "aoss:DescribeIndex",
            "aoss:ReadDocument",
            "aoss:WriteDocument"
          ]
        }
      ]
      Principal = [aws_iam_role.rag_compute_role.arn]
    }
  ])
}

# IAM Policy for Bedrock Access
resource "aws_iam_policy" "bedrock_access_policy" {
  name        = "rag-bedrock-access-policy"
  description = "Allow Lambda to access Bedrock models"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "*" # Consider scoping this down to specific model ARNs for strict production
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bedrock_attach" {
  role       = aws_iam_role.rag_compute_role.name
  policy_arn = aws_iam_policy.bedrock_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "vpc_execution_attach" {
  role       = aws_iam_role.rag_compute_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
