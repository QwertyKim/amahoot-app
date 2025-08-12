#!/bin/bash

# User Data Script for Amahoot WebSocket Server EC2 Instance
# This script sets up the Node.js environment and deploys the application

set -e  # Exit on any error

# Variables from Terraform
APP_PORT="${app_port}"
AWS_REGION="${aws_region}"
DYNAMODB_TABLE_NAME="${dynamodb_table_name}"
CORS_ORIGIN="${cors_origin}"
GITHUB_REPO_URL="${github_repo_url}"
APP_DIRECTORY="${app_directory}"

# Log file for debugging
LOG_FILE="/var/log/amahoot-setup.log"
exec > >(tee -a $LOG_FILE)
exec 2>&1

echo "=== Amahoot WebSocket Server Setup Started at $(date) ==="
echo "Configuration:"
echo "  APP_PORT: $APP_PORT"
echo "  AWS_REGION: $AWS_REGION"
echo "  DYNAMODB_TABLE_NAME: $DYNAMODB_TABLE_NAME"
echo "  CORS_ORIGIN: $CORS_ORIGIN"
echo "  GITHUB_REPO_URL: $GITHUB_REPO_URL"
echo "  APP_DIRECTORY: $APP_DIRECTORY"
echo ""

# Update system packages
echo "Updating system packages..."
yum update -y

# Install required packages
echo "Installing required packages..."
yum install -y git curl wget

# Install Node.js 18.x (LTS)
echo "Installing Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

# Verify Node.js installation
echo "Node.js version: $(node --version)"
echo "NPM version: $(npm --version)"

# Create application user
echo "Creating application user..."
useradd -m -s /bin/bash amahoot || echo "User amahoot already exists"

# Create application directory
echo "Setting up application directory..."
APP_HOME="/home/amahoot/$APP_DIRECTORY"
mkdir -p $APP_HOME
chown amahoot:amahoot $APP_HOME

# Switch to application user for the rest of the setup
echo "Setting up application as amahoot user..."
sudo -u amahoot bash << 'EOF'
set -e

# Navigate to application directory
cd /home/amahoot

# If GitHub repo URL is provided, clone the repository
if [[ "${GITHUB_REPO_URL}" != "https://github.com/your-username/amahoot-websocket.git" ]]; then
    echo "Cloning application from GitHub..."
    git clone "${GITHUB_REPO_URL}" "${APP_DIRECTORY}" || {
        echo "Failed to clone repository. Creating application structure manually..."
        mkdir -p "${APP_DIRECTORY}"
    }
else
    echo "No valid GitHub repo URL provided. Creating application structure manually..."
    mkdir -p "${APP_DIRECTORY}"
fi

cd "${APP_DIRECTORY}"

# If the directory is empty or doesn't have package.json, create a basic structure
if [[ ! -f "package.json" ]]; then
    echo "Creating basic application structure..."
    
    # Create package.json
    cat > package.json << 'PACKAGE_EOF'
{
  "name": "amahoot-hackerton-websocket",
  "version": "1.0.0",
  "description": "Real-time quiz game websocket server",
  "main": "dist/server.js",
  "scripts": {
    "dev": "tsx src/server.ts",
    "build": "tsc",
    "start": "node dist/server.js",
    "test": "jest"
  },
  "dependencies": {
    "@aws-sdk/client-dynamodb": "^3.490.0",
    "@aws-sdk/lib-dynamodb": "^3.490.0",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1",
    "express": "^4.18.2",
    "socket.io": "^4.7.5",
    "uuid": "^9.0.1",
    "ws": "^8.14.2"
  },
  "devDependencies": {
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/jest": "^29.5.8",
    "@types/node": "^20.10.0",
    "@types/uuid": "^9.0.7",
    "@types/ws": "^8.18.1",
    "jest": "^29.7.0",
    "tsx": "^4.6.2",
    "typescript": "^5.3.3"
  }
}
PACKAGE_EOF

    # Create basic TypeScript config
    cat > tsconfig.json << 'TS_EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
TS_EOF

    # Create basic server structure if src doesn't exist
    if [[ ! -d "src" ]]; then
        mkdir -p src
        cat > src/server.ts << 'SERVER_EOF'
import { createServer } from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import express from 'express';
import cors from 'cors';

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

const server = createServer(app);
const wss = new WebSocketServer({ server });

console.log('WebSocket server starting...');

wss.on('connection', (ws: WebSocket) => {
  console.log('New WebSocket connection established');
  
  ws.on('message', (data: Buffer) => {
    try {
      const message = JSON.parse(data.toString());
      console.log('Received message:', message);
      
      // Echo the message back for now
      ws.send(JSON.stringify({
        type: 'echo',
        content: message,
        timestamp: Date.now()
      }));
    } catch (error) {
      console.error('Error processing message:', error);
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Invalid message format',
        timestamp: Date.now()
      }));
    }
  });
  
  ws.on('close', () => {
    console.log('WebSocket connection closed');
  });
  
  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
  });
});

server.listen(PORT, () => {
  console.log(`🚀 Server is running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`AWS Region: ${process.env.AWS_REGION || 'not set'}`);
  console.log(`DynamoDB Table: ${process.env.DYNAMODB_TABLE || 'not set'}`);
});
SERVER_EOF
    fi
fi

# Install dependencies
echo "Installing Node.js dependencies..."
npm install

# Build the application if TypeScript source exists
if [[ -f "tsconfig.json" ]] && [[ -d "src" ]]; then
    echo "Building TypeScript application..."
    npm run build || echo "Build failed, but continuing..."
fi

EOF

# Create environment file
echo "Creating environment configuration..."
cat > $APP_HOME/.env << ENV_EOF
PORT=$APP_PORT
AWS_REGION=$AWS_REGION
DYNAMODB_TABLE=$DYNAMODB_TABLE_NAME
CORS_ORIGIN=$CORS_ORIGIN
NODE_ENV=production
ENV_EOF

chown amahoot:amahoot $APP_HOME/.env

# Create systemd service file
echo "Creating systemd service..."
cat > /etc/systemd/system/amahoot-websocket.service << SERVICE_EOF
[Unit]
Description=Amahoot WebSocket Server
After=network.target

[Service]
Type=simple
User=amahoot
WorkingDirectory=$APP_HOME
EnvironmentFile=$APP_HOME/.env
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=amahoot-websocket

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_HOME

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Set up log rotation
echo "Setting up log rotation..."
cat > /etc/logrotate.d/amahoot-websocket << LOGROTATE_EOF
/var/log/amahoot-websocket.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 amahoot amahoot
    postrotate
        systemctl reload amahoot-websocket > /dev/null 2>&1 || true
    endscript
}
LOGROTATE_EOF

# Enable and start the service
echo "Enabling and starting the service..."
systemctl daemon-reload
systemctl enable amahoot-websocket
systemctl start amahoot-websocket

# Install CloudWatch agent (optional, for monitoring)
echo "Installing CloudWatch agent..."
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << CW_EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/amahoot-setup.log",
                        "log_group_name": "/aws/ec2/amahoot/setup",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Amahoot/WebSocket",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
CW_EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Wait a moment for the service to start
sleep 5

# Check service status
echo "Checking service status..."
systemctl status amahoot-websocket --no-pager

# Display final information
echo ""
echo "=== Setup Complete ==="
echo "Service Status: $(systemctl is-active amahoot-websocket)"
echo "Application URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):$APP_PORT"
echo "WebSocket URL: ws://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):$APP_PORT"
echo ""
echo "Useful commands:"
echo "  Check service status: sudo systemctl status amahoot-websocket"
echo "  View logs: sudo journalctl -u amahoot-websocket -f"
echo "  Restart service: sudo systemctl restart amahoot-websocket"
echo ""
echo "Setup completed at $(date)"
echo "=== End of Setup ==="