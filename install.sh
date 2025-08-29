#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
APP_USER="spotify-kids"
APP_DIR="/opt/spotify-kids"
CONFIG_DIR="$APP_DIR/config"
REPO_URL="https://github.com/yourusername/spotify-kids-manager.git"

echo -e "${GREEN}Spotify Kids Manager Installer${NC}"
echo "================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
apt-get update
apt-get upgrade -y

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt-get install -y \
    python3 \
    python3-pip \
    python3-tk \
    python3-pil \
    python3-pil.imagetk \
    xserver-xorg \
    xinit \
    x11-xserver-utils \
    nginx \
    git \
    unclutter \
    chromium-browser

# Install Python packages
echo -e "${YELLOW}Installing Python packages...${NC}"
pip3 install --break-system-packages \
    spotipy \
    flask \
    flask-cors \
    werkzeug \
    pillow \
    requests \
    psutil

# Create application user
echo -e "${YELLOW}Creating application user...${NC}"
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$APP_USER"
    usermod -aG audio,video,input "$APP_USER"
fi

# Add sudo permissions for apt commands only
echo -e "${YELLOW}Configuring sudo permissions for updates...${NC}"
cat > /etc/sudoers.d/spotify-kids << EOF
# Allow spotify-kids user to run apt commands without password
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/apt-get update, /usr/bin/apt-get upgrade*, /usr/bin/apt-get autoremove*, /usr/bin/apt-get autoclean*
$APP_USER ALL=(ALL) NOPASSWD: /usr/bin/apt list*
EOF
chmod 0440 /etc/sudoers.d/spotify-kids

# Create application directories
echo -e "${YELLOW}Creating application directories...${NC}"
mkdir -p "$APP_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "/var/log/spotify-kids"

# Copy application files
echo -e "${YELLOW}Installing application files...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/spotify_player.py" "$APP_DIR/"
cp -r "$SCRIPT_DIR/web" "$APP_DIR/"

# Set permissions
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "/var/log/spotify-kids"

# Configure auto-login
echo -e "${YELLOW}Configuring auto-login...${NC}"
mkdir -p /etc/systemd/system/getty@tty1.service.d/
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $APP_USER --noclear %I \$TERM
EOF

# Create systemd service for the player
echo -e "${YELLOW}Creating systemd service for player...${NC}"
cat > /etc/systemd/system/spotify-player.service << EOF
[Unit]
Description=Spotify Kids Player
After=multi-user.target

[Service]
Type=simple
User=$APP_USER
Environment="DISPLAY=:0"
Environment="SPOTIFY_CONFIG_DIR=$CONFIG_DIR"
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/python3 $APP_DIR/spotify_player.py
Restart=always
RestartSec=10

[Install]
WantedBy=graphical.target
EOF

# Create systemd service for admin panel
echo -e "${YELLOW}Creating systemd service for admin panel...${NC}"
cat > /etc/systemd/system/spotify-admin.service << EOF
[Unit]
Description=Spotify Kids Admin Panel
After=network.target

[Service]
Type=simple
User=$APP_USER
Environment="SPOTIFY_CONFIG_DIR=$CONFIG_DIR"
WorkingDirectory=$APP_DIR/web
ExecStart=/usr/bin/python3 $APP_DIR/web/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Configure nginx
echo -e "${YELLOW}Configuring nginx...${NC}"
cat > /etc/nginx/sites-available/spotify-admin << EOF
server {
    listen 8080;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Create .xinitrc for the user
echo -e "${YELLOW}Creating X session configuration...${NC}"
cat > /home/$APP_USER/.xinitrc << EOF
#!/bin/sh

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor after 3 seconds of inactivity
unclutter -idle 3 &

# Start the Spotify player
exec python3 $APP_DIR/spotify_player.py
EOF

chmod +x /home/$APP_USER/.xinitrc
chown $APP_USER:$APP_USER /home/$APP_USER/.xinitrc

# Create .bash_profile for auto-start
echo -e "${YELLOW}Configuring auto-start...${NC}"
cat > /home/$APP_USER/.bash_profile << EOF
#!/bin/bash

# Start X server with Spotify player on tty1
if [[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    exec startx
fi
EOF

chown $APP_USER:$APP_USER /home/$APP_USER/.bash_profile

# Enable services
echo -e "${YELLOW}Enabling services...${NC}"
systemctl daemon-reload
systemctl enable spotify-admin.service
systemctl enable nginx
systemctl start spotify-admin.service
systemctl restart nginx

# Configure touchscreen if available
if [ -e "/dev/input/touchscreen0" ] || [ -e "/dev/input/event0" ]; then
    echo -e "${YELLOW}Configuring touchscreen...${NC}"
    
    # Create calibration file
    cat > /etc/X11/xorg.conf.d/99-calibration.conf << EOF
Section "InputClass"
    Identifier "calibration"
    MatchProduct "touchscreen"
    Option "Calibration" "0 800 0 480"
    Option "SwapAxes" "0"
EOF
fi

# Disable unnecessary services
echo -e "${YELLOW}Optimizing system...${NC}"
systemctl disable bluetooth.service 2>/dev/null || true
systemctl disable cups.service 2>/dev/null || true

# Create uninstall script
echo -e "${YELLOW}Creating uninstall script...${NC}"
cat > /usr/local/bin/spotify-kids-uninstall << EOF
#!/bin/bash
echo "Uninstalling Spotify Kids Manager..."
systemctl stop spotify-player.service 2>/dev/null
systemctl stop spotify-admin.service 2>/dev/null
systemctl disable spotify-player.service 2>/dev/null
systemctl disable spotify-admin.service 2>/dev/null
rm -f /etc/systemd/system/spotify-player.service
rm -f /etc/systemd/system/spotify-admin.service
rm -f /etc/nginx/sites-available/spotify-admin
rm -f /etc/nginx/sites-enabled/spotify-admin
rm -rf $APP_DIR
userdel -r $APP_USER 2>/dev/null
rm -f /usr/local/bin/spotify-kids-uninstall
echo "Uninstall complete"
EOF
chmod +x /usr/local/bin/spotify-kids-uninstall

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "Admin Panel: ${YELLOW}http://$(hostname -I | awk '{print $1}'):8080${NC}"
echo -e "Default login: ${YELLOW}admin / changeme${NC}"
echo ""
echo -e "The system will restart in 10 seconds to apply all changes."
echo -e "After restart, the Spotify player will start automatically."
echo ""
echo -e "To uninstall, run: ${YELLOW}sudo spotify-kids-uninstall${NC}"
echo ""

# Restart system
sleep 10
reboot