#!/bin/bash

# Quick fix script to remove old spotify-terminal installation

echo "Removing old spotify-terminal installation..."

# Stop and disable old services
sudo systemctl stop spotify-terminal-admin 2>/dev/null || true
sudo systemctl stop spotify-terminal 2>/dev/null || true
sudo systemctl disable spotify-terminal-admin 2>/dev/null || true
sudo systemctl disable spotify-terminal 2>/dev/null || true

# Remove old files
sudo rm -f /etc/systemd/system/spotify-terminal*.service
sudo rm -rf /opt/spotify-terminal
sudo rm -f /etc/nginx/sites-available/spotify-terminal
sudo rm -f /etc/nginx/sites-enabled/spotify-terminal

# Reload systemd
sudo systemctl daemon-reload

echo "Old installation removed. Please run the installer again:"
echo "curl -sSL https://github.com/socialoutcast/spotify-kids-manager/raw/main/install.sh | sudo bash"