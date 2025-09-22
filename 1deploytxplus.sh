#!/bin/bash
# TACACS+ Docker deployment script
# Server IP: 172.16.10.241 (interface ens2)
# Syslog server: 172.16.10.118:514
# Using rickronen/tac-plus:1.0 image

# Exit on errors
set -e

# Variables
CONFIG_DIR="$HOME/tacacs-ng/etc"
LOG_DIR="$HOME/tacacs-ng/log"
CONFIG_FILE="$CONFIG_DIR/tac_plus.conf"
TACACS_SERVER_IP="172.16.10.241"
SYSLOG_IP="172.16.10.118"
SYSLOG_PORT="514"
CONTAINER_NAME="tacacs-ng"
SHARED_SECRET="mysecret"

echo "=== TACACS+ Docker Deployment ==="
echo "Server IP: $TACACS_SERVER_IP (interface ens2)"
echo "Syslog: $SYSLOG_IP:$SYSLOG_PORT"
echo ""

# Check if Docker is running
if ! sudo docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first:"
    echo "  sudo systemctl start docker"
    echo "  sudo systemctl enable docker"
    exit 1
fi

# Verify interface ens2 exists and has the correct IP
echo "Checking network interface ens2..."
if ip addr show ens2 2>/dev/null | grep -q "$TACACS_SERVER_IP"; then
    echo "✓ Interface ens2 found with IP $TACACS_SERVER_IP"
else
    echo "Warning: Interface ens2 doesn't have IP $TACACS_SERVER_IP"
    echo "Current IPs on this system:"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
    echo ""
fi

# Step 1: Create directories
echo "Creating configuration directories..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR"
chmod 700 "$CONFIG_DIR" "$LOG_DIR"

# Step 2: Create TACACS+ config file
echo "Creating TACACS+ configuration..."
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

user = cisco {
    login = cleartext "cisco123"
    service = shell {
        default command = permit
        set priv-lvl = 15
    }
}

# Read-only user
user = readonly {
    login = cleartext "readonly123"
    service = shell {
        default command = deny
        cmd = show {
            permit .*
        }
        cmd = exit {
            permit .*
        }
        cmd = logout {
            permit .*
        }
        cmd = enable {
            permit .*
        }
        set priv-lvl = 1
    }
}

# Network operator user (intermediate privileges)
user = netops {
    login = cleartext "netops123"
    service = shell {
        default command = deny
        cmd = show {
            permit .*
        }
        cmd = clear {
            permit "counters.*"
            permit "arp.*"
        }
        cmd = ping {
            permit .*
        }
        cmd = traceroute {
            permit .*
        }
        cmd = exit {
            permit .*
        }
        cmd = logout {
            permit .*
        }
        cmd = enable {
            permit .*
        }
        set priv-lvl = 7
    }
}
EOF

chmod 600 "$CONFIG_FILE"
echo "✓ Configuration created"

# Step 3: Stop any existing container
if [ "$(sudo docker ps -aq -f name="$CONTAINER_NAME")" ]; then
    echo "Stopping existing container..."
    sudo docker stop "$CONTAINER_NAME" 2>/dev/null || true
    sudo docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Step 4: Pull Docker image with specific tag
echo "Pulling TACACS+ Docker image (rickronen/tac-plus:1.0)..."
sudo docker pull rickronen/tac-plus:1.0

# Step 5: Run the container
echo "Starting TACACS+ container..."
sudo docker run --name "$CONTAINER_NAME" \
    -p 49:49/tcp \
    -v "$CONFIG_FILE:/etc/tac_plus/tac_plus.conf:ro" \
    -v "$LOG_DIR:/var/log/tac_plus" \
    -d --restart=always \
    rickronen/tac-plus:1.0

# Step 6: Verify deployment
sleep 3
if sudo docker ps | grep -q "$CONTAINER_NAME"; then
    echo ""
    echo "========================================"
    echo "✓ TACACS+ DEPLOYMENT SUCCESSFUL!"
    echo "========================================"
    echo ""
    echo "Server Details:"
    echo "  IP Address: $TACACS_SERVER_IP"
    echo "  Interface: ens2"
    echo "  Port: TCP/49"
    echo "  Shared Secret: mysecret"
    echo ""
    echo "Test Users:"
    echo "  admin     / secret123   (priv-15, full access)"
    echo "  cisco     / cisco123    (priv-15, full access)"
    echo "  netops    / netops123   (priv-7, limited access)"
    echo "  readonly  / readonly123 (priv-1, read-only)"
    echo ""
    echo "Syslog Configuration:"
    echo "  Server: $SYSLOG_IP:$SYSLOG_PORT"
    echo "  Facility: AUTH"
    echo ""
    echo "Container Status:"
    sudo docker ps | grep "$CONTAINER_NAME"
    echo ""
    echo "Management Commands:"
    echo "  View logs:    sudo docker logs $CONTAINER_NAME"
    echo "  Stop:         sudo docker stop $CONTAINER_NAME"
    echo "  Start:        sudo docker start $CONTAINER_NAME"
    echo "  Restart:      sudo docker restart $CONTAINER_NAME"
    echo "  Live logs:    sudo docker logs -f $CONTAINER_NAME"
    echo ""
else
    echo "✗ Container failed to start!"
    echo "Debug: sudo docker logs $CONTAINER_NAME"
    exit 1
fi

# Test port connectivity
echo "Testing TACACS+ port..."
if nc -z -w 2 localhost 49 2>&1 | grep -q succeeded; then
    echo "✓ Port 49 is listening on localhost"
fi

# Test from the actual interface
if nc -z -w 2 $TACACS_SERVER_IP 49 2>&1 | grep -q succeeded; then
    echo "✓ Port 49 is accessible on $TACACS_SERVER_IP"
else
    echo "! Warning: Cannot reach port 49 on $TACACS_SERVER_IP"
    echo "  Check firewall rules: sudo ufw status"
fi

# Display configuration examples
echo ""
echo "========================================"
echo "NETWORK DEVICE CONFIGURATION EXAMPLES"
echo "========================================"
echo ""
echo "Cisco IOS/IOS-XE Configuration:"
echo "------------------------------"
cat << EOF
enable
configure terminal
 ! TACACS+ server configuration
 aaa new-model
 tacacs server TACACS-UBUNTU
  address ipv4 $TACACS_SERVER_IP
  key mysecret
  port 49
 !
 ! AAA configuration
 aaa group server tacacs+ TACACS-GROUP
  server name TACACS-UBUNTU
 !
 aaa authentication login default group TACACS-GROUP local
 aaa authorization exec default group TACACS-GROUP local
 aaa authorization commands 1 default group TACACS-GROUP local
 aaa authorization commands 7 default group TACACS-GROUP local
 aaa authorization commands 15 default group TACACS-GROUP local
 aaa accounting exec default start-stop group TACACS-GROUP
 aaa accounting commands 1 default start-stop group TACACS-GROUP
 aaa accounting commands 7 default start-stop group TACACS-GROUP
 aaa accounting commands 15 default start-stop group TACACS-GROUP
 !
 ! Local fallback user
 username fallback privilege 15 secret 0 fallbackpass
 !
 ! Apply to VTY lines
 line vty 0 4
  transport input ssh telnet
 line vty 5 15
  transport input ssh telnet
end
write memory
EOF

echo ""
echo "Cisco Nexus Configuration:"
echo "-------------------------"
cat << EOF
configure terminal
 ! Enable TACACS+
 feature tacacs+
 !
 ! Configure TACACS+ server
 tacacs-server host $TACACS_SERVER_IP port 49
 tacacs-server key mysecret
 !
 ! AAA configuration
 aaa group server tacacs+ TACACS-GROUP
  server $TACACS_SERVER_IP
  use-vrf management
 !
 aaa authentication login default group TACACS-GROUP local
 aaa authorization config-commands default group TACACS-GROUP local
 aaa authorization commands default group TACACS-GROUP local
 aaa accounting default group TACACS-GROUP
 !
 ! Local fallback user
 username fallback password fallbackpass role network-admin
end
copy running-config startup-config
EOF

echo ""
echo "Arista EOS Configuration:"
echo "------------------------"
cat << EOF
enable
configure
 ! TACACS+ configuration
 aaa authentication login default group tacacs+ local
 aaa authorization exec default group tacacs+ local
 aaa authorization commands all default group tacacs+ local
 aaa accounting exec default start-stop group tacacs+
 aaa accounting commands all default start-stop group tacacs+
 !
 tacacs-server host $TACACS_SERVER_IP port 49
 tacacs-server key mysecret
 !
 ! Local fallback user
 username fallback privilege 15 secret fallbackpass
end
write
EOF

echo ""
echo "Testing Instructions:"
echo "1. Configure your network device using examples above"
echo "2. Test login with one of the users (e.g., admin/secret123)"
echo "3. Monitor authentication logs: sudo docker logs -f $CONTAINER_NAME"
echo "4. Check syslog server ($SYSLOG_IP) for accounting records"
echo ""
echo "Firewall Note:"
echo "If devices cannot connect, ensure port 49/tcp is open:"
echo "  sudo ufw allow 49/tcp"
echo "  sudo ufw status"
