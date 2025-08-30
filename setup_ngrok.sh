#!/bin/bash

# Setup ngrok tunnel for Spotify OAuth
# This creates a public HTTPS URL that Spotify will accept

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Setting up ngrok for Spotify OAuth${NC}"
echo -e "${GREEN}======================================${NC}"

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo -e "${YELLOW}ngrok not found. Installing...${NC}"
    
    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
    elif [ "$ARCH" = "armv7l" ]; then
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz"
    else
        NGROK_URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz"
    fi
    
    # Download and install ngrok
    cd /tmp
    wget -q $NGROK_URL -O ngrok.tgz
    tar -xzf ngrok.tgz
    sudo mv ngrok /usr/local/bin/
    rm ngrok.tgz
    
    echo -e "${GREEN}ngrok installed successfully${NC}"
fi

# Create systemd service for ngrok
echo -e "${YELLOW}Creating ngrok service...${NC}"
sudo tee /etc/systemd/system/ngrok-spotify.service > /dev/null << 'EOF'
[Unit]
Description=ngrok tunnel for Spotify Admin Panel
After=network.target spotify-admin.service

[Service]
Type=simple
User=spotify-kids
ExecStart=/usr/local/bin/ngrok http 5000 --log=stdout
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create script to get ngrok URL
echo -e "${YELLOW}Creating ngrok URL helper script...${NC}"
sudo tee /usr/local/bin/get-ngrok-url > /dev/null << 'EOF'
#!/bin/bash
# Get the current ngrok public URL

# Wait for ngrok to start
sleep 2

# Get the public URL from ngrok API
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*' | cut -d'"' -f4 | head -1)

if [ -z "$NGROK_URL" ]; then
    echo "ngrok is not running or no tunnel found"
    echo "Start it with: sudo systemctl start ngrok-spotify"
    exit 1
fi

echo ""
echo "========================================="
echo "Your public HTTPS URL for Spotify OAuth:"
echo "$NGROK_URL"
echo ""
echo "Add this to your Spotify app Redirect URIs:"
echo "${NGROK_URL}/callback"
echo "========================================="
echo ""
EOF

sudo chmod +x /usr/local/bin/get-ngrok-url

# Instructions
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}ngrok Setup Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${YELLOW}To use ngrok for Spotify OAuth:${NC}"
echo ""
echo -e "1. Start the ngrok tunnel:"
echo -e "   ${GREEN}sudo systemctl start ngrok-spotify${NC}"
echo ""
echo -e "2. Get your public HTTPS URL:"
echo -e "   ${GREEN}get-ngrok-url${NC}"
echo ""
echo -e "3. Add the callback URL to your Spotify app settings"
echo ""
echo -e "4. The URL will look like:"
echo -e "   ${GREEN}https://abc123.ngrok.io/callback${NC}"
echo ""
echo -e "${YELLOW}Note: Free ngrok URLs change each time you restart.${NC}"
echo -e "${YELLOW}You'll need to update Spotify's redirect URI accordingly.${NC}"
echo ""
echo -e "${YELLOW}Alternative: Run setup_https.sh for a permanent${NC}"
echo -e "${YELLOW}local HTTPS solution with self-signed certificate.${NC}"