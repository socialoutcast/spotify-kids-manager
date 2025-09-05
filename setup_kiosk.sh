#!/bin/bash

# Setup script for Spotify Kids Player Kiosk Mode

set -e

echo "Setting up Spotify Kids Player Kiosk Mode..."

# Install required packages
echo "Installing required packages..."
sudo apt-get update
sudo apt-get install -y \
    xorg \
    xinit \
    chromium-browser \
    unclutter \
    lightdm \
    openbox

# Create spotify-kids user if doesn't exist
if ! id -u spotify-kids >/dev/null 2>&1; then
    echo "Creating spotify-kids user..."
    sudo useradd -m -s /bin/bash spotify-kids
    sudo usermod -a -G audio,video,input spotify-kids
fi

# Copy kiosk launcher
echo "Installing kiosk launcher..."
sudo cp kiosk_launcher.sh /opt/spotify-kids/kiosk_launcher.sh
sudo chmod +x /opt/spotify-kids/kiosk_launcher.sh
sudo chown spotify-kids:spotify-kids /opt/spotify-kids/kiosk_launcher.sh

# Setup auto-login with LightDM
echo "Configuring auto-login..."
sudo tee /etc/lightdm/lightdm.conf > /dev/null << 'EOF'
[Seat:*]
autologin-user=spotify-kids
autologin-user-timeout=0
user-session=openbox
EOF

# Create openbox autostart for spotify-kids user
echo "Setting up Openbox autostart..."
sudo mkdir -p /home/spotify-kids/.config/openbox
sudo tee /home/spotify-kids/.config/openbox/autostart > /dev/null << 'EOF'
# Disable screen saver and power management
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor
unclutter -idle 0.1 &

# Start the kiosk launcher
/opt/spotify-kids/kiosk_launcher.sh &
EOF

sudo chown -R spotify-kids:spotify-kids /home/spotify-kids/.config

# Alternative: Use .xinitrc if not using LightDM
sudo tee /home/spotify-kids/.xinitrc > /dev/null << 'EOF'
#!/bin/bash
xset s off
xset -dpms
xset s noblank
unclutter -idle 0.1 &
exec /opt/spotify-kids/kiosk_launcher.sh
EOF

sudo chmod +x /home/spotify-kids/.xinitrc
sudo chown spotify-kids:spotify-kids /home/spotify-kids/.xinitrc

# Install systemd service for kiosk
echo "Installing systemd service..."
sudo cp spotify-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload

# Create a simple startx script for manual testing
sudo tee /opt/spotify-kids/start_kiosk_manual.sh > /dev/null << 'EOF'
#!/bin/bash
# Manual start script for testing
sudo -u spotify-kids startx /opt/spotify-kids/kiosk_launcher.sh -- :0 vt7
EOF

sudo chmod +x /opt/spotify-kids/start_kiosk_manual.sh

# Enable services
echo "Enabling services..."
sudo systemctl enable lightdm
sudo systemctl enable spotify-kiosk.service

echo ""
echo "Kiosk mode setup complete!"
echo ""
echo "The system will now:"
echo "1. Auto-login as spotify-kids user on boot"
echo "2. Start X11 session automatically"
echo "3. Launch Chromium in kiosk mode showing the Spotify player"
echo "4. Restart browser if it crashes or is closed"
echo ""
echo "To test manually: sudo /opt/spotify-kids/start_kiosk_manual.sh"
echo "To start with systemd: sudo systemctl start spotify-kiosk"
echo ""
echo "Reboot the system for auto-login to take effect."