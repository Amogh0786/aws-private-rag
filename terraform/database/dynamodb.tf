# DynamoDB Table for Conversation History
resource "aws_dynamodb_table" "conversation_history" {
  name           = "private-rag-conversation-history"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "SessionId"

  attribute {
    name = "SessionId"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
