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
    echo "Found existing installation. Performing complete cleanup..."
    
    # Stop any running containers
    if [ -d "$INSTALL_DIR/spotify-kids-manager" ]; then
        cd "$INSTALL_DIR/spotify-kids-manager"
        docker-compose down -v --remove-orphans 2>/dev/null || true
    elif [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
        cd "$INSTALL_DIR"
        docker-compose down -v --remove-orphans 2>/dev/null || true
    fi
    
    # Remove any Docker containers, images and volumes related to spotify-kids-manager
    echo "Removing Docker containers, images and volumes..."
    docker stop spotify-kids-manager 2>/dev/null || true
    docker rm -f spotify-kids-manager 2>/dev/null || true
    docker rmi -f spotify-kids-manager:latest 2>/dev/null || true
    docker rmi -f socialoutcast/spotify-kids-manager:latest 2>/dev/null || true
    docker rmi -f $(docker images | grep -E "spotify-kids|spotify_kids" | awk '{print $3}' | uniq) 2>/dev/null || true
    docker volume rm $(docker volume ls -q | grep -E "spotify-kids|spotify_kids") 2>/dev/null || true
    
    # Stop and remove all related services
    echo "Removing system services..."
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true
    systemctl stop spotify-setup-display.service 2>/dev/null || true
    systemctl disable spotify-setup-display.service 2>/dev/null || true
    
    # Remove service files
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    rm -f /etc/systemd/system/spotify-setup-display.service
    
    # Remove wrapper scripts
    rm -f /usr/local/bin/docker-user
    rm -f /usr/local/bin/docker-compose-user
    
    # Clear any TTY messages
    for tty in /dev/tty1 /dev/tty2 /dev/tty3; do
        if [ -w "$tty" ]; then
            clear > "$tty" 2>/dev/null
        fi
    done
    
    # Remove the old installation directory completely
    rm -rf ${INSTALL_DIR}
    
    # Clean Docker system (optional but ensures clean state)
    docker system prune -f 2>/dev/null || true
    
    # Reload systemd
    systemctl daemon-reload
    
    echo "✓ Previous installation completely removed"
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
    
    # Set proper permissions on docker socket
    echo "Setting Docker socket permissions..."
    if [ -S /var/run/docker.sock ]; then
        chgrp docker /var/run/docker.sock
        chmod g+rw /var/run/docker.sock
        echo "✓ Docker socket permissions updated"
    fi
    
    # Create a wrapper script for immediate docker access
    echo "Creating docker wrapper for immediate access..."
    cat > /usr/local/bin/docker-user << 'EOF'
#!/bin/bash
# Temporary wrapper to run docker with group permissions
sg docker -c "docker $*"
EOF
    chmod +x /usr/local/bin/docker-user
    
    # Also create docker-compose wrapper
    cat > /usr/local/bin/docker-compose-user << 'EOF'
#!/bin/bash
# Temporary wrapper to run docker-compose with group permissions
sg docker -c "docker-compose $*"
EOF
    chmod +x /usr/local/bin/docker-compose-user
    
    echo ""
    echo "IMPORTANT: Docker group changes require a new session to take effect."
    echo ""
    echo "You have 3 options to use Docker commands:"
    echo "  1. Log out and log back in (recommended)"
    echo "  2. Run: newgrp docker (starts a new shell with docker group)"
    echo "  3. Use wrapper commands: docker-user and docker-compose-user"
    echo ""
    echo "Example: docker-user ps"
    echo "         docker-compose-user -f ${INSTALL_DIR}/docker-compose.yml logs"
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

# Ensure scripts directory has proper permissions
chmod +x scripts/*.sh 2>/dev/null || true

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

# Display setup message on console/TTY
echo ""
echo "Displaying setup instructions on device screen..."

# Check if we have a display script
if [ -f "${INSTALL_DIR}/scripts/display-setup-message.sh" ]; then
    # First, ensure the script is executable
    chmod +x ${INSTALL_DIR}/scripts/display-setup-message.sh
    
    # Display on TTY1 (main console) with proper redirection
    if [ -e /dev/tty1 ]; then
        echo "Displaying message on TTY1..."
        # Use chvt to switch to TTY1 if possible
        chvt 1 2>/dev/null || true
        
        # Clear and display message
        ${INSTALL_DIR}/scripts/display-setup-message.sh > /dev/tty1 2>&1
        
        # Also send to console
        ${INSTALL_DIR}/scripts/display-setup-message.sh > /dev/console 2>&1 &
    fi
    
    # Also display on current terminal for SSH users
    ${INSTALL_DIR}/scripts/display-setup-message.sh
    
    # Create a more robust systemd service
    cat > /etc/systemd/system/spotify-setup-display.service << EOF
[Unit]
Description=Display Spotify Kids Manager Setup Instructions
After=multi-user.target network-online.target
Wants=network-online.target

[Service]
Type=idle
ExecStartPre=/bin/sleep 5
ExecStart=/bin/bash -c '${INSTALL_DIR}/scripts/display-setup-message.sh --wait'
StandardOutput=tty
StandardError=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
RemainAfterExit=yes
User=root
Restart=no

[Install]
WantedBy=getty.target
EOF
    
    systemctl daemon-reload
    systemctl enable spotify-setup-display.service 2>/dev/null || true
    
    # Also create a getty override to display on login
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/spotify-setup.conf << EOF
[Service]
ExecStartPre=/bin/bash -c 'if [ ! -f /app/data/setup_status.json ] || ! grep -q "setup_complete.*true" /app/data/setup_status.json 2>/dev/null; then ${INSTALL_DIR}/scripts/display-setup-message.sh > /dev/tty1 2>&1; fi'
EOF
    
    systemctl daemon-reload
else
    # Fallback if script not found
    echo ""
    echo "================================================"
    echo "    PLEASE CONTINUE SETUP BY VISITING:         "
    echo "    http://${IP_ADDRESS}:8080                  "
    echo "================================================"
fi

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
echo "Docker commands:"
if [ "$REAL_USER" != "root" ] && [ -n "$REAL_USER" ]; then
    echo "  IMPORTANT: Use one of these methods first:"
    echo "    Option 1: newgrp docker    (opens new shell with docker access)"
    echo "    Option 2: Log out and back in (permanent fix)"
    echo ""
    echo "  Or use wrapper commands (work immediately):"
    echo "    View logs:    docker-user logs spotify-kids-manager"
    echo "    Container:    docker-user ps"
    echo "    Restart:      docker-compose-user -f ${INSTALL_DIR}/docker-compose.yml restart"
    echo ""
    echo "  After logout/login, normal commands will work:"
fi
echo "    docker logs spotify-kids-manager"
echo "    docker ps | grep spotify-kids-manager"
echo "    docker-compose -f ${INSTALL_DIR}/docker-compose.yml restart"
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