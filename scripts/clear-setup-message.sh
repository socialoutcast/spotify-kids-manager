#!/bin/bash

# Spotify Kids Manager - Clear Setup Message
# Removes the setup instructions from the display after setup is complete

echo "Clearing setup message from display..."

# Stop and disable the setup display service
systemctl stop spotify-setup-display.service 2>/dev/null || true
systemctl disable spotify-setup-display.service 2>/dev/null || true

# Remove the service file
rm -f /etc/systemd/system/spotify-setup-display.service

# Reload systemd
systemctl daemon-reload

# Clear all TTYs
for tty in /dev/tty1 /dev/tty2 /dev/tty3; do
    if [ -w "$tty" ]; then
        clear > "$tty" 2>/dev/null
        echo "Spotify Kids Manager - Setup Complete!" > "$tty" 2>/dev/null
        echo "" > "$tty" 2>/dev/null
        echo "The system is now ready for use." > "$tty" 2>/dev/null
    fi
done

echo "Setup message cleared successfully"