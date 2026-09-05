provider "aws" {
  region = var.aws_region
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# VPC
resource "aws_vpc" "private_rag_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "PrivateRAG-VPC"
    Environment = var.environment
  }
}

# Private Subnets (No IGW, No NAT)
resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.private_rag_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "PrivateRAG-Subnet-${count.index + 1}"
    Environment = var.environment
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.private_rag_vpc.id

  tags = {
    Name = "PrivateRAG-RouteTable"
    Environment = var.environment
  }
}

# Route Table Associations
resource "aws_route_table_association" "private_rt_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Security Group for VPC Endpoints & Compute
resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "private-rag-endpoints-sg"
  description = "Security group for VPC Endpoints allowing internal HTTPS traffic only"
  vpc_id      = aws_vpc.private_rag_vpc.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.private_rag_vpc.cidr_block]
  }

  egress {
    description = "HTTPS to VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.private_rag_vpc.cidr_block]
  }

  tags = {
    Name = "PrivateRAG-Endpoints-SG"
    Environment = var.environment
  }
}

# VPC Endpoints (Interface Endpoints for PrivateLink)
locals {
  services = {
    "bedrock-runtime" = "com.amazonaws.${var.aws_region}.bedrock-runtime"
    "bedrock"         = "com.amazonaws.${var.aws_region}.bedrock"
    "secretsmanager"  = "com.amazonaws.${var.aws_region}.secretsmanager"
    "logs"            = "com.amazonaws.${var.aws_region}.logs"
  }
}

resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each          = local.services
  vpc_id            = aws_vpc.private_rag_vpc.id
  service_name      = each.value
  vpc_endpoint_type = "Interface"
  
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true

  tags = {
    Name = "PrivateRAG-${each.key}-endpoint"
    Environment = var.environment
  }
}
