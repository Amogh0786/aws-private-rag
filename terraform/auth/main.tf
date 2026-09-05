# Amazon Cognito User Pool for Authentication
resource "aws_cognito_user_pool" "rag_user_pool" {
  name = "private-rag-user-pool"

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true # Only IT can create accounts
  }
}

# Cognito App Client for the Streamlit UI
resource "aws_cognito_user_pool_client" "rag_app_client" {
  name         = "private-rag-streamlit-client"
  user_pool_id = aws_cognito_user_pool.rag_user_pool.id

  generate_secret = true
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

# API Gateway Cognito Authorizer (To lock down the API)
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "rag-cognito-authorizer"
  rest_api_id   = var.api_gateway_id # From Phase 4
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.rag_user_pool.arn]
}
