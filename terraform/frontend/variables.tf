variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC ID from Phase 1"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet IDs from Phase 1"
  type        = list(string)
}

variable "corporate_cidr" {
  description = "CIDR block representing the internal corporate network (VPN/Direct Connect) allowed to access the UI"
  type        = string
  default     = "10.0.0.0/8" # Standard corporate internal address space
}

variable "ecr_image_url" {
  description = "URL of the Streamlit Docker image in Amazon ECR"
  type        = string
}

variable "api_gateway_invoke_url" {
  description = "The internal invocation URL for the Private API Gateway from Phase 4"
  type        = string
}
