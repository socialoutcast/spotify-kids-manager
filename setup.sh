#!/bin/bash
# Spotify Kids Manager - Setup Script
# This downloads everything from the release and runs the original installer
# Usage: curl -fsSL .../setup.sh | sudo bash
#    or: curl -fsSL .../setup.sh | sudo bash -s -- --reset

set -e

# Encrypted password for the release archive
# This is decrypted at runtime using a known key
ENCRYPTED_PASSWORD="U2FsdGVkX1/C12yKV6vyGvA3hFTXFmT/+5w3Z6e8ikGQnUyEdTQuOXBGyvky7eUh/Mg4tiAv8in+DwKvc71mrA=="

# Decrypt the password using standard Linux tools
# Use no special flags for maximum compatibility
SETUP_KEY="SpotifyKidsManager2025"
RELEASE_PASSWORD=$(echo "$ENCRYPTED_PASSWORD" | openssl enc -aes-256-cbc -a -d -salt -pass pass:"$SETUP_KEY")

# Create temp directory and download release
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the encrypted package from release
echo "Downloading Spotify Kids Manager..."
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/spotify-kids-manager-complete.tar.gz.enc -o spotify-kids-manager-complete.tar.gz.enc

# Decrypt and extract using the decrypted password
echo "Extracting package..."
openssl enc -aes-256-cbc -d -salt -pass pass:"$RELEASE_PASSWORD" -in spotify-kids-manager-complete.tar.gz.enc | tar xz

# Extract the nested tarballs
tar xzf installer-scripts.tar.gz
tar xzf spotify-kids-web.tar.gz
tar xzf spotify-kids-player.tar.gz
chmod +x kiosk_launcher.sh

# Detect the real user for the installer
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
else
    # Find first regular user
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            user_name=$(basename "$user_home")
            if [ "$user_name" != "lost+found" ] && id "$user_name" &>/dev/null; then
                user_id=$(id -u "$user_name")
                if [ "$user_id" -ge 1000 ] && [ "$user_id" -lt 60000 ]; then
                    REAL_USER="$user_name"
                    break
                fi
            fi
        fi
    done
fi

# Run the original installer - it will find files "locally"
# Pass through any arguments (like --reset)
# Export REAL_USER so installer can use it
export REAL_USER
bash installer-full.sh "$@"

# Cleanup
cd /
rm -rf "$TEMP_DIR"
