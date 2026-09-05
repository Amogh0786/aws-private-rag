output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.private_rag_vpc.id
}

output "private_subnet_ids" {
  description = "The IDs of the private subnets"
  value       = aws_subnet.private_subnets[*].id
}

output "vpc_endpoints_sg_id" {
  description = "The ID of the security group for VPC endpoints"
  value       = aws_security_group.vpc_endpoints_sg.id
}
