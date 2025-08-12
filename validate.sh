#!/bin/bash

# Terraform Validation Script for Amahoot WebSocket Server Infrastructure
# This script performs comprehensive validation of the Terraform configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Terraform version
validate_terraform_version() {
    print_status "INFO" "Checking Terraform version..."
    
    if ! command_exists terraform; then
        print_status "ERROR" "Terraform is not installed"
        exit 1
    fi
    
    local version=$(terraform version -json | jq -r '.terraform_version')
    local major=$(echo $version | cut -d. -f1)
    local minor=$(echo $version | cut -d. -f2)
    
    if [[ $major -lt 1 ]] || [[ $major -eq 1 && $minor -lt 0 ]]; then
        print_status "ERROR" "Terraform version $version is not supported. Minimum version: 1.0"
        exit 1
    fi
    
    print_status "SUCCESS" "Terraform version $version is supported"
}

# Function to validate AWS CLI configuration
validate_aws_cli() {
    print_status "INFO" "Checking AWS CLI configuration..."
    
    if ! command_exists aws; then
        print_status "WARNING" "AWS CLI is not installed. Skipping AWS validation."
        return 0
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "ERROR" "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    print_status "SUCCESS" "AWS CLI configured for account $account_id in region $region"
}

# Function to validate Terraform syntax
validate_terraform_syntax() {
    print_status "INFO" "Validating Terraform syntax..."
    
    if terraform fmt -check=true -diff=true .; then
        print_status "SUCCESS" "Terraform formatting is correct"
    else
        print_status "WARNING" "Terraform files need formatting. Run 'terraform fmt' to fix."
    fi
    
    terraform init -backend=false >/dev/null 2>&1
    
    if terraform validate; then
        print_status "SUCCESS" "Terraform configuration is valid"
    else
        print_status "ERROR" "Terraform configuration validation failed"
        exit 1
    fi
}

# Function to validate variable files
validate_variable_files() {
    print_status "INFO" "Validating variable files..."
    
    if [[ ! -f "terraform.tfvars.example" ]]; then
        print_status "ERROR" "terraform.tfvars.example file is missing"
        exit 1
    fi
    
    if [[ -f "terraform.tfvars" ]]; then
        print_status "SUCCESS" "terraform.tfvars file found"
        
        # Check for sensitive values in terraform.tfvars
        if grep -q "your-username" terraform.tfvars 2>/dev/null; then
            print_status "WARNING" "terraform.tfvars contains placeholder values. Please update with actual values."
        fi
    else
        print_status "WARNING" "terraform.tfvars file not found. Copy from terraform.tfvars.example and customize."
    fi
}

# Function to validate user data script
validate_user_data() {
    print_status "INFO" "Validating user data script..."
    
    if [[ ! -f "user-data.sh" ]]; then
        print_status "ERROR" "user-data.sh file is missing"
        exit 1
    fi
    
    # Check if script is executable
    if [[ ! -x "user-data.sh" ]]; then
        print_status "INFO" "Making user-data.sh executable"
        chmod +x user-data.sh
    fi
    
    # Basic syntax check for bash script
    if bash -n user-data.sh; then
        print_status "SUCCESS" "user-data.sh syntax is valid"
    else
        print_status "ERROR" "user-data.sh has syntax errors"
        exit 1
    fi
    
    # Check for required template variables
    local required_vars=("app_port" "aws_region" "dynamodb_table_name" "cors_origin")
    for var in "${required_vars[@]}"; do
        if ! grep -q "\${$var}" user-data.sh; then
            print_status "WARNING" "user-data.sh missing template variable: $var"
        fi
    done
}

# Function to validate security configurations
validate_security() {
    print_status "INFO" "Validating security configurations..."
    
    # Check for hardcoded sensitive values
    local sensitive_patterns=("password" "secret" "key" "token")
    local found_sensitive=false
    
    for pattern in "${sensitive_patterns[@]}"; do
        if grep -ri "$pattern" *.tf *.tfvars.example 2>/dev/null | grep -v "key_pair_name" | grep -v "hash_key" | grep -v "range_key"; then
            print_status "WARNING" "Potential sensitive data found containing '$pattern'"
            found_sensitive=true
        fi
    done
    
    if [[ $found_sensitive == false ]]; then
        print_status "SUCCESS" "No obvious sensitive data found in configuration files"
    fi
    
    # Check for overly permissive CIDR blocks
    if grep -q "0.0.0.0/0" *.tf 2>/dev/null; then
        print_status "WARNING" "Found 0.0.0.0/0 CIDR blocks. Consider restricting access in production."
    fi
}

# Function to validate resource naming
validate_naming() {
    print_status "INFO" "Validating resource naming conventions..."
    
    # Check if resources use consistent naming with project_name variable
    if grep -q 'Name = "${var.project_name}' *.tf; then
        print_status "SUCCESS" "Resources use consistent naming with project_name variable"
    else
        print_status "WARNING" "Some resources may not follow naming conventions"
    fi
}

# Function to validate documentation
validate_documentation() {
    print_status "INFO" "Validating documentation..."
    
    local required_docs=("README-terraform.md")
    for doc in "${required_docs[@]}"; do
        if [[ -f "$doc" ]]; then
            print_status "SUCCESS" "$doc found"
        else
            print_status "WARNING" "$doc is missing"
        fi
    done
}

# Function to run Terraform plan (dry run)
run_terraform_plan() {
    print_status "INFO" "Running Terraform plan (dry run)..."
    
    if [[ ! -f "terraform.tfvars" ]]; then
        print_status "WARNING" "Skipping terraform plan - terraform.tfvars not found"
        return 0
    fi
    
    # Initialize Terraform
    terraform init >/dev/null 2>&1
    
    # Run plan
    if terraform plan -out=tfplan >/dev/null 2>&1; then
        print_status "SUCCESS" "Terraform plan completed successfully"
        
        # Show plan summary
        local resources_to_add=$(terraform show -json tfplan | jq '.planned_values.root_module.resources | length')
        print_status "INFO" "Plan will create $resources_to_add resources"
        
        # Clean up plan file
        rm -f tfplan
    else
        print_status "ERROR" "Terraform plan failed"
        exit 1
    fi
}

# Function to validate outputs
validate_outputs() {
    print_status "INFO" "Validating output definitions..."
    
    if [[ ! -f "outputs.tf" ]]; then
        print_status "ERROR" "outputs.tf file is missing"
        exit 1
    fi
    
    # Check for required outputs
    local required_outputs=("ec2_instance_public_ip" "websocket_server_url" "dynamodb_table_name")
    for output in "${required_outputs[@]}"; do
        if grep -q "output \"$output\"" outputs.tf; then
            print_status "SUCCESS" "Output '$output' is defined"
        else
            print_status "WARNING" "Output '$output' is missing"
        fi
    done
}

# Function to check for best practices
check_best_practices() {
    print_status "INFO" "Checking Terraform best practices..."
    
    # Check for provider version constraints
    if grep -q 'version = "~>' *.tf; then
        print_status "SUCCESS" "Provider version constraints are specified"
    else
        print_status "WARNING" "Consider adding provider version constraints"
    fi
    
    # Check for resource tags
    if grep -q "default_tags" *.tf; then
        print_status "SUCCESS" "Default tags are configured"
    else
        print_status "WARNING" "Consider adding default tags for resource management"
    fi
    
    # Check for variable descriptions
    local vars_without_desc=$(grep -c "variable \"" variables.tf)
    local vars_with_desc=$(grep -c "description =" variables.tf)
    
    if [[ $vars_without_desc -eq $vars_with_desc ]]; then
        print_status "SUCCESS" "All variables have descriptions"
    else
        print_status "WARNING" "Some variables are missing descriptions"
    fi
}

# Main validation function
main() {
    echo "========================================"
    echo "Terraform Configuration Validation"
    echo "========================================"
    echo ""
    
    validate_terraform_version
    validate_aws_cli
    validate_terraform_syntax
    validate_variable_files
    validate_user_data
    validate_security
    validate_naming
    validate_documentation
    validate_outputs
    check_best_practices
    
    # Only run terraform plan if AWS is configured and tfvars exists
    if command_exists aws && aws sts get-caller-identity >/dev/null 2>&1 && [[ -f "terraform.tfvars" ]]; then
        run_terraform_plan
    else
        print_status "INFO" "Skipping terraform plan - AWS not configured or terraform.tfvars missing"
    fi
    
    echo ""
    echo "========================================"
    print_status "SUCCESS" "Validation completed successfully!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "1. Copy terraform.tfvars.example to terraform.tfvars"
    echo "2. Customize the values in terraform.tfvars"
    echo "3. Run 'terraform init' to initialize"
    echo "4. Run 'terraform plan' to review changes"
    echo "5. Run 'terraform apply' to deploy"
}

# Run main function
main "$@"