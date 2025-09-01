#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Spotify Kids Player - Installation Script${NC}"
echo "========================================="

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo -e "${RED}Please do not run this script as root${NC}"
   exit 1
fi

# Check for Node.js
if ! command -v node &> /dev/null; then
    echo -e "${YELLOW}Node.js not found. Installing...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

echo -e "${GREEN}Node.js version: $(node --version)${NC}"

# Check for npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}npm not found. Please install Node.js properly${NC}"
    exit 1
fi

echo -e "${GREEN}npm version: $(npm --version)${NC}"

# Installation directory
INSTALL_DIR="/opt/spotify-kids/player"
CONFIG_DIR="/opt/spotify-kids/config"

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
sudo mkdir -p $INSTALL_DIR
sudo mkdir -p $CONFIG_DIR/cache
sudo mkdir -p /var/log/spotify-kids

# Copy files
echo -e "${YELLOW}Copying files...${NC}"
sudo cp -r ./* $INSTALL_DIR/
sudo cp config.example.json $CONFIG_DIR/player_config.json 2>/dev/null || true

# Set permissions
echo -e "${YELLOW}Setting permissions...${NC}"
sudo chown -R spotify-kids:spotify-kids $INSTALL_DIR
sudo chown -R spotify-kids:spotify-config $CONFIG_DIR
sudo chmod 775 $CONFIG_DIR
sudo chmod 664 $CONFIG_DIR/*.json

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
cd $INSTALL_DIR
sudo -u spotify-kids npm install --production

# Install systemd service
echo -e "${YELLOW}Installing systemd service...${NC}"
sudo cp spotify-player.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable spotify-player

# Update kiosk launcher to use new player
echo -e "${YELLOW}Updating kiosk launcher...${NC}"
if [ -f /opt/spotify-kids/kiosk_launcher.sh ]; then
    # Already updated in previous script
    echo -e "${GREEN}Kiosk launcher already configured${NC}"
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "Configuration files are located in: $CONFIG_DIR"
echo ""
echo "To customize the player:"
echo "  1. Edit $CONFIG_DIR/player_config.json"
echo "  2. Restart the service: sudo systemctl restart spotify-player"
echo ""
echo "Available themes:"
echo "  - spotify-dark (default)"
echo "  - spotify-light"
echo "  - kids-colorful"
echo "  - minimal"
echo "  - high-contrast"
echo ""
echo "To start the player now:"
echo "  sudo systemctl start spotify-player"
echo ""
echo "The player will be available at:"
echo "  http://localhost:5000"
echo ""