#!/bin/bash

# Setup Script for Amahoot WebSocket Server Infrastructure
# This script prepares the environment for Terraform deployment

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

# Main setup function
main() {
    echo "========================================"
    echo "Amahoot WebSocket Server Setup"
    echo "========================================"
    echo ""
    
    print_status "INFO" "Setting up environment..."
    
    # Make all shell scripts executable
    print_status "INFO" "Making shell scripts executable..."
    chmod +x *.sh
    print_status "SUCCESS" "Shell scripts are now executable"
    
    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f "terraform.tfvars" ]]; then
        print_status "INFO" "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        print_status "SUCCESS" "terraform.tfvars created"
        print_status "WARNING" "Please edit terraform.tfvars with your configuration before deploying"
    else
        print_status "INFO" "terraform.tfvars already exists"
    fi
    
    # Create backups directory
    mkdir -p backups
    print_status "SUCCESS" "Backups directory created"
    
    # Check prerequisites
    print_status "INFO" "Checking prerequisites..."
    
    local missing_tools=()
    
    for tool in terraform aws jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_status "WARNING" "Missing tools: ${missing_tools[*]}"
        print_status "INFO" "Please install the missing tools before proceeding"
    else
        print_status "SUCCESS" "All required tools are installed"
    fi
    
    # Check AWS configuration
    if command -v aws >/dev/null 2>&1; then
        if aws sts get-caller-identity >/dev/null 2>&1; then
            local account_id=$(aws sts get-caller-identity --query Account --output text)
            local region=$(aws configure get region)
            print_status "SUCCESS" "AWS CLI configured for account $account_id in region $region"
        else
            print_status "WARNING" "AWS CLI not configured. Run 'aws configure' to set up credentials"
        fi
    fi
    
    echo ""
    echo "========================================"
    print_status "SUCCESS" "Setup completed successfully!"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo "1. Edit terraform.tfvars with your configuration"
    echo "2. Run 'make validate' or './validate.sh' to validate configuration"
    echo "3. Run 'make deploy' or './deploy.sh' to deploy infrastructure"
    echo "4. Run 'make test' or './integration-test.sh' to test deployment"
    echo ""
    echo "For help: make help"
}

# Run main function
main "$@"