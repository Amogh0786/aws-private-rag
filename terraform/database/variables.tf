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
