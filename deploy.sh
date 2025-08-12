#!/bin/bash

# Deployment Script for Amahoot WebSocket Server Infrastructure
# This script automates the deployment process with proper validation and error handling

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/deployment.log"
BACKUP_DIR="$SCRIPT_DIR/backups"
TERRAFORM_STATE_BACKUP="$BACKUP_DIR/terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    for tool in terraform aws jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_status "ERROR" "Missing required tools: ${missing_tools[*]}"
        print_status "INFO" "Please install the missing tools and try again"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "ERROR" "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    print_status "SUCCESS" "Using Terraform version $tf_version"
    
    # Check AWS account and region
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    print_status "SUCCESS" "Deploying to AWS account $account_id in region $region"
}

# Function to validate configuration
validate_configuration() {
    print_status "INFO" "Validating configuration..."
    
    # Check if terraform.tfvars exists
    if [[ ! -f "terraform.tfvars" ]]; then
        print_status "ERROR" "terraform.tfvars file not found"
        print_status "INFO" "Copy terraform.tfvars.example to terraform.tfvars and customize"
        exit 1
    fi
    
    # Run validation script
    if [[ -f "validate.sh" ]]; then
        print_status "INFO" "Running validation script..."
        bash validate.sh
    else
        print_status "WARNING" "Validation script not found, skipping detailed validation"
    fi
    
    print_status "SUCCESS" "Configuration validation completed"
}

# Function to create backup
create_backup() {
    print_status "INFO" "Creating backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup terraform state if it exists
    if [[ -f "terraform.tfstate" ]]; then
        cp "terraform.tfstate" "$TERRAFORM_STATE_BACKUP"
        print_status "SUCCESS" "Terraform state backed up to $TERRAFORM_STATE_BACKUP"
    fi
    
    # Backup configuration files
    local config_backup="$BACKUP_DIR/config_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$config_backup" *.tf *.tfvars user-data.sh 2>/dev/null || true
    print_status "SUCCESS" "Configuration files backed up to $config_backup"
}

# Function to initialize Terraform
initialize_terraform() {
    print_status "INFO" "Initializing Terraform..."
    
    if terraform init; then
        print_status "SUCCESS" "Terraform initialized successfully"
    else
        print_status "ERROR" "Terraform initialization failed"
        exit 1
    fi
}

# Function to plan deployment
plan_deployment() {
    print_status "INFO" "Planning deployment..."
    
    local plan_file="tfplan_$(date +%Y%m%d_%H%M%S)"
    
    if terraform plan -out="$plan_file"; then
        print_status "SUCCESS" "Terraform plan completed successfully"
        
        # Show plan summary
        local plan_summary=$(terraform show -json "$plan_file" | jq -r '
            .planned_values.root_module.resources | length as $total |
            "Plan Summary: \($total) resources to be created"
        ')
        print_status "INFO" "$plan_summary"
        
        echo "$plan_file"
    else
        print_status "ERROR" "Terraform plan failed"
        exit 1
    fi
}

# Function to apply deployment
apply_deployment() {
    local plan_file=$1
    
    print_status "INFO" "Applying deployment..."
    print_status "WARNING" "This will create AWS resources that may incur costs"
    
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        read -p "Do you want to proceed with the deployment? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_status "INFO" "Deployment cancelled by user"
            rm -f "$plan_file"
            exit 0
        fi
    fi
    
    if terraform apply "$plan_file"; then
        print_status "SUCCESS" "Deployment completed successfully"
        rm -f "$plan_file"
    else
        print_status "ERROR" "Deployment failed"
        rm -f "$plan_file"
        exit 1
    fi
}

# Function to validate deployment
validate_deployment() {
    print_status "INFO" "Validating deployment..."
    
    # Get outputs
    local instance_ip=$(terraform output -raw ec2_instance_public_ip 2>/dev/null || echo "")
    local websocket_url=$(terraform output -raw websocket_server_url 2>/dev/null || echo "")
    
    if [[ -n "$instance_ip" ]]; then
        print_status "SUCCESS" "EC2 instance deployed with IP: $instance_ip"
        
        # Wait for instance to be ready
        print_status "INFO" "Waiting for instance to be ready..."
        sleep 30
        
        # Test HTTP health check
        local health_url="http://$instance_ip:$(terraform output -raw app_port 2>/dev/null || echo "5000")/health"
        print_status "INFO" "Testing health endpoint: $health_url"
        
        local max_attempts=10
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if curl -s -f "$health_url" >/dev/null 2>&1; then
                print_status "SUCCESS" "Application is responding to health checks"
                break
            else
                print_status "INFO" "Attempt $attempt/$max_attempts: Application not ready yet, waiting..."
                sleep 30
                ((attempt++))
            fi
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            print_status "WARNING" "Application health check failed after $max_attempts attempts"
            print_status "INFO" "Check application logs: sudo journalctl -u amahoot-websocket -f"
        fi
    else
        print_status "ERROR" "Failed to get instance IP from Terraform outputs"
    fi
}

# Function to display deployment summary
display_summary() {
    print_status "INFO" "Deployment Summary"
    echo "===========================================" | tee -a "$LOG_FILE"
    
    # Display all outputs
    terraform output | tee -a "$LOG_FILE"
    
    echo "===========================================" | tee -a "$LOG_FILE"
    print_status "INFO" "Deployment log saved to: $LOG_FILE"
    print_status "INFO" "Backups saved to: $BACKUP_DIR"
}

# Function to cleanup on error
cleanup_on_error() {
    print_status "ERROR" "Deployment failed, cleaning up..."
    
    # Remove any temporary plan files
    rm -f tfplan_*
    
    # Optionally destroy resources if deployment failed
    if [[ "$CLEANUP_ON_ERROR" == "true" ]]; then
        print_status "WARNING" "Destroying resources due to failed deployment..."
        terraform destroy -auto-approve
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -a, --auto-approve    Skip interactive approval"
    echo "  -c, --cleanup         Cleanup resources on error"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AUTO_APPROVE=true     Skip interactive approval"
    echo "  CLEANUP_ON_ERROR=true Cleanup resources on error"
}

# Main deployment function
main() {
    local auto_approve=false
    local cleanup_on_error=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--auto-approve)
                auto_approve=true
                shift
                ;;
            -c|--cleanup)
                cleanup_on_error=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_status "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set environment variables
    if [[ "$auto_approve" == "true" ]]; then
        export AUTO_APPROVE=true
    fi
    
    if [[ "$cleanup_on_error" == "true" ]]; then
        export CLEANUP_ON_ERROR=true
    fi
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    echo "========================================"
    echo "Amahoot WebSocket Server Deployment"
    echo "========================================"
    echo ""
    
    check_prerequisites
    validate_configuration
    create_backup
    initialize_terraform
    
    local plan_file
    plan_file=$(plan_deployment)
    
    apply_deployment "$plan_file"
    validate_deployment
    display_summary
    
    print_status "SUCCESS" "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"