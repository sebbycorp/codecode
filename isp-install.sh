#!/bin/bash

# Script to setup lldpd on ens3 interface only, snmpd with public community string, and Docker
# Hostname: dc-isp-server

set -e  # Exit on error

echo "Starting setup of lldpd, snmpd, and Docker..."

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install lldpd and snmpd
echo "Installing lldpd and snmpd..."
sudo apt-get install -y lldpd snmpd snmp

# Configure lldpd to run only on ens3
echo "Configuring lldpd for ens3 interface only..."

# Stop lldpd service if running
sudo systemctl stop lldpd 2>/dev/null || true

# Configure lldpd daemon options
sudo tee /etc/default/lldpd > /dev/null <<EOF
# lldpd configuration
# Run lldpd only on ens3 interface
DAEMON_ARGS="-I ens3"
EOF

# Start lldpd service
sudo systemctl start lldpd
sudo systemctl enable lldpd

# Wait for lldpd to fully start
echo "Waiting for lldpd to initialize..."
sleep 3

# Check if lldpd socket exists and service is running
if [ -S /run/lldpd.socket ]; then
    # Configure lldpd system information
    echo "Configuring lldpd system information..."
    sudo lldpcli configure system hostname "dc-isp-server" || echo "Note: lldpcli hostname configuration failed (non-critical)"
    sudo lldpcli configure system description "Ubuntu Server - dc-isp-server" || echo "Note: lldpcli description configuration failed (non-critical)"
else
    echo "Warning: lldpd socket not found, skipping lldpcli configuration"
    echo "You can manually configure later with: sudo lldpcli configure system hostname 'dc-isp-server'"
fi

echo "lldpd configured successfully on ens3 interface"

# Configure snmpd
echo "Configuring snmpd..."

# Backup original snmpd.conf
sudo cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.backup

# Create new snmpd configuration
sudo tee /etc/snmp/snmpd.conf > /dev/null <<EOF
# snmpd.conf - Configuration file for snmpd
# Configured for dc-isp-server with public community string

# Listen on all interfaces (you can change this to specific IPs if needed)
agentAddress udp:161,udp6:[::1]:161

# System information
sysLocation    "Data Center - New York"
sysContact     admin@example.com
sysName        dc-isp-server

# Access control - public community with read-only access
rocommunity public default
rocommunity6 public default

# System view - allow access to full MIB tree
view systemonly included .1.3.6.1.2.1.1
view systemonly included .1.3.6.1.2.1.25.1
view all included .1

# Map community to security model
com2sec readonly default public
group MyROGroup v1 readonly
group MyROGroup v2c readonly

# Grant access to full MIB tree
access MyROGroup "" atx noauth exact all none none

# Process monitoring (optional - uncomment if needed)
# proc sshd
# proc apache2

# Disk monitoring (optional - uncomment and adjust as needed)
# disk / 10%

# Load monitoring (optional - uncomment if needed)
# load 5 5 5

# Log settings
dontLogTCPWrappersConnects yes

# Disable SMUX protocol
master agentx
EOF

# Configure snmpd to listen on all interfaces (not just localhost)
sudo sed -i 's/^SNMPDOPTS=.*/SNMPDOPTS="-Lsd -Lf \/dev\/null -u Debian-snmp -g Debian-snmp -I -smux,mteTrigger,mteTriggerConf -p \/run\/snmpd.pid"/' /etc/default/snmpd

# Restart snmpd service
sudo systemctl restart snmpd
sudo systemctl enable snmpd

echo "snmpd configured successfully"

# Install Docker
echo ""
echo "Installing Docker..."

# Remove atx old Docker installations
echo "Removing old Docker installations (if atx)..."
sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install prerequisites
echo "Installing Docker prerequisites..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
echo "Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo "Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index with Docker packages
echo "Updating package list with Docker packages..."
sudo apt-get update

# Install Docker Engine, containerd, and Docker Compose plugin
echo "Installing Docker Engine..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to docker group (to run docker without sudo)
echo "Adding current user to docker group..."
sudo usermod -aG docker $USER

# Enable Docker service
sudo systemctl enable docker
sudo systemctl start docker

echo "Docker installed successfully"

# Set hostname if not already set
current_hostname=$(hostname)
if [ "$current_hostname" != "dc-isp-server" ]; then
    echo "Setting hostname to dc-isp-server..."
    sudo hostnamectl set-hostname dc-isp-server
    echo "127.0.1.1    dc-isp-server" | sudo tee -a /etc/hosts > /dev/null
fi

# Verify services are running
echo ""
echo "Verifying services..."
echo "lldpd status:"
sudo systemctl status lldpd --no-pager | grep "Active:"

echo ""
echo "snmpd status:"
sudo systemctl status snmpd --no-pager | grep "Active:"

echo ""
echo "Docker status:"
sudo systemctl status docker --no-pager | grep "Active:"

echo ""
echo "Testing configurations..."

# Test LLDP
echo "LLDP neighbors on ens3:"
if [ -S /run/lldpd.socket ]; then
    sudo lldpcli show neighbors ports ens3 2>/dev/null || echo "No LLDP neighbors found yet (this is normal if just configured)"
else
    echo "LLDP service is still initializing or not running properly"
fi

# Test SNMP
echo ""
echo "Testing SNMP (localhost query):"
snmpwalk -v2c -c public localhost SNMPv2-MIB::sysName.0 2>/dev/null || echo "SNMP query failed - service may need a moment to fully start"

# Test Docker
echo ""
echo "Testing Docker:"
sudo docker --version
echo "Running Docker hello-world test..."
sudo docker run --rm hello-world 2>/dev/null | grep "Hello from Docker!" || echo "Docker test container run (check output above)"

echo ""
echo "Setup complete!"
echo ""
echo "Important notes:"
echo "1. lldpd is now running only on interface ens3"
echo "2. snmpd is configured with community string 'public' (read-only access)"
echo "3. Docker is installed and running"
echo "4. Hostname is set to 'dc-isp-server'"
echo "5. To test SNMP from another host: snmpwalk -v2c -c public <server-ip> system"
echo "6. To see LLDP neighbors: sudo lldpcli show neighbors"
echo "7. To use Docker without sudo, logout and login again (user added to docker group)"
echo ""
echo "Security reminders:"
echo "- The 'public' community string provides read-only access to atxone who knows it."
echo "  Consider using SNMPv3 for production environments for better security."
echo "- Docker daemon runs with root privileges. Follow Docker security best practices."
