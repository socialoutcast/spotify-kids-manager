#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_USER="spotify-kids"
APP_DIR="/opt/spotify-kids"
CONFIG_DIR="$APP_DIR/config"
REPO_URL="https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
RESET_MODE=false
if [[ "$1" == "--reset" ]]; then
    RESET_MODE=true
fi

echo -e "${GREEN}Spotify Kids Manager Installer${NC}"
echo "================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

# Clean up old spotify-terminal installation if exists
if [ -d "/opt/spotify-terminal" ] || systemctl list-units --all | grep -q "spotify-terminal"; then
    echo -e "${YELLOW}Found old spotify-terminal installation. Cleaning up...${NC}"
    systemctl stop spotify-terminal-admin 2>/dev/null || true
    systemctl stop spotify-terminal 2>/dev/null || true
    systemctl disable spotify-terminal-admin 2>/dev/null || true
    systemctl disable spotify-terminal 2>/dev/null || true
    rm -f /etc/systemd/system/spotify-terminal*.service
    rm -rf /opt/spotify-terminal
    rm -f /etc/nginx/sites-*/spotify-terminal
    systemctl daemon-reload
fi

# Reset function
if [ "$RESET_MODE" = true ]; then
    echo -e "${YELLOW}RESET MODE: Force removing ALL Spotify installations...${NC}"
    echo -e "${RED}Removing ALL configuration and data NOW!${NC}"
    # NO CONFIRMATION - JUST FORCE IT
    
    echo -e "${YELLOW}Stopping ALL Spotify services...${NC}"
    # Stop ANY service with spotify in the name
    systemctl list-units --all --type=service | grep -i spotify | awk '{print $1}' | while read service; do
        systemctl stop "$service" 2>/dev/null || true
        systemctl disable "$service" 2>/dev/null || true
    done
    
    echo -e "${YELLOW}Removing ALL Spotify files...${NC}"
    # Remove ALL spotify-related directories
    rm -rf /opt/spotify*
    rm -rf /opt/spotify-terminal
    rm -rf /opt/spotify-kids
    
    # Remove ALL service files
    rm -f /etc/systemd/system/spotify*.service
    rm -f /lib/systemd/system/spotify*.service
    rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
    
    # Remove ALL nginx configs
    rm -f /etc/nginx/sites-available/spotify*
    rm -f /etc/nginx/sites-enabled/spotify*
    rm -f /etc/nginx/sites-available/spotify-admin
    rm -f /etc/nginx/sites-enabled/spotify-admin
    
    # Restore default nginx site if needed
    if [ ! -f /etc/nginx/sites-enabled/default ] && [ -f /etc/nginx/sites-available/default ]; then
        ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
    fi
    
    # Remove ALL sudoers entries
    rm -f /etc/sudoers.d/spotify*
    rm -f /etc/sudoers.d/spotify-pkgmgr
    
    # Remove ALL uninstall scripts
    rm -f /usr/local/bin/spotify*
    
    # Remove X11 configs we may have added
    rm -f /etc/X11/xorg.conf.d/99-calibration.conf
    rm -f /etc/X11/xorg.conf.d/10-serverflags.conf
    rm -f /etc/X11/xorg.conf.d/20-display.conf
    
    echo -e "${YELLOW}Removing ALL Spotify users and groups...${NC}"
    # Remove ANY user with spotify in the name
    for user in spotify-kids spotify-admin spotify-terminal; do
        if id "$user" &>/dev/null; then
            # Kill all processes for this user
            pkill -9 -u "$user" 2>/dev/null || true
            sleep 2
            # Force remove user without removing home (we'll do that manually)
            userdel "$user" 2>/dev/null || true
        fi
    done
    
    # Remove the package management group
    groupdel spotify-pkgmgr 2>/dev/null || true
    # Remove the config group
    groupdel spotify-config 2>/dev/null || true
    
    # Force clean up home directories
    rm -rf /home/spotify-kids 2>/dev/null || true
    rm -rf /home/spotify-admin 2>/dev/null || true
    rm -rf /home/spotify-terminal 2>/dev/null || true
    rm -rf /home/spotify* 2>/dev/null || true
    
    # Clean up logs
    rm -rf /var/log/spotify*
    
    # Clean up any .bash_profile or .xinitrc we created
    for homedir in /home/*; do
        if [ -f "$homedir/.xinitrc" ] && grep -q "spotify" "$homedir/.xinitrc" 2>/dev/null; then
            rm -f "$homedir/.xinitrc"
        fi
        if [ -f "$homedir/.bash_profile" ] && grep -q "spotify" "$homedir/.bash_profile" 2>/dev/null; then
            rm -f "$homedir/.bash_profile"
        fi
    done
    
    # Reload everything
    systemctl daemon-reload
    systemctl restart nginx 2>/dev/null || true
    
    echo -e "${GREEN}COMPLETE RESET DONE! All Spotify installations removed.${NC}"
    echo -e "${GREEN}Starting fresh installation...${NC}"
    echo ""
    sleep 2
    # DON'T EXIT - CONTINUE WITH INSTALLATION BELOW
fi

# Update system
echo -e "${YELLOW}Updating system packages...${NC}"
echo "Running apt-get update..."
apt-get update || true
echo "Running apt-get upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q || true
echo "System update complete"

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
apt-get install -y \
    python3 \
    python3-pip \
    python3-tk \
    python3-pil \
    python3-pil.imagetk \
    xserver-xorg \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    xinit \
    x11-xserver-utils \
    x11-utils \
    x11-apps \
    nginx \
    git \
    unclutter \
    bluez \
    bluez-tools \
    pulseaudio-module-bluetooth \
    rfkill \
    scrot \
    xterm

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

# Create application user (NO SUDO PRIVILEGES)
echo -e "${YELLOW}Creating application user...${NC}"
if ! id "$APP_USER" &>/dev/null; then
    # User doesn't exist, but group might - clean it up
    if getent group "$APP_USER" >/dev/null 2>&1; then
        echo "Cleaning up existing group $APP_USER from previous installation..."
        groupdel "$APP_USER" 2>/dev/null || true
    fi
    # Now create fresh user and group
    useradd -m -s /bin/bash "$APP_USER"
    usermod -aG audio,video,input "$APP_USER"
else
    echo "User $APP_USER already exists"
fi

# ALWAYS ensure home directory exists
mkdir -p /home/$APP_USER
chown $APP_USER:$APP_USER /home/$APP_USER

# Create package management group
PKG_MGMT_GROUP="spotify-pkgmgr"
echo -e "${YELLOW}Creating package management group...${NC}"
if ! getent group "$PKG_MGMT_GROUP" >/dev/null 2>&1; then
    groupadd "$PKG_MGMT_GROUP"
    echo "Created group $PKG_MGMT_GROUP for package management"
else
    echo "Group $PKG_MGMT_GROUP already exists"
fi

# Create admin user for the web panel
ADMIN_USER="spotify-admin"
echo -e "${YELLOW}Creating admin user for web panel...${NC}"

# Clean up any partial state first
if ! id "$ADMIN_USER" &>/dev/null; then
    # User doesn't exist, but group might - clean it up
    if getent group "$ADMIN_USER" >/dev/null 2>&1; then
        echo "Cleaning up existing group $ADMIN_USER from previous installation..."
        groupdel "$ADMIN_USER" 2>/dev/null || true
    fi
    # Now create fresh user and group
    useradd -r -M -s /bin/false "$ADMIN_USER"
    # Add admin user to package management group ONLY
    usermod -G "$PKG_MGMT_GROUP" "$ADMIN_USER"
else
    echo "User $ADMIN_USER already exists"
    # Ensure user is in package management group and ONLY that group
    usermod -G "$PKG_MGMT_GROUP" "$ADMIN_USER"
fi

# Add www-data to package management group
usermod -a -G "$PKG_MGMT_GROUP" www-data

# Note: Sudo permissions are now configured via the spotify-pkgmgr group
# This ensures the admin user only has access to specific package management commands

# Create application directories
echo -e "${YELLOW}Creating application directories...${NC}"
mkdir -p "$APP_DIR"
mkdir -p "$CONFIG_DIR"
mkdir -p "/var/log/spotify-kids"
mkdir -p "/var/log/nginx"

# Copy or download application files
echo -e "${YELLOW}Installing application files...${NC}"

# Check if running from local directory or curl
if [ -f "$SCRIPT_DIR/spotify_player.py" ]; then
    echo "Installing from local files..."
    cp "$SCRIPT_DIR/spotify_player.py" "$APP_DIR/"
    cp "$SCRIPT_DIR/parental_controls.py" "$APP_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/full_diagnostics.py" "$APP_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/remote_fix.py" "$APP_DIR/" 2>/dev/null || true
    cp "$SCRIPT_DIR/debug_web.py" "$APP_DIR/" 2>/dev/null || true
    cp -r "$SCRIPT_DIR/web" "$APP_DIR/"
else
    echo "Downloading files from GitHub..."
    # Main application files
    wget -q "$REPO_URL/spotify_player.py" -O "$APP_DIR/spotify_player.py"
    wget -q "$REPO_URL/parental_controls.py" -O "$APP_DIR/parental_controls.py" || echo "parental_controls.py not found"
    
    # Diagnostic and fix tools
    wget -q "$REPO_URL/full_diagnostics.py" -O "$APP_DIR/full_diagnostics.py" || echo "full_diagnostics.py not found"
    wget -q "$REPO_URL/remote_fix.py" -O "$APP_DIR/remote_fix.py" || echo "remote_fix.py not found"
    wget -q "$REPO_URL/debug_web.py" -O "$APP_DIR/debug_web.py" || echo "debug_web.py not found"
    
    # Web admin panel
    mkdir -p "$APP_DIR/web"
    mkdir -p "$APP_DIR/web/static"
    wget -q "$REPO_URL/web/app.py" -O "$APP_DIR/web/app.py"
    wget -q "$REPO_URL/web/static/admin.js" -O "$APP_DIR/web/static/admin.js"
fi

# Create a shared group for config access
CONFIG_GROUP="spotify-config"
if ! getent group "$CONFIG_GROUP" >/dev/null 2>&1; then
    groupadd "$CONFIG_GROUP"
fi

# Add both users to the config group
usermod -a -G "$CONFIG_GROUP" "$APP_USER"
usermod -a -G "$CONFIG_GROUP" "$ADMIN_USER"

# Set permissions
chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chown -R "$ADMIN_USER:$ADMIN_USER" "$APP_DIR/web"

# Make config dir accessible to both users via shared group
chown -R "$APP_USER:$CONFIG_GROUP" "$CONFIG_DIR"
chmod 775 "$CONFIG_DIR"
# Set group sticky bit so new files inherit the group
chmod g+s "$CONFIG_DIR"

# Create cache directory for player
mkdir -p "$CONFIG_DIR/.cache"
chown "$APP_USER:$CONFIG_GROUP" "$CONFIG_DIR/.cache"
chmod 775 "$CONFIG_DIR/.cache"

# Both users need access to logs
chown -R "$APP_USER:$APP_USER" "/var/log/spotify-kids"
chmod 775 "/var/log/spotify-kids"

# Set default permissions for config files
chmod 664 "$CONFIG_DIR"/*.json 2>/dev/null || true

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
After=multi-user.target graphical.target
Wants=graphical.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/$APP_USER/.Xauthority"
Environment="HOME=/home/$APP_USER"
Environment="SPOTIFY_CONFIG_DIR=$CONFIG_DIR"
Environment="SPOTIFY_DEBUG=true"
Environment="PYTHONUNBUFFERED=1"
WorkingDirectory=$APP_DIR
ExecStartPre=/bin/bash -c 'until [ -S /tmp/.X11-unix/X0 ]; do sleep 1; done'
ExecStart=/usr/bin/python3 -u $APP_DIR/spotify_player.py
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3
StandardOutput=journal
StandardError=journal

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
User=$ADMIN_USER
Group=$ADMIN_USER
Environment="SPOTIFY_CONFIG_DIR=$CONFIG_DIR"
WorkingDirectory=$APP_DIR/web
ExecStart=/usr/bin/python3 $APP_DIR/web/app.py
Restart=always
RestartSec=10
# Admin user needs to run commands
PrivateDevices=no
ProtectSystem=no
ProtectHome=no

[Install]
WantedBy=multi-user.target
EOF

# Generate SSL certificate for HTTPS (required for Spotify OAuth)
echo -e "${YELLOW}Generating SSL certificate for HTTPS...${NC}"
SSL_DIR="$APP_DIR/ssl"
mkdir -p $SSL_DIR
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $SSL_DIR/server.key \
    -out $SSL_DIR/server.crt \
    -subj "/C=US/ST=State/L=City/O=SpotifyKids/CN=$IP_ADDRESS" \
    -addext "subjectAltName=IP:$IP_ADDRESS,DNS:localhost" 2>/dev/null

# Set proper permissions
chown -R $APP_USER:$APP_USER $SSL_DIR
chmod 600 $SSL_DIR/server.key
chmod 644 $SSL_DIR/server.crt

# Configure nginx with HTTPS
echo -e "${YELLOW}Configuring nginx with HTTPS support...${NC}"
cat > /etc/nginx/sites-available/spotify-admin << EOF
# HTTPS server - main configuration
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name $IP_ADDRESS;

    ssl_certificate $SSL_DIR/server.crt;
    ssl_certificate_key $SSL_DIR/server.key;
    
    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://127.0.0.1:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }
}

# HTTP server - redirect to HTTPS
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $IP_ADDRESS;
    return 301 https://\$server_name\$request_uri;
}

# Port 8080 - redirect to HTTPS for backward compatibility
server {
    listen 8080;
    listen [::]:8080;
    server_name $IP_ADDRESS;
    return 301 https://$IP_ADDRESS\$request_uri;
}
EOF

ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Create .xinitrc for the user
echo -e "${YELLOW}Creating X session configuration...${NC}"
mkdir -p /home/$APP_USER
cat > /home/$APP_USER/.xinitrc << EOF
#!/bin/sh

# Log X session startup
echo "Starting X session at \$(date)" >> /var/log/spotify-kids/xsession.log

# Set display environment
export DISPLAY=:0
export XAUTHORITY=/home/$APP_USER/.Xauthority

# Wait for X server to be ready
sleep 2

# Disable screen blanking and power management
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Hide cursor after 3 seconds of inactivity
unclutter -idle 3 -root &

# Set background color to black
xsetroot -solid '#000000' 2>/dev/null || true

# Log before starting player
echo "Starting Spotify player at \$(date)" >> /var/log/spotify-kids/xsession.log

# Start the Spotify player with error logging
exec python3 $APP_DIR/spotify_player.py 2>&1 | tee -a /var/log/spotify-kids/player.log
EOF

chmod +x /home/$APP_USER/.xinitrc
chown $APP_USER:$APP_USER /home/$APP_USER/.xinitrc

# Create .bash_profile for auto-start
echo -e "${YELLOW}Configuring auto-start...${NC}"
mkdir -p /home/$APP_USER
cat > /home/$APP_USER/.bash_profile << EOF
#!/bin/bash

# Start X server with Spotify player on tty1
if [[ -z \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    exec startx
fi
EOF

chown -R $APP_USER:$APP_USER /home/$APP_USER

# Configure sudo permissions for package management group
echo -e "${YELLOW}Configuring sudo permissions for package management...${NC}"
cat > /etc/sudoers.d/spotify-pkgmgr << 'EOF'
# Allow package management group to run package updates without password
%spotify-pkgmgr ALL=(ALL) NOPASSWD:SETENV: /usr/bin/apt-get update
%spotify-pkgmgr ALL=(ALL) NOPASSWD:SETENV: /usr/bin/apt-get upgrade*
%spotify-pkgmgr ALL=(ALL) NOPASSWD:SETENV: /usr/bin/apt-get dist-upgrade*
%spotify-pkgmgr ALL=(ALL) NOPASSWD:SETENV: /usr/bin/apt-get autoremove*
%spotify-pkgmgr ALL=(ALL) NOPASSWD:SETENV: /usr/bin/apt-get autoclean*
%spotify-pkgmgr ALL=(ALL) NOPASSWD:SETENV: /usr/bin/apt-get clean
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/apt list*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/apt update
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/dpkg -l
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart spotify-player
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop spotify-player
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl start spotify-player
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl status spotify-player
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl is-active spotify-player
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart spotify-admin
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl start bluetooth
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl stop bluetooth
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/systemctl is-active bluetooth
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/bluetoothctl*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/sbin/rfkill*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/journalctl*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /bin/journalctl*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/tail*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/head*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/cat /var/log/*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /bin/cat /var/log/*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/truncate*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/dmesg*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /bin/dmesg*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/python3 /opt/spotify-kids/full_diagnostics.py
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /sbin/reboot
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /sbin/shutdown*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /sbin/poweroff
EOF
chmod 0440 /etc/sudoers.d/spotify-pkgmgr

# Enable services
echo -e "${YELLOW}Enabling services...${NC}"
systemctl daemon-reload
systemctl enable spotify-admin.service
systemctl enable nginx
systemctl start spotify-admin.service
systemctl restart nginx

# Configure X11
echo -e "${YELLOW}Configuring X11 display server...${NC}"
mkdir -p /etc/X11/xorg.conf.d/

# Create basic X11 configuration
cat > /etc/X11/xorg.conf.d/10-serverflags.conf << EOF
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
    Option "DontZap" "false"
    Option "AllowMouseOpenFail" "true"
EndSection
EOF

# Configure display
cat > /etc/X11/xorg.conf.d/20-display.conf << EOF
Section "Monitor"
    Identifier "Monitor0"
    Option "DPMS" "false"
EndSection

Section "Screen"
    Identifier "Screen0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080" "1280x720" "1024x768" "800x600"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen "Screen0"
EndSection
EOF

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
EndSection
EOF
fi

# Configure Bluetooth and audio
echo -e "${YELLOW}Configuring Bluetooth and audio...${NC}"

# Enable Bluetooth service
systemctl enable bluetooth.service
systemctl start bluetooth.service

# Configure PulseAudio for Bluetooth
if ! grep -q "load-module module-bluetooth-policy" /etc/pulse/default.pa 2>/dev/null; then
    echo "load-module module-bluetooth-policy" >> /etc/pulse/default.pa
fi
if ! grep -q "load-module module-bluetooth-discover" /etc/pulse/default.pa 2>/dev/null; then
    echo "load-module module-bluetooth-discover" >> /etc/pulse/default.pa
fi

# Add spotify-kids user to audio and bluetooth groups
usermod -aG bluetooth,audio "$APP_USER"

# Set Bluetooth to be discoverable and pairable
bluetoothctl power on 2>/dev/null || true
bluetoothctl agent on 2>/dev/null || true
bluetoothctl default-agent 2>/dev/null || true
bluetoothctl discoverable on 2>/dev/null || true
bluetoothctl pairable on 2>/dev/null || true

# Disable unnecessary services
echo -e "${YELLOW}Optimizing system...${NC}"
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
rm -f /etc/nginx/sites-available/spotify-admin-ssl
rm -f /etc/nginx/sites-enabled/spotify-admin-ssl
rm -f /etc/sudoers.d/spotify-admin
rm -f /etc/sudoers.d/spotify-pkgmgr
rm -rf $APP_DIR
userdel -r $APP_USER 2>/dev/null
userdel spotify-admin 2>/dev/null
groupdel spotify-pkgmgr 2>/dev/null
groupdel spotify-config 2>/dev/null
rm -f /usr/local/bin/spotify-kids-uninstall
echo "Uninstall complete"
EOF
chmod +x /usr/local/bin/spotify-kids-uninstall

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "Admin Panel: ${GREEN}https://$(hostname -I | awk '{print $1}')${NC}"
echo -e "Default login: ${YELLOW}admin / changeme${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT for Spotify Authentication:${NC}"
echo -e "1. Your browser will show a security warning (self-signed certificate)"
echo -e "   Click 'Advanced' and 'Proceed' to continue"
echo ""
echo -e "2. Add this URL to your Spotify app's Redirect URIs:"
echo -e "   ${GREEN}https://$(hostname -I | awk '{print $1}')/callback${NC}"
echo ""
echo -e "The system will restart in 10 seconds to apply all changes."
echo -e "After restart, the Spotify player will start automatically."
echo ""
echo -e "To uninstall, run: ${YELLOW}sudo spotify-kids-uninstall${NC}"
echo ""

# Restart system
sleep 10
reboot