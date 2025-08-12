# Variables for Amahoot WebSocket Server Terraform Configuration

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project (used for resource naming)"
  type        = string
  default     = "amahoot-websocket"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair for SSH access (optional)"
  type        = string
  default     = null
}

variable "app_port" {
  description = "Port number for the WebSocket application"
  type        = number
  default     = 5000
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for game data"
  type        = string
  default     = "amahoot-game-data"
}

variable "cors_origin" {
  description = "CORS origin for the application"
  type        = string
  default     = "*"
}

variable "ssh_allowed_cidrs" {
  description = "List of CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "create_elastic_ip" {
  description = "Whether to create an Elastic IP for the instance"
  type        = bool
  default     = false
}

variable "github_repo_url" {
  description = "GitHub repository URL for the application code"
  type        = string
  default     = "https://github.com/your-username/amahoot-websocket.git"
}

variable "app_directory" {
  description = "Directory name for the application"
  type        = string
  default     = "amahoot-websocket"
}

# Validation rules
variable "allowed_instance_types" {
  description = "List of allowed EC2 instance types"
  type        = list(string)
  default     = ["t3.micro", "t3.small", "t3.medium", "t3.large"]
}

# Validate instance type
locals {
  validate_instance_type = contains(var.allowed_instance_types, var.instance_type)
}

# Custom validation for instance type
variable "validate_instance_type" {
  description = "Validation for instance type"
  type        = bool
  default     = true
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium", "t3.large", "t2.micro", "t2.small"], var.instance_type)
    error_message = "Instance type must be one of: t3.micro, t3.small, t3.medium, t3.large, t2.micro, t2.small."
  }
}

# Validate AWS region
variable "validate_aws_region" {
  description = "Validation for AWS region"
  type        = bool
  default     = true
  validation {
    condition = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be in the format: us-east-1, eu-west-1, etc."
  }
}

# Validate port number
variable "validate_app_port" {
  description = "Validation for application port"
  type        = bool
  default     = true
  validation {
    condition     = var.app_port >= 1024 && var.app_port <= 65535
    error_message = "Application port must be between 1024 and 65535."
  }
}