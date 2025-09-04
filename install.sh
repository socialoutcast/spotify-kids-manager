#!/bin/bash
# Spotify Kids Manager - Installer
set -e
TEMP_DIR=$(mktemp -d)
curl -sL https://github.com/socialoutcast/spotify-kids-manager/releases/latest/download/installer-scripts.tar.gz | tar xz -C "$TEMP_DIR"
sudo bash "$TEMP_DIR/installer-full.sh"
rm -rf "$TEMP_DIR"