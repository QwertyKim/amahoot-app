# Terraform Tests for Amahoot WebSocket Server Infrastructure
# These tests validate the infrastructure configuration

# Test 1: Validate VPC Configuration
resource "test_assertions" "vpc_configuration" {
  component = "vpc"

  equal "vpc_cidr_valid" {
    description = "VPC CIDR should be valid"
    got         = can(cidrhost(aws_vpc.main.cidr_block, 0))
    want        = true
  }

  equal "vpc_dns_enabled" {
    description = "VPC should have DNS resolution enabled"
    got         = aws_vpc.main.enable_dns_support
    want        = true
  }

  equal "vpc_dns_hostnames_enabled" {
    description = "VPC should have DNS hostnames enabled"
    got         = aws_vpc.main.enable_dns_hostnames
    want        = true
  }
}

# Test 2: Validate Subnet Configuration
resource "test_assertions" "subnet_configuration" {
  component = "subnet"

  equal "public_subnet_in_vpc" {
    description = "Public subnet should be in the correct VPC"
    got         = aws_subnet.public.vpc_id
    want        = aws_vpc.main.id
  }

  equal "public_subnet_auto_assign_ip" {
    description = "Public subnet should auto-assign public IPs"
    got         = aws_subnet.public.map_public_ip_on_launch
    want        = true
  }

  check "subnet_cidr_within_vpc" {
    description = "Subnet CIDR should be within VPC CIDR"
    condition   = cidrsubnet(aws_vpc.main.cidr_block, 8, 1) == aws_subnet.public.cidr_block
  }
}

# Test 3: Validate Security Group Rules
resource "test_assertions" "security_group_rules" {
  component = "security_group"

  check "websocket_port_open" {
    description = "WebSocket port should be accessible"
    condition = anytrue([
      for rule in aws_security_group.websocket_server.ingress :
      rule.from_port <= var.app_port && rule.to_port >= var.app_port && rule.protocol == "tcp"
    ])
  }

  check "ssh_port_configured" {
    description = "SSH port should be configured if key pair is provided"
    condition = var.key_pair_name == null ? true : anytrue([
      for rule in aws_security_group.websocket_server.ingress :
      rule.from_port == 22 && rule.to_port == 22 && rule.protocol == "tcp"
    ])
  }

  check "outbound_traffic_allowed" {
    description = "Outbound traffic should be allowed"
    condition = anytrue([
      for rule in aws_security_group.websocket_server.egress :
      rule.from_port == 0 && rule.to_port == 0 && rule.protocol == "-1"
    ])
  }
}

# Test 4: Validate IAM Configuration
resource "test_assertions" "iam_configuration" {
  component = "iam"

  equal "ec2_assume_role_policy" {
    description = "EC2 role should have correct assume role policy"
    got         = jsondecode(aws_iam_role.ec2_role.assume_role_policy).Statement[0].Principal.Service
    want        = "ec2.amazonaws.com"
  }

  check "dynamodb_policy_attached" {
    description = "DynamoDB policy should be attached to EC2 role"
    condition   = aws_iam_role_policy_attachment.ec2_dynamodb.role == aws_iam_role.ec2_role.name
  }
}

# Test 5: Validate DynamoDB Configuration
resource "test_assertions" "dynamodb_configuration" {
  component = "dynamodb"

  equal "dynamodb_billing_mode" {
    description = "DynamoDB should use pay-per-request billing"
    got         = aws_dynamodb_table.game_data.billing_mode
    want        = "PAY_PER_REQUEST"
  }

  equal "dynamodb_hash_key" {
    description = "DynamoDB should have correct hash key"
    got         = aws_dynamodb_table.game_data.hash_key
    want        = "PK"
  }

  equal "dynamodb_range_key" {
    description = "DynamoDB should have correct range key"
    got         = aws_dynamodb_table.game_data.range_key
    want        = "SK"
  }

  equal "dynamodb_encryption_enabled" {
    description = "DynamoDB should have server-side encryption enabled"
    got         = aws_dynamodb_table.game_data.server_side_encryption[0].enabled
    want        = true
  }

  equal "dynamodb_pitr_enabled" {
    description = "DynamoDB should have point-in-time recovery enabled"
    got         = aws_dynamodb_table.game_data.point_in_time_recovery[0].enabled
    want        = true
  }
}

# Test 6: Validate EC2 Configuration
resource "test_assertions" "ec2_configuration" {
  component = "ec2"

  equal "ec2_instance_type" {
    description = "EC2 instance should use specified instance type"
    got         = aws_instance.websocket_server.instance_type
    want        = var.instance_type
  }

  equal "ec2_monitoring_enabled" {
    description = "EC2 detailed monitoring should be enabled"
    got         = aws_instance.websocket_server.monitoring
    want        = true
  }

  equal "ec2_ebs_optimized" {
    description = "EC2 instance should be EBS optimized"
    got         = aws_instance.websocket_server.ebs_optimized
    want        = true
  }

  equal "ec2_root_volume_encrypted" {
    description = "EC2 root volume should be encrypted"
    got         = aws_instance.websocket_server.root_block_device[0].encrypted
    want        = true
  }

  equal "ec2_subnet_placement" {
    description = "EC2 instance should be in public subnet"
    got         = aws_instance.websocket_server.subnet_id
    want        = aws_subnet.public.id
  }
}

# Test 7: Validate Network Connectivity
resource "test_assertions" "network_connectivity" {
  component = "networking"

  equal "internet_gateway_attached" {
    description = "Internet Gateway should be attached to VPC"
    got         = aws_internet_gateway.main.vpc_id
    want        = aws_vpc.main.id
  }

  check "public_route_configured" {
    description = "Public route table should have route to Internet Gateway"
    condition = anytrue([
      for route in aws_route_table.public.route :
      route.cidr_block == "0.0.0.0/0" && route.gateway_id == aws_internet_gateway.main.id
    ])
  }

  equal "route_table_association" {
    description = "Public subnet should be associated with public route table"
    got         = aws_route_table_association.public.subnet_id
    want        = aws_subnet.public.id
  }
}

# Test 8: Validate Resource Tagging
resource "test_assertions" "resource_tagging" {
  component = "tagging"

  check "vpc_tagged" {
    description = "VPC should have required tags"
    condition = alltrue([
      contains(keys(aws_vpc.main.tags), "Name"),
      contains(keys(aws_vpc.main.tags), "Project"),
      contains(keys(aws_vpc.main.tags), "Environment"),
      contains(keys(aws_vpc.main.tags), "ManagedBy")
    ])
  }

  check "ec2_tagged" {
    description = "EC2 instance should have required tags"
    condition = alltrue([
      contains(keys(aws_instance.websocket_server.tags), "Name"),
      contains(keys(aws_instance.websocket_server.tags), "Project"),
      contains(keys(aws_instance.websocket_server.tags), "Environment"),
      contains(keys(aws_instance.websocket_server.tags), "ManagedBy")
    ])
  }

  check "dynamodb_tagged" {
    description = "DynamoDB table should have required tags"
    condition = alltrue([
      contains(keys(aws_dynamodb_table.game_data.tags), "Name"),
      contains(keys(aws_dynamodb_table.game_data.tags), "Project"),
      contains(keys(aws_dynamodb_table.game_data.tags), "Environment"),
      contains(keys(aws_dynamodb_table.game_data.tags), "ManagedBy")
    ])
  }
}

# Test 9: Validate Variable Constraints
resource "test_assertions" "variable_validation" {
  component = "variables"

  check "port_in_valid_range" {
    description = "Application port should be in valid range"
    condition   = var.app_port >= 1024 && var.app_port <= 65535
  }

  check "instance_type_allowed" {
    description = "Instance type should be in allowed list"
    condition = contains([
      "t3.micro", "t3.small", "t3.medium", "t3.large",
      "t2.micro", "t2.small"
    ], var.instance_type)
  }

  check "vpc_cidr_valid_format" {
    description = "VPC CIDR should be in valid format"
    condition   = can(cidrhost(var.vpc_cidr, 0))
  }

  check "subnet_cidr_within_vpc" {
    description = "Subnet CIDR should be within VPC CIDR"
    condition   = can(cidrsubnet(var.vpc_cidr, 8, 1))
  }
}

# Test 10: Validate Outputs
resource "test_assertions" "output_validation" {
  component = "outputs"

  check "websocket_url_format" {
    description = "WebSocket URL should have correct format"
    condition = can(regex("^ws://[0-9.]+:[0-9]+$", 
      var.create_elastic_ip ? 
        "ws://${aws_eip.websocket_server[0].public_ip}:${var.app_port}" : 
        "ws://${aws_instance.websocket_server.public_ip}:${var.app_port}"
    ))
  }

  check "http_url_format" {
    description = "HTTP URL should have correct format"
    condition = can(regex("^http://[0-9.]+:[0-9]+$",
      var.create_elastic_ip ? 
        "http://${aws_eip.websocket_server[0].public_ip}:${var.app_port}" : 
        "http://${aws_instance.websocket_server.public_ip}:${var.app_port}"
    ))
  }
}