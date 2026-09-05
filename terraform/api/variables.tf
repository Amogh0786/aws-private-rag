variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID from Phase 1"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs from Phase 1"
  type        = list(string)
}

variable "vpc_endpoints_sg_id" {
  description = "Security Group ID for VPC Endpoints from Phase 1"
  type        = string
}

variable "lambda_invoke_arn" {
  description = "The Invoke ARN of the Lambda function (from Phase 3 module)"
  type        = string
}

variable "lambda_function_name" {
  description = "The name of the Lambda function (from Phase 3 module)"
  type        = string
}
