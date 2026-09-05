output "internal_alb_dns_name" {
  description = "The internal DNS name of the Load Balancer to access the Streamlit UI via the corporate VPN"
  value       = aws_lb.frontend_alb.dns_name
}
