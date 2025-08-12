#!/bin/bash

# Destroy Script for Amahoot WebSocket Server Infrastructure
# This script safely destroys the deployed infrastructure with proper validation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/destroy.log"
BACKUP_DIR="$SCRIPT_DIR/backups"

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
    
    # Check required tools
    for tool in terraform aws jq; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            print_status "ERROR" "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "ERROR" "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check if Terraform state exists
    if [[ ! -f "terraform.tfstate" ]]; then
        print_status "WARNING" "No Terraform state file found"
        print_status "INFO" "This might indicate that no infrastructure is deployed"
        
        read -p "Continue anyway? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            print_status "INFO" "Destroy operation cancelled"
            exit 0
        fi
    fi
    
    print_status "SUCCESS" "Prerequisites check completed"
}

# Function to show current infrastructure
show_current_infrastructure() {
    print_status "INFO" "Current infrastructure state:"
    
    if [[ -f "terraform.tfstate" ]]; then
        # Show resources that will be destroyed
        local resource_count=$(terraform show -json | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
        print_status "INFO" "Resources to be destroyed: $resource_count"
        
        # Show key resources
        if terraform output >/dev/null 2>&1; then
            echo "Key resources:" | tee -a "$LOG_FILE"
            terraform output | tee -a "$LOG_FILE"
        fi
    else
        print_status "INFO" "No state file found - no resources to destroy"
    fi
}

# Function to create final backup
create_final_backup() {
    print_status "INFO" "Creating final backup before destruction..."
    
    mkdir -p "$BACKUP_DIR"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local final_backup_dir="$BACKUP_DIR/final_backup_$timestamp"
    
    mkdir -p "$final_backup_dir"
    
    # Backup Terraform state
    if [[ -f "terraform.tfstate" ]]; then
        cp "terraform.tfstate" "$final_backup_dir/"
        print_status "SUCCESS" "Terraform state backed up"
    fi
    
    # Backup configuration files
    cp *.tf *.tfvars "$final_backup_dir/" 2>/dev/null || true
    cp user-data.sh "$final_backup_dir/" 2>/dev/null || true
    
    # Export current outputs to a file
    if terraform output >/dev/null 2>&1; then
        terraform output > "$final_backup_dir/terraform_outputs.txt"
        print_status "SUCCESS" "Terraform outputs saved"
    fi
    
    # Create infrastructure summary
    cat > "$final_backup_dir/infrastructure_summary.txt" << EOF
Infrastructure Destruction Summary
Generated: $(date)
AWS Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
AWS Region: $(aws configure get region 2>/dev/null || echo "unknown")

Resources destroyed on: $(date)
EOF
    
    print_status "SUCCESS" "Final backup created in $final_backup_dir"
}

# Function to plan destruction
plan_destruction() {
    print_status "INFO" "Planning infrastructure destruction..."
    
    local destroy_plan="destroy_plan_$(date +%Y%m%d_%H%M%S)"
    
    if terraform plan -destroy -out="$destroy_plan"; then
        print_status "SUCCESS" "Destruction plan created successfully"
        
        # Show destruction summary
        local resources_to_destroy=$(terraform show -json "$destroy_plan" | jq '.resource_changes | map(select(.change.actions[] == "delete")) | length' 2>/dev/null || echo "unknown")
        print_status "INFO" "Resources to be destroyed: $resources_to_destroy"
        
        echo "$destroy_plan"
    else
        print_status "ERROR" "Failed to create destruction plan"
        exit 1
    fi
}

# Function to confirm destruction
confirm_destruction() {
    print_status "WARNING" "This will permanently destroy all infrastructure resources!"
    print_status "WARNING" "This action cannot be undone!"
    
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        echo ""
        echo "Resources that will be destroyed:"
        terraform show -json | jq -r '.values.root_module.resources[]? | "- \(.type): \(.name)"' 2>/dev/null || echo "- Unable to list resources"
        echo ""
        
        print_status "WARNING" "Are you absolutely sure you want to destroy all resources?"
        read -p "Type 'yes' to confirm destruction: " -r
        
        if [[ "$REPLY" != "yes" ]]; then
            print_status "INFO" "Destruction cancelled by user"
            exit 0
        fi
        
        # Double confirmation for production-like environments
        if grep -q "prod\|production" terraform.tfvars 2>/dev/null; then
            print_status "WARNING" "Production environment detected!"
            read -p "Type 'DESTROY PRODUCTION' to confirm: " -r
            
            if [[ "$REPLY" != "DESTROY PRODUCTION" ]]; then
                print_status "INFO" "Production destruction cancelled"
                exit 0
            fi
        fi
    fi
    
    print_status "INFO" "Destruction confirmed"
}

# Function to execute destruction
execute_destruction() {
    local destroy_plan=$1
    
    print_status "INFO" "Executing infrastructure destruction..."
    
    if terraform apply "$destroy_plan"; then
        print_status "SUCCESS" "Infrastructure destroyed successfully"
        rm -f "$destroy_plan"
    else
        print_status "ERROR" "Infrastructure destruction failed"
        print_status "INFO" "Some resources may still exist and incur costs"
        print_status "INFO" "Check AWS console and clean up manually if needed"
        rm -f "$destroy_plan"
        exit 1
    fi
}

# Function to verify destruction
verify_destruction() {
    print_status "INFO" "Verifying destruction completion..."
    
    # Check if state file is empty or contains no resources
    if [[ -f "terraform.tfstate" ]]; then
        local remaining_resources=$(terraform show -json 2>/dev/null | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
        
        if [[ "$remaining_resources" == "0" ]]; then
            print_status "SUCCESS" "All resources have been destroyed"
        else
            print_status "WARNING" "$remaining_resources resources may still exist"
            print_status "INFO" "Run 'terraform show' to see remaining resources"
        fi
    fi
    
    # Optional: Check AWS resources directly
    print_status "INFO" "Checking for any remaining AWS resources..."
    
    # Check for EC2 instances with project tag
    local project_name=$(grep 'project_name.*=' terraform.tfvars 2>/dev/null | cut -d'"' -f2 || echo "amahoot-websocket")
    local remaining_instances=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=$project_name" "Name=instance-state-name,Values=running,pending,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_instances" && "$remaining_instances" != "None" ]]; then
        print_status "WARNING" "Found potentially remaining EC2 instances: $remaining_instances"
    else
        print_status "SUCCESS" "No remaining EC2 instances found"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    print_status "INFO" "Cleaning up local files..."
    
    if [[ "$CLEANUP_LOCAL" == "true" ]]; then
        # Remove Terraform files
        rm -f terraform.tfstate*
        rm -f .terraform.lock.hcl
        rm -rf .terraform/
        rm -f tfplan_*
        rm -f destroy_plan_*
        
        print_status "SUCCESS" "Local Terraform files cleaned up"
    else
        print_status "INFO" "Keeping local Terraform files (use --cleanup-local to remove)"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -a, --auto-approve    Skip interactive confirmation"
    echo "  -c, --cleanup-local   Remove local Terraform files after destruction"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AUTO_APPROVE=true     Skip interactive confirmation"
    echo "  CLEANUP_LOCAL=true    Remove local files after destruction"
}

# Main destruction function
main() {
    local auto_approve=false
    local cleanup_local=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--auto-approve)
                auto_approve=true
                shift
                ;;
            -c|--cleanup-local)
                cleanup_local=true
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
    
    if [[ "$cleanup_local" == "true" ]]; then
        export CLEANUP_LOCAL=true
    fi
    
    echo "========================================"
    echo "Amahoot WebSocket Server Destruction"
    echo "========================================"
    echo ""
    
    check_prerequisites
    show_current_infrastructure
    create_final_backup
    
    local destroy_plan
    destroy_plan=$(plan_destruction)
    
    confirm_destruction
    execute_destruction "$destroy_plan"
    verify_destruction
    cleanup_local_files
    
    echo ""
    echo "========================================"
    print_status "SUCCESS" "Infrastructure destruction completed!"
    echo "========================================"
    print_status "INFO" "Destruction log saved to: $LOG_FILE"
    print_status "INFO" "Final backup saved to: $BACKUP_DIR"
    print_status "INFO" "Please verify in AWS console that all resources are removed"
}

# Run main function with all arguments
main "$@"