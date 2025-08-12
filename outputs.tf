# Outputs for Amahoot WebSocket Server Terraform Configuration

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public.id
}

output "public_subnet_cidr" {
  description = "CIDR block of the public subnet"
  value       = aws_subnet.public.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.websocket_server.id
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.websocket_server.id
}

output "ec2_instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.websocket_server.public_ip
}

output "ec2_instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.websocket_server.private_ip
}

output "ec2_instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.websocket_server.public_dns
}

output "elastic_ip" {
  description = "Elastic IP address (if created)"
  value       = var.create_elastic_ip ? aws_eip.websocket_server[0].public_ip : null
}

output "elastic_ip_dns" {
  description = "Elastic IP DNS name (if created)"
  value       = var.create_elastic_ip ? aws_eip.websocket_server[0].public_dns : null
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.game_data.name
}

output "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.game_data.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "websocket_server_url" {
  description = "WebSocket server URL"
  value       = var.create_elastic_ip ? "ws://${aws_eip.websocket_server[0].public_ip}:${var.app_port}" : "ws://${aws_instance.websocket_server.public_ip}:${var.app_port}"
}

output "websocket_server_http_url" {
  description = "HTTP URL for the WebSocket server"
  value       = var.create_elastic_ip ? "http://${aws_eip.websocket_server[0].public_ip}:${var.app_port}" : "http://${aws_instance.websocket_server.public_ip}:${var.app_port}"
}

output "ssh_command" {
  description = "SSH command to connect to the instance (if key pair is specified)"
  value       = var.key_pair_name != null ? "ssh -i ~/.ssh/${var.key_pair_name}.pem ec2-user@${var.create_elastic_ip ? aws_eip.websocket_server[0].public_ip : aws_instance.websocket_server.public_ip}" : "No key pair specified"
}

output "application_logs_command" {
  description = "Command to view application logs"
  value       = "sudo journalctl -u amahoot-websocket -f"
}

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value = {
    project_name        = var.project_name
    environment         = var.environment
    aws_region          = var.aws_region
    instance_type       = var.instance_type
    application_port    = var.app_port
    vpc_cidr           = var.vpc_cidr
    public_subnet_cidr = var.public_subnet_cidr
    dynamodb_table     = var.dynamodb_table_name
    elastic_ip_created = var.create_elastic_ip
  }
}