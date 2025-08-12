# Makefile for Amahoot WebSocket Server Infrastructure
# Provides convenient commands for managing the infrastructure

.PHONY: help init validate plan deploy test destroy clean setup

# Default target
help: ## Show this help message
	@echo "Amahoot WebSocket Server Infrastructure Management"
	@echo "================================================="
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Terraform >= 1.0"
	@echo "  - AWS CLI configured"
	@echo "  - jq (for JSON processing)"
	@echo ""

setup: ## Set up the environment and make scripts executable
	@echo "Setting up environment..."
	@chmod +x *.sh
	@echo "Scripts made executable"
	@if [ ! -f terraform.tfvars ]; then \
		echo "Creating terraform.tfvars from example..."; \
		cp terraform.tfvars.example terraform.tfvars; \
		echo "Please edit terraform.tfvars with your configuration"; \
	fi
	@echo "Setup complete!"

init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	@terraform init

validate: ## Validate Terraform configuration and run checks
	@echo "Running validation..."
	@./validate.sh

plan: ## Create Terraform execution plan
	@echo "Creating Terraform plan..."
	@terraform plan

deploy: ## Deploy the infrastructure
	@echo "Deploying infrastructure..."
	@./deploy.sh

deploy-auto: ## Deploy the infrastructure without interactive prompts
	@echo "Deploying infrastructure (auto-approve)..."
	@./deploy.sh --auto-approve

test: ## Run integration tests
	@echo "Running integration tests..."
	@./integration-test.sh

destroy: ## Destroy the infrastructure
	@echo "Destroying infrastructure..."
	@./destroy.sh

destroy-auto: ## Destroy the infrastructure without interactive prompts
	@echo "Destroying infrastructure (auto-approve)..."
	@./destroy.sh --auto-approve

clean: ## Clean up temporary files and backups
	@echo "Cleaning up temporary files..."
	@rm -f tfplan_*
	@rm -f destroy_plan_*
	@rm -f *.log
	@echo "Cleanup complete"

status: ## Show current infrastructure status
	@echo "Current infrastructure status:"
	@echo "=============================="
	@if [ -f terraform.tfstate ]; then \
		echo "Terraform state: EXISTS"; \
		terraform show -json | jq -r '.values.root_module.resources | length' | xargs -I {} echo "Resources deployed: {}"; \
		echo ""; \
		echo "Key outputs:"; \
		terraform output 2>/dev/null || echo "No outputs available"; \
	else \
		echo "Terraform state: NOT FOUND"; \
		echo "No infrastructure appears to be deployed"; \
	fi

logs: ## Show application logs (requires SSH access)
	@echo "Fetching application logs..."
	@INSTANCE_IP=$$(terraform output -raw ec2_instance_public_ip 2>/dev/null); \
	KEY_NAME=$$(terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="aws_instance") | .values.key_name // empty' 2>/dev/null); \
	if [ -n "$$INSTANCE_IP" ] && [ -n "$$KEY_NAME" ]; then \
		echo "Connecting to $$INSTANCE_IP..."; \
		ssh -i ~/.ssh/$$KEY_NAME.pem ec2-user@$$INSTANCE_IP "sudo journalctl -u amahoot-websocket -n 50"; \
	else \
		echo "Cannot retrieve instance IP or SSH key name"; \
	fi

ssh: ## SSH into the EC2 instance
	@INSTANCE_IP=$$(terraform output -raw ec2_instance_public_ip 2>/dev/null); \
	KEY_NAME=$$(terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="aws_instance") | .values.key_name // empty' 2>/dev/null); \
	if [ -n "$$INSTANCE_IP" ] && [ -n "$$KEY_NAME" ]; then \
		echo "Connecting to $$INSTANCE_IP..."; \
		ssh -i ~/.ssh/$$KEY_NAME.pem ec2-user@$$INSTANCE_IP; \
	else \
		echo "Cannot retrieve instance IP or SSH key name"; \
	fi

format: ## Format Terraform files
	@echo "Formatting Terraform files..."
	@terraform fmt

check: ## Run all checks (validate, format, test)
	@echo "Running all checks..."
	@make format
	@make validate
	@if [ -f terraform.tfstate ]; then make test; fi

backup: ## Create backup of current state
	@echo "Creating backup..."
	@mkdir -p backups
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	if [ -f terraform.tfstate ]; then \
		cp terraform.tfstate backups/terraform.tfstate.backup.$$TIMESTAMP; \
		echo "State backed up to backups/terraform.tfstate.backup.$$TIMESTAMP"; \
	fi; \
	tar -czf backups/config_backup_$$TIMESTAMP.tar.gz *.tf *.tfvars *.sh *.md 2>/dev/null || true; \
	echo "Configuration backed up to backups/config_backup_$$TIMESTAMP.tar.gz"

info: ## Show infrastructure information
	@echo "Infrastructure Information"
	@echo "========================="
	@echo "Project: Amahoot WebSocket Server"
	@echo "Terraform Version: $$(terraform version | head -n1)"
	@echo "AWS CLI Version: $$(aws --version 2>&1 | head -n1)"
	@echo "AWS Account: $$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'Not configured')"
	@echo "AWS Region: $$(aws configure get region 2>/dev/null || echo 'Not configured')"
	@echo ""
	@if [ -f terraform.tfvars ]; then \
		echo "Configuration file: terraform.tfvars (exists)"; \
	else \
		echo "Configuration file: terraform.tfvars (missing - run 'make setup')"; \
	fi

# Development targets
dev-deploy: setup validate deploy test ## Complete development deployment workflow

prod-deploy: ## Production deployment with extra safety checks
	@echo "Production deployment workflow..."
	@echo "WARNING: This will deploy to production!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		make backup && make validate && make deploy && make test; \
	else \
		echo "Production deployment cancelled"; \
	fi

# Monitoring targets
monitor: ## Show real-time application status
	@echo "Monitoring application status..."
	@INSTANCE_IP=$$(terraform output -raw ec2_instance_public_ip 2>/dev/null); \
	if [ -n "$$INSTANCE_IP" ]; then \
		echo "Instance IP: $$INSTANCE_IP"; \
		echo "Health check: http://$$INSTANCE_IP:5000/health"; \
		echo "WebSocket URL: ws://$$INSTANCE_IP:5000"; \
		echo ""; \
		echo "Testing connectivity..."; \
		curl -s -f "http://$$INSTANCE_IP:5000/health" && echo "✓ HTTP health check passed" || echo "✗ HTTP health check failed"; \
	else \
		echo "No instance IP found - infrastructure may not be deployed"; \
	fi

# Utility targets
update-deps: ## Update Terraform providers
	@echo "Updating Terraform providers..."
	@terraform init -upgrade

docs: ## Generate documentation
	@echo "Generating documentation..."
	@terraform-docs markdown table . > TERRAFORM_DOCS.md
	@echo "Documentation generated in TERRAFORM_DOCS.md"

security-scan: ## Run security scan on Terraform configuration
	@echo "Running security scan..."
	@if command -v tfsec >/dev/null 2>&1; then \
		tfsec .; \
	else \
		echo "tfsec not installed. Install with: brew install tfsec"; \
	fi