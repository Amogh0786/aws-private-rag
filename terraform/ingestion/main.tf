# S3 Bucket for Document Drop
resource "aws_s3_bucket" "documents_bucket" {
  bucket_prefix = "private-rag-docs-"
}

# S3 Bucket Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.documents_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.ingestion_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".pdf"
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}

# Lambda Function for Document Ingestion
resource "aws_lambda_function" "ingestion_lambda" {
  filename         = "ingestion_payload.zip" # Placeholder for CI/CD build artifact
  function_name    = "private-rag-document-ingestion"
  role             = aws_iam_role.ingestion_role.arn
  handler          = "ingestion_lambda.lambda_handler"
  runtime          = "python3.11"
  timeout          = 300 # 5 minutes for large PDFs
  memory_size      = 1024

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.vpc_endpoints_sg_id]
  }

  environment {
    variables = {
      AWS_REGION           = var.aws_region
      AOSS_ENDPOINT        = var.aoss_endpoint
      BEDROCK_ENDPOINT_URL = var.bedrock_endpoint_url
      INDEX_NAME           = "rag-index"
    }
  }
}

# Allow S3 to invoke Lambda
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingestion_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.documents_bucket.arn
}

# IAM Role for Ingestion Lambda
resource "aws_iam_role" "ingestion_role" {
  name = "rag-ingestion-role"

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

# Attach VPC Execution Role
resource "aws_iam_role_policy_attachment" "vpc_execution" {
  role       = aws_iam_role.ingestion_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Inline Policy for S3, Bedrock, and OpenSearch Data Access
resource "aws_iam_role_policy" "ingestion_policy" {
  name = "rag-ingestion-policy"
  role = aws_iam_role.ingestion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.documents_bucket.arn,
          "${aws_s3_bucket.documents_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = "*"
      }
    ]
  })
}
