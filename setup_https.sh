#!/bin/bash

# Setup HTTPS for Spotify Kids Manager
# This script generates a self-signed certificate and configures HTTPS

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Setting up HTTPS for Spotify Auth${NC}"
echo -e "${GREEN}==================================${NC}"

# Get the device's IP address
IP_ADDRESS=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}Detected IP address: ${IP_ADDRESS}${NC}"

# Create SSL directory
SSL_DIR="/opt/spotify-kids/ssl"
echo -e "${YELLOW}Creating SSL directory...${NC}"
sudo mkdir -p $SSL_DIR

# Generate self-signed certificate
echo -e "${YELLOW}Generating self-signed SSL certificate...${NC}"
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $SSL_DIR/server.key \
    -out $SSL_DIR/server.crt \
    -subj "/C=US/ST=State/L=City/O=SpotifyKids/CN=$IP_ADDRESS" \
    -addext "subjectAltName=IP:$IP_ADDRESS,DNS:localhost"

# Set proper permissions
sudo chown -R spotify-kids:spotify-kids $SSL_DIR
sudo chmod 600 $SSL_DIR/server.key
sudo chmod 644 $SSL_DIR/server.crt

# Create nginx HTTPS configuration
echo -e "${YELLOW}Creating nginx HTTPS configuration...${NC}"
sudo tee /etc/nginx/sites-available/spotify-admin-ssl > /dev/null << EOF
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name $IP_ADDRESS;

    ssl_certificate $SSL_DIR/server.crt;
    ssl_certificate_key $SSL_DIR/server.key;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $IP_ADDRESS;
    return 301 https://\$server_name\$request_uri;
}

# Keep port 8080 for backward compatibility (also redirects to HTTPS)
server {
    listen 8080;
    listen [::]:8080;
    server_name $IP_ADDRESS;
    return 301 https://\$server_name\$request_uri;
}
EOF

# Enable the HTTPS site
echo -e "${YELLOW}Enabling HTTPS configuration...${NC}"
sudo ln -sf /etc/nginx/sites-available/spotify-admin-ssl /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/spotify-admin  # Remove old HTTP-only config

# Test nginx configuration
echo -e "${YELLOW}Testing nginx configuration...${NC}"
sudo nginx -t

# Restart nginx
echo -e "${YELLOW}Restarting nginx...${NC}"
sudo systemctl restart nginx

echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}HTTPS Setup Complete!${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT STEPS:${NC}"
echo ""
echo -e "1. The admin panel is now available at:"
echo -e "   ${GREEN}https://${IP_ADDRESS}${NC}"
echo ""
echo -e "2. Add this URL to your Spotify app's Redirect URIs:"
echo -e "   ${GREEN}https://${IP_ADDRESS}/callback${NC}"
echo ""
echo -e "3. Your browser will show a security warning because"
echo -e "   the certificate is self-signed. This is normal."
echo -e "   Click 'Advanced' and 'Proceed' to continue."
echo ""
echo -e "${YELLOW}Note: Spotify requires HTTPS for redirect URIs${NC}"
echo -e "${YELLOW}except for localhost. This self-signed cert${NC}"
echo -e "${YELLOW}enables HTTPS for your local network.${NC}"