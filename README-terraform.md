# Terraform Infrastructure as Code for Amahoot Quiz Game WebSocket Server

This directory contains Terraform configuration files to deploy the Amahoot quiz game WebSocket server on AWS EC2 in a public subnet.

## Architecture

- **VPC**: Custom VPC with public subnet
- **EC2**: t3.micro instance running the Node.js WebSocket server
- **DynamoDB**: Table for game data storage
- **Security**: IAM roles and security groups with least privilege access
- **Networking**: Internet Gateway and route tables for public access

## Files

- `main.tf`: Core infrastructure resources
- `variables.tf`: Input variables and configuration
- `outputs.tf`: Output values after deployment
- `user-data.sh`: EC2 initialization script
- `terraform.tfvars.example`: Example variables file

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform installed (>= 1.0)
3. An existing EC2 Key Pair (optional, for SSH access)

## Deployment

1. Copy and customize the variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Plan the deployment:
   ```bash
   terraform plan
   ```

4. Apply the configuration:
   ```bash
   terraform apply
   ```

## Configuration

The application will be accessible on port 5000 of the EC2 instance's public IP address. The WebSocket server will automatically start on boot and restart on failure.

## Security Notes

- The EC2 instance is placed in a public subnet as requested
- Security groups restrict access to necessary ports only
- IAM roles follow least privilege principles
- For production, consider using a private subnet with Application Load Balancer

## Cleanup

To destroy the infrastructure:
```bash
terraform destroy
```