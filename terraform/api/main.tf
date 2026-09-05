data "aws_caller_identity" "current" {}

# VPC Endpoint for API Gateway (Execute-API)
resource "aws_vpc_endpoint" "api_endpoint" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoints_sg_id]
  private_dns_enabled = true

  tags = {
    Name        = "PrivateRAG-API-Endpoint"
    Environment = var.environment
  }
}

# Private API Gateway REST API
resource "aws_api_gateway_rest_api" "rag_api" {
  name        = "Private-RAG-API"
  description = "Private API Gateway for internal enterprise RAG queries"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.api_endpoint.id]
  }
}

# Resource Policy enforcing Zero-Trust access
resource "aws_api_gateway_rest_api_policy" "rag_api_policy" {
  rest_api_id = aws_api_gateway_rest_api.rag_api.id
  
  # Deny all traffic that DOES NOT come from the specified VPC Endpoint
  # Explicitly allow traffic from the corporate AWS account via that endpoint
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Deny"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.rag_api.execution_arn}/*"
        Condition = {
          StringNotEquals = {
            "aws:SourceVpce" = aws_vpc_endpoint.api_endpoint.id
          }
        }
      },
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "${aws_api_gateway_rest_api.rag_api.execution_arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# API Route /query
resource "aws_api_gateway_resource" "query_resource" {
  rest_api_id = aws_api_gateway_rest_api.rag_api.id
  parent_id   = aws_api_gateway_rest_api.rag_api.root_resource_id
  path_part   = "query"
}

# API Method (POST)
resource "aws_api_gateway_method" "query_method" {
  rest_api_id   = aws_api_gateway_rest_api.rag_api.id
  resource_id   = aws_api_gateway_resource.query_resource.id
  http_method   = "POST"
  authorization = "NONE" # Access is restricted by Resource Policy & VPC Endpoint
}

# Connect API Gateway to Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.rag_api.id
  resource_id             = aws_api_gateway_resource.query_resource.id
  http_method             = aws_api_gateway_method.query_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "rag_api_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_rest_api_policy.rag_api_policy
  ]
  rest_api_id = aws_api_gateway_rest_api.rag_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.query_resource.id,
      aws_api_gateway_method.query_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Stage mapping
resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.rag_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.rag_api.id
  stage_name    = "prod"
}

# Allow API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.rag_api.execution_arn}/*/*"
}
