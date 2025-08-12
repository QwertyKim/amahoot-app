# Troubleshooting Guide for Amahoot WebSocket Server Infrastructure

This guide provides solutions for common issues encountered when deploying and managing the Amahoot WebSocket server infrastructure.

## Table of Contents

1. [Deployment Issues](#deployment-issues)
2. [Application Issues](#application-issues)
3. [Network Connectivity Issues](#network-connectivity-issues)
4. [AWS Service Issues](#aws-service-issues)
5. [Performance Issues](#performance-issues)
6. [Security Issues](#security-issues)
7. [Monitoring and Logging](#monitoring-and-logging)
8. [Common Error Messages](#common-error-messages)

## Deployment Issues

### Terraform Validation Errors

**Problem**: Terraform validation fails with syntax errors
```bash
Error: Invalid reference
```

**Solution**:
1. Run the validation script:
   ```bash
   bash validate.sh
   ```
2. Check for typos in variable names and resource references
3. Ensure all required variables are defined in `terraform.tfvars`
4. Validate JSON syntax in user-data script templates

### AWS Credentials Issues

**Problem**: AWS authentication failures
```bash
Error: NoCredentialsError: Unable to locate credentials
```

**Solution**:
1. Configure AWS CLI:
   ```bash
   aws configure
   ```
2. Verify credentials:
   ```bash
   aws sts get-caller-identity
   ```
3. Check IAM permissions for required services (EC2, DynamoDB, IAM, VPC)

### Terraform State Lock Issues

**Problem**: Terraform state is locked
```bash
Error: Error locking state: ConditionalCheckFailedException
```

**Solution**:
1. Wait for other operations to complete
2. Force unlock if necessary (use with caution):
   ```bash
   terraform force-unlock <LOCK_ID>
   ```
3. Check for crashed Terraform processes

### Resource Quota Exceeded

**Problem**: AWS service limits exceeded
```bash
Error: VcpuLimitExceeded: You have requested more vCPU capacity than your current vCPU limit
```

**Solution**:
1. Check current service limits in AWS console
2. Request limit increases through AWS Support
3. Use smaller instance types or different regions
4. Clean up unused resources

## Application Issues

### Application Not Starting

**Problem**: WebSocket server fails to start

**Diagnosis**:
1. Check application logs:
   ```bash
   ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>
   sudo journalctl -u amahoot-websocket -f
   ```

2. Check system logs:
   ```bash
   sudo tail -f /var/log/messages
   ```

**Common Solutions**:
1. **Port already in use**:
   ```bash
   sudo netstat -tlnp | grep :5000
   sudo kill -9 <PID>
   sudo systemctl restart amahoot-websocket
   ```

2. **Missing dependencies**:
   ```bash
   cd /home/amahoot/amahoot-websocket
   npm install
   sudo systemctl restart amahoot-websocket
   ```

3. **Environment variables not set**:
   ```bash
   sudo systemctl edit amahoot-websocket
   # Add environment variables
   sudo systemctl restart amahoot-websocket
   ```

### Database Connection Issues

**Problem**: Cannot connect to DynamoDB

**Diagnosis**:
1. Check IAM role permissions:
   ```bash
   aws sts get-caller-identity
   aws iam get-role --role-name amahoot-websocket-ec2-role
   ```

2. Test DynamoDB access:
   ```bash
   aws dynamodb list-tables --region us-east-1
   ```

**Solutions**:
1. Verify IAM role is attached to EC2 instance
2. Check DynamoDB table exists and is in correct region
3. Verify security group allows outbound HTTPS traffic
4. Check AWS region configuration in application

### Memory or CPU Issues

**Problem**: Application crashes due to resource constraints

**Diagnosis**:
1. Check system resources:
   ```bash
   top
   free -h
   df -h
   ```

2. Check application memory usage:
   ```bash
   ps aux | grep node
   ```

**Solutions**:
1. Upgrade to larger instance type
2. Optimize application code
3. Add swap space:
   ```bash
   sudo dd if=/dev/zero of=/swapfile bs=1024 count=1048576
   sudo mkswap /swapfile
   sudo swapon /swapfile
   ```

## Network Connectivity Issues

### Cannot Access WebSocket Server

**Problem**: WebSocket connections fail or timeout

**Diagnosis**:
1. Test HTTP connectivity:
   ```bash
   curl -v http://<instance-ip>:5000/health
   ```

2. Test WebSocket connectivity:
   ```bash
   wscat -c ws://<instance-ip>:5000
   ```

3. Check security group rules:
   ```bash
   aws ec2 describe-security-groups --group-ids <sg-id>
   ```

**Solutions**:
1. **Security group not allowing traffic**:
   - Add inbound rule for port 5000 from 0.0.0.0/0
   - Ensure outbound rules allow all traffic

2. **Instance not in public subnet**:
   - Verify subnet has route to Internet Gateway
   - Check route table associations

3. **Application not binding to correct interface**:
   - Ensure application binds to 0.0.0.0, not 127.0.0.1
   - Check application configuration

### SSH Access Issues

**Problem**: Cannot SSH to EC2 instance

**Diagnosis**:
1. Check security group SSH rules
2. Verify key pair is correct
3. Test connectivity:
   ```bash
   telnet <instance-ip> 22
   ```

**Solutions**:
1. Add SSH rule to security group (port 22)
2. Verify key file permissions:
   ```bash
   chmod 400 ~/.ssh/your-key.pem
   ```
3. Use correct username (ec2-user for Amazon Linux)

## AWS Service Issues

### DynamoDB Throttling

**Problem**: DynamoDB operations are being throttled
```bash
Error: ProvisionedThroughputExceededException
```

**Solutions**:
1. Switch to On-Demand billing mode (already configured)
2. Implement exponential backoff in application
3. Optimize query patterns
4. Use batch operations where possible

### EC2 Instance Launch Failures

**Problem**: EC2 instance fails to launch

**Common Causes and Solutions**:
1. **Insufficient capacity**: Try different availability zone or instance type
2. **Invalid AMI**: Verify AMI ID is correct for the region
3. **Security group issues**: Check security group exists and rules are valid
4. **Subnet issues**: Ensure subnet exists and has available IP addresses

### IAM Permission Errors

**Problem**: Access denied errors for AWS services

**Diagnosis**:
1. Check current permissions:
   ```bash
   aws iam simulate-principal-policy --policy-source-arn <role-arn> --action-names dynamodb:GetItem --resource-arns <table-arn>
   ```

**Solutions**:
1. Review and update IAM policies
2. Ensure policies are attached to correct role
3. Check for explicit deny statements
4. Verify resource ARNs are correct

## Performance Issues

### High Latency

**Problem**: WebSocket connections have high latency

**Diagnosis**:
1. Check network latency:
   ```bash
   ping <instance-ip>
   traceroute <instance-ip>
   ```

2. Monitor application performance:
   ```bash
   sudo netstat -i
   sar -n DEV 1
   ```

**Solutions**:
1. Use instance types with enhanced networking
2. Deploy in region closer to users
3. Optimize application code
4. Use CloudFront for static content

### High Memory Usage

**Problem**: Application consumes excessive memory

**Diagnosis**:
1. Monitor memory usage:
   ```bash
   free -h
   ps aux --sort=-%mem | head
   ```

2. Check for memory leaks in application logs

**Solutions**:
1. Upgrade to instance with more memory
2. Optimize application code
3. Implement connection pooling
4. Add memory monitoring and alerts

## Security Issues

### Security Group Misconfigurations

**Problem**: Overly permissive or restrictive security groups

**Best Practices**:
1. Restrict SSH access to specific IP ranges
2. Use specific ports instead of port ranges
3. Regularly audit security group rules
4. Use security group references instead of CIDR blocks where possible

### SSL/TLS Issues

**Problem**: Insecure connections or certificate errors

**Solutions**:
1. Implement SSL termination at load balancer
2. Use AWS Certificate Manager for SSL certificates
3. Configure application to use HTTPS
4. Implement proper certificate validation

## Monitoring and Logging

### CloudWatch Logs Not Appearing

**Problem**: Application logs not showing in CloudWatch

**Solutions**:
1. Verify CloudWatch agent is installed and running:
   ```bash
   sudo systemctl status amazon-cloudwatch-agent
   ```

2. Check agent configuration:
   ```bash
   sudo cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
   ```

3. Restart CloudWatch agent:
   ```bash
   sudo systemctl restart amazon-cloudwatch-agent
   ```

### Missing Metrics

**Problem**: CloudWatch metrics not being collected

**Solutions**:
1. Verify IAM permissions for CloudWatch
2. Check metric filters and alarms configuration
3. Ensure application is generating metrics
4. Review CloudWatch agent logs

## Common Error Messages

### "Connection refused"
- **Cause**: Application not running or not listening on expected port
- **Solution**: Check application status and port configuration

### "Permission denied"
- **Cause**: Insufficient IAM permissions or file permissions
- **Solution**: Review and update permissions

### "Resource not found"
- **Cause**: AWS resource doesn't exist or wrong region
- **Solution**: Verify resource exists and check region configuration

### "Timeout"
- **Cause**: Network connectivity issues or slow response
- **Solution**: Check security groups, network configuration, and application performance

### "Invalid parameter"
- **Cause**: Incorrect configuration values
- **Solution**: Validate all configuration parameters and formats

## Getting Help

### Useful Commands for Diagnosis

1. **Check Terraform state**:
   ```bash
   terraform show
   terraform output
   ```

2. **Check AWS resources**:
   ```bash
   aws ec2 describe-instances
   aws dynamodb list-tables
   aws logs describe-log-groups
   ```

3. **Check application status**:
   ```bash
   sudo systemctl status amahoot-websocket
   sudo journalctl -u amahoot-websocket --since "1 hour ago"
   ```

4. **Network diagnostics**:
   ```bash
   netstat -tlnp
   ss -tlnp
   curl -v http://localhost:5000/health
   ```

### Log Locations

- **Application logs**: `sudo journalctl -u amahoot-websocket`
- **System logs**: `/var/log/messages`
- **CloudWatch logs**: AWS Console > CloudWatch > Log Groups
- **Deployment logs**: `deployment.log` in project directory
- **User data logs**: `/var/log/cloud-init-output.log`

### Support Resources

1. **AWS Documentation**: https://docs.aws.amazon.com/
2. **Terraform Documentation**: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
3. **Node.js Documentation**: https://nodejs.org/en/docs/
4. **AWS Support**: Create support case in AWS Console

### Emergency Procedures

1. **Application not responding**:
   ```bash
   sudo systemctl restart amahoot-websocket
   ```

2. **High resource usage**:
   ```bash
   sudo systemctl stop amahoot-websocket
   # Investigate and fix issue
   sudo systemctl start amahoot-websocket
   ```

3. **Complete infrastructure failure**:
   ```bash
   # Destroy and redeploy
   bash destroy.sh --auto-approve
   bash deploy.sh --auto-approve
   ```

Remember to always test changes in a development environment before applying to production!