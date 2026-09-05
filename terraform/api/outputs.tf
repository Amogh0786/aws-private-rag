output "api_gateway_invoke_url" {
  description = "The internal invocation URL for the Private API Gateway"
  value       = aws_api_gateway_stage.prod_stage.invoke_url
}

output "api_vpc_endpoint_id" {
  description = "The ID of the VPC Endpoint used to invoke the API"
  value       = aws_vpc_endpoint.api_endpoint.id
}
