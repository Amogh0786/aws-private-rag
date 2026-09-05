variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs from Phase 1"
  type        = list(string)
}

variable "vpc_endpoints_sg_id" {
  description = "Security Group ID for VPC Endpoints from Phase 1"
  type        = string
}

variable "aoss_endpoint" {
  description = "OpenSearch Serverless Collection Endpoint URL"
  type        = string
}

variable "bedrock_endpoint_url" {
  description = "Bedrock VPC Endpoint URL"
  type        = string
}
