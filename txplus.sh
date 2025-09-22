#!/bin/bash

# Script to deploy tac_plus-ng in Docker on Ubuntu and configure syslog for authentication and accounting logs
# Target syslog server: 172.16.10.118:514/UDP
# Logs: Authentication (successful/failed logins) and accounting (executed commands)

# Exit on errors
set -e

# Variables
CONFIG_DIR="$HOME/tacacs-ng/etc"
LOG_DIR="$HOME/tacacs-ng/log"
CONFIG_FILE="$CONFIG_DIR/tac_plus-ng.cfg"
SYSLOG_IP="172.16.10.118"
SYSLOG_PORT="514"
CONTAINER_NAME="tacacs-ng"
SHARED_SECRET="mysecret"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Step 1: Install Docker if not present
if ! command_exists docker; then
    echo "Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y docker.io
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker "$USER"
    echo "Docker installed. Please log out and back in to apply docker group changes, or run 'newgrp docker' in this session."
else
    echo "Docker already installed."
fi

# Step 2: Create directories
echo "Creating directories for configuration and logs..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# Step 3: Create tac_plus-ng configuration file
echo "Creating configuration file at $CONFIG_FILE..."
cat > "$CONFIG_FILE" << 'EOF'
# Global defaults
default authentication { permit = all }
default authorization { permit = all }
default accounting { permit = all }

# Logging setup: Define a log group for remote syslog
log syslog-remote {
    destination = 172.16.10.118:514  # Remote UDP syslog server
    syslog facility = AUTH           # Syslog facility
    syslog level = INFO             # Log level (INFO captures auth and acct events)
    syslog ident = tac_plus-ng      # Identifier in syslog messages
    timestamp = RFC3164             # Timestamp format for syslog
}

# Apply remote syslog to authentication logs (successful/failed logins)
authentication log = syslog-remote

# Apply remote syslog to accounting logs (commands and session events)
accounting log = syslog-remote

# Optional: Local logging for debugging
log local-auth {
    destination = "/var卓

System: /var/log/tac_plus-ng/auth.log"
}
# authentication log = local-auth  # Uncomment to enable local auth logging
# accounting log = local-auth      # Uncomment to enable local acct logging

# Server listener
id = tac_plus {
    listen = { port = 49 }
    key = "mysecret"  # Shared secret for Cisco/Arista
}

# Simple local user for testing
group = admin {
    default service = permit
    member = admin
}

user = admin {
    member = admin
    login = cleartext "secret123"  # Plaintext password (use crypt for production)
}
EOF

# Secure the config file
chmod 600 "$CONFIG_FILE"
echo "Configuration file created and secured."

# Step 4: Pull the tac_plus-ng Docker image
echo "Pulling tac_plus-ng Docker image..."
docker pull christianbecker/tac_plus-ng

# Step 5: Stop and remove any existing container with the same name
if [ "$(docker ps -aq -f name="$CONTAINER_NAME")" ]; then
    echo "Stopping and removing existing $CONTAINER_NAME container..."
    docker stop "$CONTAINER_NAME" || true
    docker rm "$CONTAINER_NAME" || true
fi

# Step 6: Run the Docker container
echo "Starting tac_plus-ng container..."
docker run --name "$CONTAINER_NAME" \
    -p 49:49/udp \
    -v "$(pwd)/etc/tac_plus-ng.cfg:/usr/local/etc/tac_plus-ng.cfg:ro" \
    -v "$(pwd)/log:/var/log" \
    -d --restart=always \
    christianbecker/tac_plus-ng

# Step 7: Verify container is running
if docker ps | grep -q "$CONTAINER_NAME"; then
    echo "TACACS+ container is running successfully."
else
    echo "Error: Container failed to start. Check logs with 'docker logs $CONTAINER_NAME'."
    exit 1
fi

# Step 8: Test syslog connectivity
echo "Testing syslog connectivity to $SYSLOG_IP:$SYSLOG_PORT..."
echo "test message from tac_plus-ng setup" | nc -u -w 1 "$SYSLOG_IP" "$SYSLOG_PORT" || {
    echo "Warning: Failed to send test syslog message. Ensure $SYSLOG_IP:$SYSLOG_PORT is reachable and UDP is allowed."
}

# Final instructions
echo "TACACS+ server deployed. Test with a TACACS+ client (user: admin, password: secret123)."
echo "Authentication (successful/failed) and accounting (commands) logs will be sent to $SYSLOG_IP:$SYSLOG_PORT (facility: AUTH, level: INFO)."
echo "Check container logs: 'docker logs $CONTAINER_NAME'."
echo "Local logs (if enabled) are in $LOG_DIR."
echo "For Cisco/Arista config examples, see below. For production: Update $CONFIG_FILE with secure user backend (e.g., PAM/LDAP)."
echo ""
echo "Cisco Configuration (IOS/IOS-XE):"
echo "--------------------------------"
echo "enable"
echo "configure terminal"
echo " aaa new-model"
echo " tacacs server tacacs1"
echo "  address ipv4 172.16.10.100"
echo "  key mysecret"
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
echo " tacacs-server host 172.16.10.100"
echo " tacacs-server key 7 mysecret"
echo " username fallback privilege 15 secret fallbackpass"
echo "end"
echo "write"
