#!/bin/bash

# Spotify Kids Manager - Docker Permissions Fix Script
# Run this if you get "permission denied" errors with docker commands

echo "================================================"
echo "   Docker Permissions Fix                      "
echo "================================================"
echo ""

# Get the current user
CURRENT_USER=${USER:-$(whoami)}

# Check if user is in docker group
if groups "$CURRENT_USER" | grep -q "\bdocker\b"; then
    echo "✓ User '$CURRENT_USER' is already in the docker group"
    echo ""
    echo "The group membership just needs to be activated."
    echo ""
    echo "Choose an option:"
    echo "  1. Run: newgrp docker"
    echo "     (This opens a new shell with docker access)"
    echo ""
    echo "  2. Log out and log back in"
    echo "     (This permanently fixes it for all shells)"
    echo ""
    echo "  3. Use the wrapper commands:"
    echo "     docker-user ps"
    echo "     docker-user logs spotify-kids-manager"
    echo ""
    
    # Try to activate docker group for current shell
    echo "Attempting to activate docker group for this shell..."
    echo ""
    echo "Run this command now:"
    echo "  newgrp docker"
    echo ""
    echo "Then test with:"
    echo "  docker ps"
else
    echo "⚠ User '$CURRENT_USER' is not in the docker group"
    echo ""
    echo "Run the installation script with sudo to fix this:"
    echo "  sudo ./install.sh"
    echo ""
    echo "Or manually add yourself to the docker group:"
    echo "  sudo usermod -aG docker $CURRENT_USER"
    echo "  newgrp docker"
fi

echo ""
echo "================================================"
echo "Quick Test Commands:"
echo "================================================"
echo ""
echo "After running 'newgrp docker', test with:"
echo "  docker ps"
echo "  docker logs spotify-kids-manager"
echo ""
echo "If you still get permission denied, try:"
echo "  sudo systemctl restart docker"
echo "  newgrp docker"
echo ""