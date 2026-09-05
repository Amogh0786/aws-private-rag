output "vector_db_endpoint" {
  description = "The endpoint URL for the OpenSearch Serverless collection"
  value       = aws_opensearchserverless_collection.vector_db.collection_endpoint
}

output "rag_compute_role_arn" {
  description = "IAM Role ARN for the RAG compute layer"
  value       = aws_iam_role.rag_compute_role.arn
}
