#!/bin/bash

# Spotify Kids Manager - One-Click Installation Script
# This script sets up everything needed for the locked-down Spotify player

set -e

INSTALL_DIR="/opt/spotify-kids-manager"
SERVICE_NAME="spotify-kids-manager"
DOCKER_IMAGE="spotify-kids-manager:latest"

echo "================================================"
echo "   Spotify Kids Manager - Installation Script  "
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run this script as root (use sudo)"
   exit 1
fi

# Clean up any failed previous installation
echo "[1/9] Checking for previous installation..."
if [ -d "$INSTALL_DIR" ]; then
    echo "Found existing installation. Cleaning up..."
    
    # Stop any running containers
    if [ -d "$INSTALL_DIR/spotify-kids-manager" ]; then
        cd "$INSTALL_DIR/spotify-kids-manager"
        docker-compose down 2>/dev/null || true
    elif [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        cd "$INSTALL_DIR"
        docker-compose down 2>/dev/null || true
    fi
    
    # Stop the service if it exists
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    
    # Remove the old installation
    rm -rf ${INSTALL_DIR}
    echo "✓ Previous installation cleaned up"
fi

# Get the current user who invoked sudo (if applicable)
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_USER_HOME=$(eval echo ~$REAL_USER)

# Check for Docker and configure group
echo "[2/9] Checking for Docker and configuring user permissions..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
else
    echo "✓ Docker is installed"
fi

# Ensure docker group exists
if ! getent group docker > /dev/null 2>&1; then
    echo "Creating docker group..."
    groupadd docker
fi

# Add the real user to docker group if not root
if [ "$REAL_USER" != "root" ] && [ -n "$REAL_USER" ]; then
    echo "Adding user '$REAL_USER' to docker group..."
    usermod -aG docker "$REAL_USER"
    echo "✓ User '$REAL_USER' added to docker group"
    
    # Apply group changes immediately for the current session
    # This allows docker commands to work without logout
    echo "Applying group changes for immediate use..."
    
    # Create a temporary sudoers entry for docker commands if needed
    if [ -d /etc/sudoers.d ]; then
        echo "$REAL_USER ALL=(ALL) NOPASSWD: /usr/bin/docker, /usr/bin/docker-compose" > /etc/sudoers.d/spotify-kids-docker-temp
        chmod 0440 /etc/sudoers.d/spotify-kids-docker-temp
    fi
    
    echo ""
    echo "NOTE: User '$REAL_USER' can now use Docker commands."
    echo "      The changes will be fully applied after next login."
    echo "      For this session, docker commands will work via this script."
else
    echo "✓ Running as root, no group changes needed"
fi

# Check for Docker Compose
echo "[3/9] Checking for Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    apt-get update
    apt-get install -y docker-compose
else
    echo "✓ Docker Compose is installed"
fi

# Create installation directory
echo "[4/9] Creating installation directory..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download the application files
echo "[5/9] Downloading application files..."
git clone https://github.com/socialoutcast/spotify-kids-manager.git .

# Build Docker image
echo "[6/9] Building Docker image (this may take a while)..."
docker-compose build

# Start the container immediately
echo "[7/9] Starting Docker container..."
docker-compose down 2>/dev/null || true
docker-compose up -d

# Wait for container to start
echo "Waiting for container to start..."
sleep 10

# Verify container is running
if docker ps | grep -q spotify-kids-manager; then
    echo "✓ Container started successfully"
else
    echo "⚠ Container failed to start, checking logs..."
    docker-compose logs --tail 20
    echo ""
    echo "Attempting to start again..."
    docker-compose up -d
    sleep 5
    
    if docker ps | grep -q spotify-kids-manager; then
        echo "✓ Container started on second attempt"
    else
        echo "✗ Container failed to start. Please check logs with:"
        echo "  cd $INSTALL_DIR && docker-compose logs"
    fi
fi

# Create systemd service
echo "[8/9] Creating systemd service..."
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Spotify Kids Manager
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=${INSTALL_DIR}
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configure firewall
echo "[9/9] Configuring firewall and network..."
# Check if ufw is installed and active
if command -v ufw &> /dev/null; then
    echo "Configuring UFW firewall..."
    ufw allow 8080/tcp comment 'Spotify Kids Manager Web' || true
    ufw allow 22/tcp comment 'SSH' || true
    ufw --force enable || true
    echo "✓ Firewall configured"
elif command -v firewall-cmd &> /dev/null; then
    echo "Configuring firewalld..."
    firewall-cmd --permanent --add-port=8080/tcp || true
    firewall-cmd --permanent --add-port=22/tcp || true
    firewall-cmd --reload || true
    echo "✓ Firewall configured"
else
    echo "No firewall detected, configuring iptables..."
fi

# Check if iptables needs direct configuration
if command -v iptables &> /dev/null; then
    # Ensure port 8080 is not blocked
    iptables -I INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    echo "✓ iptables rules added"
fi

# Enable and start the service
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service

# Check if port 8080 is listening
echo ""
echo "Checking service status..."
if netstat -tuln | grep -q ":8080 "; then
    echo "✓ Web service is listening on port 8080"
else
    echo "⚠ Port 8080 may not be accessible yet"
    echo "  Container status:"
    docker ps | grep spotify-kids-manager || echo "  Container not running"
fi

# Get IP address
IP_ADDRESS=$(hostname -I | cut -d' ' -f1)

# Final instructions
echo ""
echo "================================================"
echo "   Installation Complete!                      "
echo "================================================"
echo ""
echo "Spotify Kids Manager is now running!"
echo ""
echo "Access the web interface at:"
echo "  http://${IP_ADDRESS}:8080"
echo ""
echo "Default login credentials:"
echo "  Username: admin"
echo "  Password: changeme"
echo ""
echo "IMPORTANT: Change the admin password after first login!"
echo ""
if [ "$REAL_USER" != "root" ] && [ -n "$REAL_USER" ]; then
    echo "Docker Access for user '$REAL_USER':"
    echo "  ✓ User added to docker group"
    echo "  ✓ Can use docker commands without sudo"
    echo "  Note: Full permissions apply after next login"
    echo ""
fi
echo "Service management commands:"
echo "  Start:   sudo systemctl start ${SERVICE_NAME}"
echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
echo "  Restart: sudo systemctl restart ${SERVICE_NAME}"
echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "Docker commands (no sudo needed for $REAL_USER):"
echo "  View logs:    docker-compose -f ${INSTALL_DIR}/docker-compose.yml logs"
echo "  Restart:      docker-compose -f ${INSTALL_DIR}/docker-compose.yml restart"
echo "  Stop:         docker-compose -f ${INSTALL_DIR}/docker-compose.yml down"
echo "  Start:        docker-compose -f ${INSTALL_DIR}/docker-compose.yml up -d"
echo "  Container:    docker ps | grep spotify-kids-manager"
echo ""
echo "If the web interface is not accessible:"
echo "  1. Check container: docker ps"
echo "  2. Check logs: docker-compose -f ${INSTALL_DIR}/docker-compose.yml logs"
echo "  3. Restart: docker-compose -f ${INSTALL_DIR}/docker-compose.yml restart"
echo ""
echo "To completely reinstall, run this script again."
echo "================================================"

# Clean up temporary sudoers file after informing the user
if [ -f /etc/sudoers.d/spotify-kids-docker-temp ]; then
    echo ""
    echo "Note: Temporary docker permissions have been set."
    echo "These will be replaced by group permissions on next login."
fi