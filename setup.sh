#!/bin/bash
# Spotify Kids Manager - Setup Script
# This downloads everything from the release and runs the original installer
# Usage: curl -fsSL .../setup.sh | sudo bash
#    or: curl -fsSL .../setup.sh | sudo bash -s -- --reset

set -e

# Encrypted password for the release archive
# This is decrypted at runtime using a known key
ENCRYPTED_PASSWORD="U2FsdGVkX1/RI66IBDHMkTDxfKp4VVZ/OAjQLoATTMj2c8ZJSWcAnnzT1qPF0wQ1Nl0w501ZWLwW9qtb5JtZdw=="

# Decrypt the password using standard Linux tools
SETUP_KEY="SpotifyKidsManager2025"
RELEASE_PASSWORD=$(echo "$ENCRYPTED_PASSWORD" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$SETUP_KEY")

# Create temp directory and download release
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the encrypted package from release
echo "Downloading Spotify Kids Manager..."
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/spotify-kids-manager-complete.tar.gz.enc -o spotify-kids-manager-complete.tar.gz.enc

# Decrypt and extract using the decrypted password
echo "Extracting package..."
openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:"$RELEASE_PASSWORD" -in spotify-kids-manager-complete.tar.gz.enc | tar xz

# Extract the nested tarballs
tar xzf installer-scripts.tar.gz
tar xzf spotify-kids-web.tar.gz
tar xzf spotify-kids-player.tar.gz
chmod +x kiosk_launcher.sh

# Run the original installer - it will find files "locally"
# Pass through any arguments (like --reset)
sudo bash installer-full.sh "$@"

# Cleanup
cd /
rm -rf "$TEMP_DIR"
