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

# Check for Docker
echo "[1/7] Checking for Docker..."
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

# Check for Docker Compose
echo "[2/7] Checking for Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    apt-get update
    apt-get install -y docker-compose
else
    echo "✓ Docker Compose is installed"
fi

# Create installation directory
echo "[3/7] Creating installation directory..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download the application files
echo "[4/7] Downloading application files..."
if [ -d "spotify-kids-manager" ]; then
    echo "Updating existing installation..."
    cd spotify-kids-manager
    git pull
else
    git clone https://github.com/socialoutcast/spotify-kids-manager.git
    cd spotify-kids-manager
fi

# Build Docker image
echo "[5/7] Building Docker image (this may take a while)..."
docker-compose build

# Start the container immediately
echo "[6/7] Starting Docker container..."
cd ${INSTALL_DIR}/spotify-kids-manager
docker-compose down 2>/dev/null || true
docker-compose up -d
sleep 10

# Verify container is running
if docker ps | grep -q spotify-kids-manager; then
    echo "✓ Container started successfully"
else
    echo "⚠ Container failed to start, attempting again..."
    docker-compose logs --tail 20
    docker-compose up -d
    sleep 5
fi

# Create systemd service
echo "[7/7] Creating systemd service..."
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
WorkingDirectory=${INSTALL_DIR}/spotify-kids-manager
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Configure firewall
echo "[7/8] Configuring firewall..."
# Check if ufw is installed and active
if command -v ufw &> /dev/null; then
    echo "Configuring UFW firewall..."
    ufw allow 80/tcp comment 'Spotify Kids Manager Web' || true
    ufw allow 22/tcp comment 'SSH' || true
    ufw --force enable || true
    echo "✓ Firewall configured"
elif command -v firewall-cmd &> /dev/null; then
    echo "Configuring firewalld..."
    firewall-cmd --permanent --add-port=80/tcp || true
    firewall-cmd --permanent --add-port=22/tcp || true
    firewall-cmd --reload || true
    echo "✓ Firewall configured"
else
    echo "No firewall detected, skipping firewall configuration"
fi

# Check if iptables needs direct configuration
if command -v iptables &> /dev/null; then
    # Ensure port 80 is not blocked
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    echo "✓ iptables rules added"
fi

# Enable and start the service
echo "[8/8] Starting Spotify Kids Manager..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl start ${SERVICE_NAME}.service

# Wait for service to be ready
echo ""
echo "Waiting for service to start..."
sleep 10

# Check if port 80 is listening
echo "Checking service status..."
if netstat -tuln | grep -q ":80 "; then
    echo "✓ Web service is listening on port 80"
else
    echo "⚠ Warning: Port 80 may not be accessible"
    echo "  Checking Docker container..."
    docker ps
    echo ""
    echo "  Checking container logs..."
    docker logs ${SERVICE_NAME} --tail 20
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
echo "  http://${IP_ADDRESS}"
echo ""
echo "Default login credentials:"
echo "  Username: admin"
echo "  Password: changeme"
echo ""
echo "IMPORTANT: Change the admin password after first login!"
echo ""
echo "Service management commands:"
echo "  Start:   sudo systemctl start ${SERVICE_NAME}"
echo "  Stop:    sudo systemctl stop ${SERVICE_NAME}"
echo "  Restart: sudo systemctl restart ${SERVICE_NAME}"
echo "  Status:  sudo systemctl status ${SERVICE_NAME}"
echo "  Logs:    sudo journalctl -u ${SERVICE_NAME} -f"
echo ""
echo "To uninstall:"
echo "  sudo systemctl stop ${SERVICE_NAME}"
echo "  sudo systemctl disable ${SERVICE_NAME}"
echo "  sudo rm -rf ${INSTALL_DIR}"
echo "  sudo rm /etc/systemd/system/${SERVICE_NAME}.service"
echo ""
echo "================================================"