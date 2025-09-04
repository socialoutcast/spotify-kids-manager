#!/bin/bash
# Spotify Kids Manager - Setup Script
# This downloads everything from the release and runs the original installer

set -e

# Create temp directory and download release
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the installer package from release
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/installer-scripts.tar.gz | tar xz

# Download source packages from release
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/spotify-kids-web.tar.gz -o web.tar.gz
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/spotify-kids-player.tar.gz -o player.tar.gz
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/kiosk_launcher.sh -o kiosk_launcher.sh

# Extract source to match original installer's expected structure
mkdir -p web player
tar xzf web.tar.gz -C web/
tar xzf player.tar.gz -C player/
chmod +x kiosk_launcher.sh

# Run the original installer - it will find files "locally"
sudo bash installer-full.sh

# Cleanup
cd /
rm -rf "$TEMP_DIR"