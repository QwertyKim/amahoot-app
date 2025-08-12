#!/bin/bash

# Integration Tests for Amahoot WebSocket Server Infrastructure
# This script tests the deployed infrastructure end-to-end

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_TIMEOUT=30
MAX_RETRIES=5
WEBSOCKET_TEST_MESSAGE='{"type":"ping","timestamp":'$(date +%s)'}'

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $status in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} [$timestamp] $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} [$timestamp] $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} [$timestamp] $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message"
            ;;
        "TEST")
            echo -e "${BLUE}[TEST]${NC} [$timestamp] $message"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to get Terraform outputs
get_terraform_output() {
    local output_name=$1
    terraform output -raw "$output_name" 2>/dev/null || echo ""
}

# Function to test HTTP connectivity
test_http_connectivity() {
    local instance_ip=$1
    local app_port=$2
    
    print_status "TEST" "Testing HTTP connectivity to $instance_ip:$app_port"
    
    local health_url="http://$instance_ip:$app_port/health"
    local retry_count=0
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        if curl -s -f --connect-timeout $TEST_TIMEOUT "$health_url" >/dev/null 2>&1; then
            print_status "SUCCESS" "HTTP health check passed"
            return 0
        else
            ((retry_count++))
            print_status "WARNING" "HTTP health check failed (attempt $retry_count/$MAX_RETRIES)"
            sleep 5
        fi
    done
    
    print_status "ERROR" "HTTP connectivity test failed after $MAX_RETRIES attempts"
    return 1
}

# Function to test WebSocket connectivity
test_websocket_connectivity() {
    local instance_ip=$1
    local app_port=$2
    
    print_status "TEST" "Testing WebSocket connectivity to $instance_ip:$app_port"
    
    if ! command_exists wscat; then
        print_status "WARNING" "wscat not found, skipping WebSocket test"
        print_status "INFO" "Install wscat with: npm install -g wscat"
        return 0
    fi
    
    local ws_url="ws://$instance_ip:$app_port"
    local test_result
    
    # Test WebSocket connection with timeout
    test_result=$(timeout $TEST_TIMEOUT wscat -c "$ws_url" -x "$WEBSOCKET_TEST_MESSAGE" 2>&1 || echo "TIMEOUT")
    
    if [[ "$test_result" == "TIMEOUT" ]]; then
        print_status "ERROR" "WebSocket connection timed out"
        return 1
    elif echo "$test_result" | grep -q "pong\|echo"; then
        print_status "SUCCESS" "WebSocket connectivity test passed"
        return 0
    else
        print_status "ERROR" "WebSocket test failed: $test_result"
        return 1
    fi
}

# Function to test DynamoDB connectivity
test_dynamodb_connectivity() {
    local table_name=$1
    local aws_region=$2
    
    print_status "TEST" "Testing DynamoDB connectivity for table $table_name"
    
    # Test table existence and basic operations
    if aws dynamodb describe-table --table-name "$table_name" --region "$aws_region" >/dev/null 2>&1; then
        print_status "SUCCESS" "DynamoDB table $table_name is accessible"
        
        # Test write operation
        local test_item='{"PK":{"S":"TEST"},"SK":{"S":"integration-test"},"timestamp":{"N":"'$(date +%s)'"}}'
        if aws dynamodb put-item --table-name "$table_name" --item "$test_item" --region "$aws_region" >/dev/null 2>&1; then
            print_status "SUCCESS" "DynamoDB write test passed"
            
            # Test read operation
            if aws dynamodb get-item --table-name "$table_name" --key '{"PK":{"S":"TEST"},"SK":{"S":"integration-test"}}' --region "$aws_region" >/dev/null 2>&1; then
                print_status "SUCCESS" "DynamoDB read test passed"
                
                # Cleanup test item
                aws dynamodb delete-item --table-name "$table_name" --key '{"PK":{"S":"TEST"},"SK":{"S":"integration-test"}}' --region "$aws_region" >/dev/null 2>&1
                print_status "INFO" "Test item cleaned up"
                
                return 0
            else
                print_status "ERROR" "DynamoDB read test failed"
                return 1
            fi
        else
            print_status "ERROR" "DynamoDB write test failed"
            return 1
        fi
    else
        print_status "ERROR" "DynamoDB table $table_name is not accessible"
        return 1
    fi
}

# Function to test EC2 instance health
test_ec2_health() {
    local instance_id=$1
    local aws_region=$2
    
    print_status "TEST" "Testing EC2 instance health for $instance_id"
    
    # Check instance state
    local instance_state=$(aws ec2 describe-instances --instance-ids "$instance_id" --region "$aws_region" --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "unknown")
    
    if [[ "$instance_state" == "running" ]]; then
        print_status "SUCCESS" "EC2 instance is running"
        
        # Check system status
        local system_status=$(aws ec2 describe-instance-status --instance-ids "$instance_id" --region "$aws_region" --query 'InstanceStatuses[0].SystemStatus.Status' --output text 2>/dev/null || echo "unknown")
        local instance_status=$(aws ec2 describe-instance-status --instance-ids "$instance_id" --region "$aws_region" --query 'InstanceStatuses[0].InstanceStatus.Status' --output text 2>/dev/null || echo "unknown")
        
        if [[ "$system_status" == "ok" && "$instance_status" == "ok" ]]; then
            print_status "SUCCESS" "EC2 instance status checks passed"
            return 0
        else
            print_status "WARNING" "EC2 instance status checks: System=$system_status, Instance=$instance_status"
            return 1
        fi
    else
        print_status "ERROR" "EC2 instance state: $instance_state"
        return 1
    fi
}

# Function to test security group rules
test_security_group() {
    local sg_id=$1
    local aws_region=$2
    local app_port=$3
    
    print_status "TEST" "Testing security group rules for $sg_id"
    
    # Check if required ports are open
    local sg_rules=$(aws ec2 describe-security-groups --group-ids "$sg_id" --region "$aws_region" --query 'SecurityGroups[0].IpPermissions' --output json 2>/dev/null || echo "[]")
    
    # Check for WebSocket port
    if echo "$sg_rules" | jq -e ".[] | select(.FromPort <= $app_port and .ToPort >= $app_port)" >/dev/null; then
        print_status "SUCCESS" "Security group allows traffic on port $app_port"
    else
        print_status "ERROR" "Security group does not allow traffic on port $app_port"
        return 1
    fi
    
    # Check for SSH port (if configured)
    if echo "$sg_rules" | jq -e '.[] | select(.FromPort == 22 and .ToPort == 22)' >/dev/null; then
        print_status "SUCCESS" "Security group allows SSH access"
    else
        print_status "INFO" "SSH access not configured in security group"
    fi
    
    return 0
}

# Function to test application logs
test_application_logs() {
    local instance_ip=$1
    local key_pair_name=$2
    
    print_status "TEST" "Testing application logs accessibility"
    
    if [[ -z "$key_pair_name" ]]; then
        print_status "WARNING" "No SSH key configured, skipping log test"
        return 0
    fi
    
    local key_file="$HOME/.ssh/${key_pair_name}.pem"
    if [[ ! -f "$key_file" ]]; then
        print_status "WARNING" "SSH key file not found: $key_file"
        return 0
    fi
    
    # Test SSH connectivity and log access
    if timeout $TEST_TIMEOUT ssh -i "$key_file" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ec2-user@$instance_ip" "sudo systemctl is-active amahoot-websocket" >/dev/null 2>&1; then
        print_status "SUCCESS" "Application service is active"
        return 0
    else
        print_status "WARNING" "Could not verify application service status via SSH"
        return 1
    fi
}

# Function to run all tests
run_integration_tests() {
    print_status "INFO" "Starting integration tests..."
    
    # Get Terraform outputs
    local instance_ip=$(get_terraform_output "ec2_instance_public_ip")
    local instance_id=$(get_terraform_output "ec2_instance_id")
    local sg_id=$(get_terraform_output "security_group_id")
    local table_name=$(get_terraform_output "dynamodb_table_name")
    local app_port=$(get_terraform_output "app_port" || echo "5000")
    local aws_region=$(get_terraform_output "aws_region" || aws configure get region)
    local key_pair_name=$(terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="aws_instance") | .values.key_name // empty' 2>/dev/null || echo "")
    
    # Validate required outputs
    if [[ -z "$instance_ip" ]]; then
        print_status "ERROR" "Could not get EC2 instance IP from Terraform outputs"
        return 1
    fi
    
    if [[ -z "$instance_id" ]]; then
        print_status "ERROR" "Could not get EC2 instance ID from Terraform outputs"
        return 1
    fi
    
    print_status "INFO" "Testing infrastructure with:"
    print_status "INFO" "  Instance IP: $instance_ip"
    print_status "INFO" "  Instance ID: $instance_id"
    print_status "INFO" "  App Port: $app_port"
    print_status "INFO" "  AWS Region: $aws_region"
    print_status "INFO" "  DynamoDB Table: $table_name"
    
    local test_results=()
    
    # Run individual tests
    print_status "INFO" "Running EC2 health test..."
    if test_ec2_health "$instance_id" "$aws_region"; then
        test_results+=("EC2_HEALTH:PASS")
    else
        test_results+=("EC2_HEALTH:FAIL")
    fi
    
    print_status "INFO" "Running security group test..."
    if test_security_group "$sg_id" "$aws_region" "$app_port"; then
        test_results+=("SECURITY_GROUP:PASS")
    else
        test_results+=("SECURITY_GROUP:FAIL")
    fi
    
    print_status "INFO" "Running HTTP connectivity test..."
    if test_http_connectivity "$instance_ip" "$app_port"; then
        test_results+=("HTTP_CONNECTIVITY:PASS")
    else
        test_results+=("HTTP_CONNECTIVITY:FAIL")
    fi
    
    print_status "INFO" "Running WebSocket connectivity test..."
    if test_websocket_connectivity "$instance_ip" "$app_port"; then
        test_results+=("WEBSOCKET_CONNECTIVITY:PASS")
    else
        test_results+=("WEBSOCKET_CONNECTIVITY:FAIL")
    fi
    
    print_status "INFO" "Running DynamoDB connectivity test..."
    if test_dynamodb_connectivity "$table_name" "$aws_region"; then
        test_results+=("DYNAMODB_CONNECTIVITY:PASS")
    else
        test_results+=("DYNAMODB_CONNECTIVITY:FAIL")
    fi
    
    print_status "INFO" "Running application logs test..."
    if test_application_logs "$instance_ip" "$key_pair_name"; then
        test_results+=("APPLICATION_LOGS:PASS")
    else
        test_results+=("APPLICATION_LOGS:FAIL")
    fi
    
    # Display test results
    echo ""
    echo "========================================"
    echo "Integration Test Results"
    echo "========================================"
    
    local passed=0
    local failed=0
    
    for result in "${test_results[@]}"; do
        local test_name=$(echo "$result" | cut -d: -f1)
        local test_status=$(echo "$result" | cut -d: -f2)
        
        if [[ "$test_status" == "PASS" ]]; then
            print_status "SUCCESS" "$test_name: PASSED"
            ((passed++))
        else
            print_status "ERROR" "$test_name: FAILED"
            ((failed++))
        fi
    done
    
    echo "========================================"
    print_status "INFO" "Test Summary: $passed passed, $failed failed"
    
    if [[ $failed -eq 0 ]]; then
        print_status "SUCCESS" "All integration tests passed!"
        return 0
    else
        print_status "ERROR" "$failed test(s) failed"
        return 1
    fi
}

# Main function
main() {
    echo "========================================"
    echo "Amahoot WebSocket Server Integration Tests"
    echo "========================================"
    echo ""
    
    # Check prerequisites
    if ! command_exists terraform; then
        print_status "ERROR" "Terraform is not installed"
        exit 1
    fi
    
    if ! command_exists aws; then
        print_status "ERROR" "AWS CLI is not installed"
        exit 1
    fi
    
    if ! command_exists jq; then
        print_status "ERROR" "jq is not installed"
        exit 1
    fi
    
    # Check if Terraform state exists
    if [[ ! -f "terraform.tfstate" ]]; then
        print_status "ERROR" "Terraform state file not found. Deploy infrastructure first."
        exit 1
    fi
    
    # Run tests
    if run_integration_tests; then
        print_status "SUCCESS" "Integration tests completed successfully!"
        exit 0
    else
        print_status "ERROR" "Integration tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"