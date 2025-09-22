#!/bin/bash

# Script to set up TACACS+ configuration for Docker deployment
# This version prepares everything but doesn't install Docker

# Exit on errors
set -e

# Variables
CONFIG_DIR="/home/root/tacacs-ng/etc"
LOG_DIR="/home/root/tacacs-ng/log"
CONFIG_FILE="$CONFIG_DIR/tac_plus.conf"
SYSLOG_IP="172.16.10.118"
SYSLOG_PORT="514"
CONTAINER_NAME="tacacs-ng"
SHARED_SECRET="mysecret"

echo "=== TACACS+ Configuration Setup ==="
echo ""

# Step 1: Create directories
echo "Creating directories for configuration and logs..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR"
chmod 700 "$CONFIG_DIR" "$LOG_DIR"

# Step 2: Create config file
echo "Creating TACACS+ configuration file..."
cat > "$CONFIG_FILE" << 'EOF'
key = "mysecret"

accounting syslog {
    server 172.16.10.118 514
    facility auth
    level info
}

user = admin {
    login = cleartext "secret123"
    service = shell {
        default command = permit
        set priv-lvl = 15
    }
}
EOF

# Secure the config file
chmod 600 "$CONFIG_FILE"
echo "Configuration file created and secured at: $CONFIG_FILE"

# Step 3: Create a Docker run script for later use
echo "Creating Docker run script..."
cat > "$CONFIG_DIR/../run-tacacs.sh" << EOF
#!/bin/bash
# Run TACACS+ container

CONTAINER_NAME="tacacs-ng"
CONFIG_FILE="$CONFIG_FILE"
LOG_DIR="$LOG_DIR"

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed. Please install Docker first."
    exit 1
fi

# Stop and remove any existing container
if [ "\$(docker ps -aq -f name="\$CONTAINER_NAME")" ]; then
    echo "Stopping and removing existing \$CONTAINER_NAME container..."
    docker stop "\$CONTAINER_NAME" || true
    docker rm "\$CONTAINER_NAME" || true
fi

# Pull the image
echo "Pulling fbotha/tac_plus Docker image..."
docker pull fbotha/tac_plus

# Run the container
echo "Starting tac_plus container..."
docker run --name "\$CONTAINER_NAME" \\
    -p 49:49/tcp \\
    -v "\$CONFIG_FILE:/etc/tac_plus/tac_plus.conf:ro" \\
    -v "\$LOG_DIR:/var/log/tac_plus" \\
    -d --restart=always \\
    fbotha/tac_plus

# Verify
sleep 5
if docker ps | grep -q "\$CONTAINER_NAME"; then
    echo "TACACS+ container is running successfully."
    docker ps | grep "\$CONTAINER_NAME"
else
    echo "Error: Container failed to start. Check logs with 'docker logs \$CONTAINER_NAME'."
    exit 1
fi
EOF

chmod +x "$CONFIG_DIR/../run-tacacs.sh"
echo "Docker run script created at: $CONFIG_DIR/../run-tacacs.sh"

# Step 4: Test syslog connectivity
echo ""
echo "Testing syslog connectivity to $SYSLOG_IP:$SYSLOG_PORT..."
echo "test message from tacacs setup" | nc -u -w 1 "$SYSLOG_IP" "$SYSLOG_PORT" || {
    echo "Warning: Failed to send test syslog message. Ensure $SYSLOG_IP:$SYSLOG_PORT is reachable and UDP is allowed."
}

# Step 5: Display configuration summary
echo ""
echo "=== Configuration Summary ==="
echo "Configuration directory: $CONFIG_DIR"
echo "Log directory: $LOG_DIR"
echo "Config file: $CONFIG_FILE"
echo "Syslog server: $SYSLOG_IP:$SYSLOG_PORT"
echo "TACACS+ port: TCP/49"
echo "Test user: admin / secret123"
echo ""
echo "=== Next Steps ==="
echo "1. Install Docker:"
echo "   - Try: curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh"
echo "   - Or manually install docker.io package when repositories are available"
echo ""
echo "2. Run the TACACS+ container:"
echo "   $CONFIG_DIR/../run-tacacs.sh"
echo ""
echo "=== Network Device Configuration Examples ==="
echo ""
echo "Cisco Configuration (IOS/IOS-XE):"
echo "--------------------------------"
echo "enable"
echo "configure terminal"
echo " aaa new-model"
echo " tacacs server tacacs1"
echo "  address ipv4 <YOUR-SERVER-IP>"
echo "  key mysecret"
echo "  port 49"
echo " aaa authentication login default group tacacs1 local"
echo " aaa authorization exec default group tacacs1 local"
echo " aaa accounting exec default start-stop group tacacs1"
echo " aaa accounting commands 15 default start-stop group tacacs1"
echo " username fallback privilege 15 secret fallbackpass"
echo " line vty 0 4"
echo "  login authentication default"
echo "  authorization exec default"
echo "end"
echo "write memory"
echo ""
echo "Arista Configuration (EOS):"
echo "--------------------------"
echo "enable"
echo "configure"
echo " aaa authentication login default group tacacs+ local"
echo " aaa authorization exec default group tacacs+ local"
echo " aaa accounting exec default start-stop group tacacs+"
echo " aaa accounting commands all default start-stop group tacacs+"
echo " tacacs-server host <YOUR-SERVER-IP> port 49"
echo " tacacs-server key 7 mysecret"
echo " username fallback privilege 15 secret fallbackpass"
echo "end"
echo "write"
