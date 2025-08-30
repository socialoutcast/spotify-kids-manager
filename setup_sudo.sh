#!/bin/bash

# Setup sudo permissions for Spotify Kids Manager admin panel
# This allows the web app to run system updates without password

echo "Setting up sudo permissions for Spotify Kids Manager..."

# Create sudoers file for spotify-admin
cat << EOF | sudo tee /etc/sudoers.d/spotify-admin
# Allow www-data to run apt commands without password
www-data ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/systemctl, /usr/sbin/rfkill, /usr/bin/bluetoothctl, /usr/sbin/reboot, /usr/sbin/poweroff
EOF

# Set correct permissions
sudo chmod 0440 /etc/sudoers.d/spotify-admin

echo "Sudo permissions configured successfully!"
echo "The web admin panel can now:"
echo "  - Check for system updates"
echo "  - Install system updates"
echo "  - Control Bluetooth"
echo "  - Restart services"
echo "  - Reboot/shutdown system"