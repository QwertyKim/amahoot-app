# Amahoot WebSocket Server - Terraform Infrastructure as Code

This repository contains a complete Terraform Infrastructure as Code (IaC) solution for deploying the Amahoot real-time quiz game WebSocket server on AWS. The infrastructure creates an EC2 instance in a public subnet running a Node.js WebSocket server with DynamoDB backend.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                Public Subnet                        │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │              EC2 Instance                   │    │    │
│  │  │  ┌─────────────────────────────────────┐    │    │    │
│  │  │  │        Node.js WebSocket Server     │    │    │    │
│  │  │  │        - Express.js                 │    │    │    │
│  │  │  │        - Socket.IO                  │    │    │    │
│  │  │  │        - Port 5000                  │    │    │    │
│  │  │  └─────────────────────────────────────┘    │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                Internet Gateway                     │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────────┐
│                    DynamoDB Table                           │
│                  (amahoot-game-data)                        │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- **Terraform** >= 1.0 ([Install Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli))
- **AWS CLI** configured with appropriate credentials ([Setup Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html))
- **jq** for JSON processing ([Install Guide](https://stedolan.github.io/jq/download/))
- **make** (optional, for convenient commands)

### 1. Setup Environment

```bash
# Clone the repository (if not already done)
# git clone <your-repo-url>
# cd amahoot-websocket

# Set up the environment
make setup
# OR manually:
chmod +x *.sh
cp terraform.tfvars.example terraform.tfvars
```

### 2. Configure Variables

Edit `terraform.tfvars` with your specific configuration:

```hcl
# AWS Configuration
aws_region = "us-east-1"

# Project Configuration
project_name = "amahoot-websocket"
environment  = "dev"

# EC2 Configuration
instance_type = "t3.micro"
key_pair_name = "your-key-pair-name"  # Optional, for SSH access

# Application Configuration
app_port = 5000
cors_origin = "https://yourdomain.com"  # Or "*" for development

# Security Configuration
ssh_allowed_cidrs = ["203.0.113.0/24"]  # Your IP range

# Optional Features
create_elastic_ip = false  # Set to true for production
```

### 3. Deploy Infrastructure

```bash
# Validate configuration
make validate

# Deploy infrastructure
make deploy

# Or use individual commands:
terraform init
terraform plan
terraform apply
```

### 4. Test Deployment

```bash
# Run integration tests
make test

# Check status
make status

# Monitor application
make monitor
```

## 📁 Project Structure

```
.
├── main.tf                    # Core infrastructure resources
├── variables.tf               # Input variables and validation
├── outputs.tf                 # Output values
├── user-data.sh              # EC2 initialization script
├── terraform.tfvars.example  # Example configuration
├── terraform-tests.tf        # Infrastructure tests
├── validate.sh               # Configuration validation script
├── deploy.sh                 # Automated deployment script
├── integration-test.sh       # End-to-end testing script
├── destroy.sh                # Safe infrastructure destruction
├── troubleshooting.md        # Troubleshooting guide
├── Makefile                  # Convenient command shortcuts
└── README.md                 # This file
```

## 🛠️ Available Commands

Using the Makefile for convenient operations:

```bash
make help           # Show all available commands
make setup          # Set up environment and make scripts executable
make validate       # Validate Terraform configuration
make deploy         # Deploy infrastructure
make test           # Run integration tests
make status         # Show current infrastructure status
make logs           # Show application logs
make ssh            # SSH into EC2 instance
make destroy        # Destroy infrastructure
make clean          # Clean up temporary files
```

## 🔧 Infrastructure Components

### Core Resources

- **VPC**: Custom VPC with DNS support
- **Public Subnet**: Subnet with Internet Gateway access
- **EC2 Instance**: t3.micro instance running Amazon Linux 2
- **Security Group**: Configured for WebSocket traffic (port 5000)
- **DynamoDB Table**: NoSQL database for game data
- **IAM Role**: EC2 instance role with DynamoDB permissions
- **CloudWatch**: Monitoring and logging setup

### Security Features

- **Encrypted EBS volumes**
- **IAM roles with least privilege**
- **Security groups with specific port access**
- **Optional SSH key-based access**
- **DynamoDB encryption at rest**
- **VPC with private networking**

### Monitoring & Observability

- **CloudWatch Agent** for system metrics
- **Application logs** via systemd journal
- **Health check endpoints**
- **Automated log rotation**
- **Performance monitoring**

## 🔍 Testing

The infrastructure includes comprehensive testing:

### Validation Tests
- Terraform syntax validation
- Variable constraint checking
- Security configuration validation
- Resource dependency verification

### Integration Tests
- HTTP connectivity testing
- WebSocket connection testing
- DynamoDB access verification
- EC2 instance health checks
- Security group rule validation

Run tests with:
```bash
make test
# OR
./integration-test.sh
```

## 📊 Monitoring

### Application Health

Check application status:
```bash
# Via HTTP health endpoint
curl http://<instance-ip>:5000/health

# Via application logs
make logs

# Via SSH (if key configured)
make ssh
sudo journalctl -u amahoot-websocket -f
```

### Infrastructure Monitoring

- **CloudWatch Metrics**: CPU, memory, disk usage
- **CloudWatch Logs**: Application and system logs
- **AWS Console**: Resource status and billing

## 🔒 Security Best Practices

### Network Security
- EC2 instance in public subnet (as requested)
- Security groups with minimal required access
- Optional SSH access with key-based authentication

### Data Security
- DynamoDB encryption at rest
- EBS volume encryption
- IAM roles with least privilege access
- No hardcoded credentials

### Operational Security
- Regular security updates via user data script
- Log monitoring and retention
- Backup procedures for critical data

## 🚨 Troubleshooting

Common issues and solutions are documented in [troubleshooting.md](troubleshooting.md).

### Quick Diagnostics

```bash
# Check infrastructure status
make status

# Validate configuration
make validate

# Test connectivity
make monitor

# View logs
make logs
```

### Common Issues

1. **Application not responding**: Check security groups and application logs
2. **DynamoDB access denied**: Verify IAM role permissions
3. **SSH connection failed**: Check key pair configuration and security groups
4. **High resource usage**: Monitor CloudWatch metrics and consider instance upgrade

## 💰 Cost Optimization

### Default Configuration Costs (us-east-1)
- **EC2 t3.micro**: ~$8.50/month (free tier eligible)
- **DynamoDB**: Pay-per-request (minimal cost for development)
- **Data Transfer**: Minimal for typical usage
- **CloudWatch**: Basic monitoring included

### Cost Reduction Tips
- Use free tier eligible resources
- Enable DynamoDB on-demand billing
- Monitor usage with AWS Cost Explorer
- Clean up unused resources regularly

## 🔄 Deployment Workflows

### Development Workflow
```bash
make setup          # Initial setup
make dev-deploy     # Deploy with testing
make test           # Verify deployment
# ... develop and test ...
make destroy        # Clean up when done
```

### Production Workflow
```bash
make setup          # Initial setup
make backup         # Backup existing state
make validate       # Thorough validation
make prod-deploy    # Production deployment with safety checks
make monitor        # Verify deployment
```

## 📚 Additional Resources

- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Node.js Best Practices](https://nodejs.org/en/docs/guides/)
- [WebSocket API Documentation](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test thoroughly
4. Update documentation as needed
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:

1. Check the [troubleshooting guide](troubleshooting.md)
2. Review AWS CloudWatch logs
3. Create an issue in the repository
4. Contact the development team

---

**⚠️ Important Notes:**

- This configuration creates resources in AWS that may incur costs
- Always run `terraform destroy` when resources are no longer needed
- Review security settings before deploying to production
- Keep your `terraform.tfvars` file secure and never commit it to version control
- Regularly update Terraform providers and modules for security patches

**🎯 Next Steps:**

After successful deployment, consider:
- Setting up CI/CD pipelines
- Implementing blue-green deployments
- Adding SSL/TLS termination
- Configuring custom domain names
- Setting up monitoring alerts
- Implementing backup strategies