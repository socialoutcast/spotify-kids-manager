#!/bin/bash
#
# Spotify Kids Manager - Installation Script
# Copyright (c) 2025 SavageIndustries. All rights reserved.
#
# This is proprietary software. Unauthorized copying, modification, distribution,
# or reverse engineering is strictly prohibited. See LICENSE file for details.
#

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

# Function to wait for apt/dpkg locks to be released
wait_for_apt() {
    echo -e "${YELLOW}Checking for running package managers...${NC}"
    
    while true; do
        # Check if apt, apt-get, dpkg, or unattended-upgrades are running
        if pgrep -x "apt" > /dev/null || \
           pgrep -x "apt-get" > /dev/null || \
           pgrep -x "dpkg" > /dev/null || \
           pgrep -f "unattended-upgrade" > /dev/null; then
            echo -e "${YELLOW}Another package manager is running. Waiting...${NC}"
            sleep 5
        else
            # Also check for lock files
            if fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
               fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
               fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
               fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
                echo -e "${YELLOW}Package database is locked. Waiting...${NC}"
                sleep 5
            else
                echo -e "${GREEN}Package manager is available.${NC}"
                break
            fi
        fi
    done
    
    # Give it a moment to ensure everything is clear
    sleep 2
}

# Wait for apt to be available before starting
wait_for_apt

# Clean up any old installations
if [ -d "/opt/spotify-terminal" ] || [ -d "/opt/spotify-kids" ] && [ "$RESET_MODE" = false ]; then
    echo -e "${YELLOW}Found existing installation. Use --reset to remove it first.${NC}"
    echo -e "${RED}Installation aborted to prevent data loss.${NC}"
    exit 1
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
    rm -rf /opt/spotify-kids
    rm -rf /opt/spotify-terminal 2>/dev/null || true
    
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
wait_for_apt
echo "Running apt-get update..."
apt-get update || {
    echo -e "${YELLOW}Initial update failed, retrying...${NC}"
    sleep 2
    wait_for_apt
    apt-get update
}

echo "Running apt-get upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || true

echo "Handling held-back packages with dist-upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -q \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" || true

echo "Removing unnecessary packages..."
apt-get autoremove -y || true

echo "Cleaning package cache..."
apt-get autoclean -y || true

echo "System update complete"

# Remove bloatware to free up space for kiosk device
echo -e "${YELLOW}Removing unnecessary software to free up space...${NC}"
wait_for_apt
apt-get remove -y --purge \
    libreoffice* \
    libreoffice-* \
    openoffice* \
    thunderbird* \
    evolution* \
    pidgin* \
    hexchat* \
    gimp* \
    inkscape* \
    audacity* \
    vlc* \
    transmission* \
    brasero* \
    cheese* \
    rhythmbox* \
    totem* \
    2>/dev/null || true

# Clean up after removal
apt-get autoremove -y
apt-get autoclean -y

# Install common fonts for web display
echo -e "${YELLOW}Installing common fonts...${NC}"
apt-get install -y \
    fonts-liberation \
    fonts-liberation2 \
    fonts-dejavu-core \
    fonts-dejavu-extra \
    fonts-droid-fallback \
    fonts-noto-mono \
    fonts-noto-color-emoji \
    fonts-roboto \
    fonts-ubuntu \
    fonts-font-awesome \
    fonts-material-design-icons-iconfont \
    2>/dev/null || true

# Accept Microsoft fonts EULA automatically
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections
apt-get install -y ttf-mscorefonts-installer 2>/dev/null || true

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"

# First ensure package lists are up to date
echo -e "${BLUE}Ensuring package lists are current...${NC}"
wait_for_apt
apt-get update || true

# Install packages in smaller groups to handle failures better
echo -e "${BLUE}Installing Python packages...${NC}"
apt-get install -y \
    python3 \
    python3-pip \
    python3-tk \
    python3-pil \
    python3-pil.imagetk || true

echo -e "${BLUE}Installing X server packages...${NC}"
apt-get install -y \
    xserver-xorg \
    xserver-xorg-video-all \
    xserver-xorg-input-all \
    xinit \
    x11-xserver-utils \
    x11-utils \
    x11-apps \
    xterm || true

echo -e "${BLUE}Installing web server...${NC}"
# Update again before nginx to avoid 404 errors
wait_for_apt
apt-get update
apt-get install -y nginx || {
    echo -e "${YELLOW}nginx installation failed, updating repos and retrying...${NC}"
    wait_for_apt
    apt-get update
    apt-get install -y nginx
}

echo -e "${BLUE}Installing window manager and display packages...${NC}"
apt-get install -y \
    openbox \
    lightdm \
    unclutter || true

echo -e "${BLUE}Installing browser...${NC}"
apt-get install -y chromium || apt-get install -y chromium-browser || true

echo -e "${BLUE}Installing Bluetooth and audio packages...${NC}"
apt-get install -y \
    bluez \
    bluez-firmware \
    bluez-tools \
    bluez-alsa-utils \
    pulseaudio \
    pulseaudio-module-bluetooth \
    libasound2-plugins \
    libspa-0.2-bluetooth \
    pi-bluetooth \
    pulseaudio-utils || true

echo -e "${BLUE}Installing utility packages...${NC}"
apt-get install -y \
    git \
    rfkill \
    scrot \
    curl \
    expect || true

# Install Node.js for the web player
echo -e "${YELLOW}Installing Node.js...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
fi
NODE_VERSION=$(node --version 2>/dev/null || echo "not installed")
echo -e "${GREEN}Node.js version: ${NODE_VERSION}${NC}"

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

# Final cleanup after all installations
echo -e "${YELLOW}Final system cleanup...${NC}"
apt-get autoremove -y || true
apt-get autoclean -y || true

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
if [ -f "$SCRIPT_DIR/web/app.py" ]; then
    echo "Installing from local files..."
    # Web admin panel
    cp -r "$SCRIPT_DIR/web" "$APP_DIR/"
    # Player application
    cp -r "$SCRIPT_DIR/player" "$APP_DIR/"
    # Kiosk launcher
    cp "$SCRIPT_DIR/kiosk_launcher.sh" "$APP_DIR/" 2>/dev/null || true
else
    echo "Downloading files from GitHub..."
    # Web admin panel
    mkdir -p "$APP_DIR/web"
    mkdir -p "$APP_DIR/web/static"
    wget -q "$REPO_URL/web/app.py" -O "$APP_DIR/web/app.py"
    wget -q "$REPO_URL/web/static/admin.js" -O "$APP_DIR/web/static/admin.js"
    
    # Player application
    mkdir -p "$APP_DIR/player"
    mkdir -p "$APP_DIR/player/client"
    wget -q "$REPO_URL/player/package.json" -O "$APP_DIR/player/package.json"
    wget -q "$REPO_URL/player/server.js" -O "$APP_DIR/player/server.js"
    wget -q "$REPO_URL/player/spotify-player.service" -O "$APP_DIR/player/spotify-player.service"
    wget -q "$REPO_URL/player/client/index.html" -O "$APP_DIR/player/client/index.html"
    
    # Kiosk launcher
    wget -q "$REPO_URL/kiosk_launcher.sh" -O "$APP_DIR/kiosk_launcher.sh" || echo "kiosk_launcher.sh not found"
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

# Configure display manager for auto-login (using LightDM, not getty)
echo -e "${YELLOW}Configuring display manager...${NC}"

# Disable getty on tty1 to prevent conflicts
systemctl disable getty@tty1 2>/dev/null || true
systemctl stop getty@tty1 2>/dev/null || true
rm -rf /etc/systemd/system/getty@tty1.service.d 2>/dev/null || true

# Create openbox autostart file
mkdir -p /home/$APP_USER/.config/openbox
cat > /home/$APP_USER/.config/openbox/autostart << 'EOF'
# Disable screen saver and power management
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor
unclutter -idle 0.1 &

# Start the kiosk launcher
/opt/spotify-kids/kiosk_launcher.sh &
EOF
chown -R $APP_USER:$APP_USER /home/$APP_USER/.config
chmod 755 /home/$APP_USER/.config/openbox/autostart

# Configure LightDM for auto-login with openbox
echo -e "${YELLOW}Configuring LightDM...${NC}"
cat > /etc/lightdm/lightdm.conf << EOF
[Seat:*]
autologin-user=$APP_USER
autologin-user-timeout=0
user-session=openbox
greeter-hide-users=true
greeter-show-manual-login=false
allow-guest=false
xserver-command=X -nocursor
EOF

# Set openbox as default X session manager
update-alternatives --set x-session-manager /usr/bin/openbox-session 2>/dev/null || true

# Install Node.js dependencies for player
echo -e "${YELLOW}Installing player dependencies...${NC}"
cd "$APP_DIR/player"
sudo -u $APP_USER npm install --omit=dev

# Create cache directory
mkdir -p "$CONFIG_DIR/cache"
chown $APP_USER:$CONFIG_GROUP "$CONFIG_DIR/cache"
chmod 775 "$CONFIG_DIR/cache"

# Create systemd service for the player
echo -e "${YELLOW}Creating systemd service for player...${NC}"
cat > /etc/systemd/system/spotify-player.service << EOF
[Unit]
Description=Spotify Kids Web Player
After=network.target bluetooth.service pulseaudio-spotify-kids.service
Wants=network-online.target bluetooth.service pulseaudio-spotify-kids.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/player
Environment="NODE_ENV=production"
Environment="PORT=5000"
Environment="SPOTIFY_CONFIG_DIR=$CONFIG_DIR"
Environment="PULSE_RUNTIME_PATH=/tmp/pulse-spotify-kids"
Environment="XDG_RUNTIME_DIR=/tmp"
ExecStartPre=/bin/bash -c 'if [ ! -d "node_modules" ]; then npm install --omit=dev; fi'
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3
StandardOutput=journal
StandardError=journal
SyslogIdentifier=spotify-player
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$CONFIG_DIR

[Install]
WantedBy=multi-user.target
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
IP_ADDRESS=$(hostname -I 2>/dev/null | awk '{print $1}')

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

# Create kiosk launcher script
echo -e "${YELLOW}Creating kiosk launcher...${NC}"
cat > "$APP_DIR/kiosk_launcher.sh" << 'EOF'
#!/bin/bash

# Spotify Kids Player Kiosk Mode Launcher
# This script launches Chromium in kiosk mode displaying the web player

# Redirect all output to /dev/null to prevent terminal flashing
exec > /dev/null 2>&1

# Change to a directory the spotify-kids user has access to
cd /opt/spotify-kids || cd /tmp

# Wait for network to be ready
sleep 10

# Auto-detect the display
if [ -z "$DISPLAY" ]; then
    # Find the active X display
    for display in 0 1 2; do
        if [ -S /tmp/.X11-unix/X${display} ]; then
            export DISPLAY=:${display}
            break
        fi
    done
fi

# Try to get X authorization if needed
if [ -f /home/spotify-kids/.Xauthority ]; then
    export XAUTHORITY=/home/spotify-kids/.Xauthority
fi

# Disable screen blanking and power management
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Hide mouse cursor immediately for touchscreen
unclutter -idle 0 -root &

# Remove any existing chromium preferences that might interfere
rm -rf /home/spotify-kids/.config/chromium/Singleton*

# Wait for the web player to be ready
until curl -s http://localhost:5000 > /dev/null 2>&1; do
    sleep 2
done

# Kill any existing chromium instances first
pkill -f "chromium.*kiosk" 2>/dev/null || true
sleep 2

# Launch chromium - systemd will restart if it crashes
exec chromium-browser \
    --kiosk \
    --noerrdialogs \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-translate \
    --no-first-run \
    --fast \
    --fast-start \
    --disable-features=TranslateUI \
    --check-for-update-interval=31536000 \
    --disable-pinch \
    --overscroll-history-navigation=0 \
    --disable-component-update \
    --autoplay-policy=no-user-gesture-required \
    --window-position=0,0 \
    --user-data-dir=/home/spotify-kids/.config/chromium-kiosk \
    "http://localhost:5000"
EOF

chmod +x "$APP_DIR/kiosk_launcher.sh"
chown $APP_USER:$APP_USER "$APP_DIR/kiosk_launcher.sh"

# Create systemd service for kiosk mode
echo -e "${YELLOW}Creating kiosk service...${NC}"
cat > /etc/systemd/system/spotify-kiosk.service << EOF
[Unit]
Description=Spotify Kids Player Kiosk Mode
After=graphical.target spotify-player.service
Wants=graphical.target
Requires=spotify-player.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/$APP_USER/.Xauthority"
Environment="HOME=/home/$APP_USER"

# Wait for X11 to be ready
ExecStartPre=/bin/bash -c 'until [ -S /tmp/.X11-unix/X0 ]; do sleep 2; done'
ExecStartPre=/bin/sleep 5

# Start kiosk
ExecStart=$APP_DIR/kiosk_launcher.sh

# Restart if crashes
Restart=always
RestartSec=10

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
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
%spotify-pkgmgr ALL=(spotify-kids) NOPASSWD: /usr/bin/bluetoothctl*
%spotify-pkgmgr ALL=(spotify-kids) NOPASSWD: /usr/bin/expect*
%spotify-pkgmgr ALL=(spotify-kids) NOPASSWD: /usr/bin/pactl*
%spotify-pkgmgr ALL=(spotify-kids) NOPASSWD: /usr/bin/pacmd*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/journalctl*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /bin/journalctl*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/tail*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/head*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/cat /var/log/*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /bin/cat /var/log/*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/truncate*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/dmesg*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /bin/dmesg*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /sbin/reboot
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /sbin/shutdown*
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /sbin/poweroff
EOF
chmod 0440 /etc/sudoers.d/spotify-pkgmgr

# Disable Plymouth splash screen to prevent flashing
echo -e "${YELLOW}Disabling splash screens...${NC}"
systemctl disable plymouth-quit-wait 2>/dev/null || true
systemctl disable plymouth-start 2>/dev/null || true

# Update boot parameters to hide boot messages
echo -e "${YELLOW}Updating boot parameters...${NC}"
if [ -f /boot/cmdline.txt ]; then
    # Raspberry Pi boot config
    cp /boot/cmdline.txt /boot/cmdline.txt.backup
    # Remove any existing splash/quiet parameters and add our own
    sed -i 's/ splash//g; s/ quiet//g; s/ plymouth.ignore-serial-consoles//g; s/ logo.nologo//g; s/ vt.global_cursor_default=0//g; s/ consoleblank=0//g; s/ loglevel=[0-9]//g' /boot/cmdline.txt
    # Add parameters to hide boot messages
    sed -i 's/$/ quiet loglevel=0 logo.nologo vt.global_cursor_default=0 consoleblank=0/' /boot/cmdline.txt
elif [ -f /etc/default/grub ]; then
    # GRUB systems
    cp /etc/default/grub /etc/default/grub.backup
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=0 logo.nologo vt.global_cursor_default=0 consoleblank=0"/' /etc/default/grub
    update-grub 2>/dev/null || true
fi

# Set graphical target as default
systemctl set-default graphical.target

# Enable services
echo -e "${YELLOW}Enabling services...${NC}"
# Reload systemd to recognize all new service files
systemctl daemon-reload
# Enable display manager
systemctl enable lightdm
systemctl enable spotify-player.service
systemctl enable spotify-admin.service
systemctl enable spotify-kiosk.service
systemctl enable nginx
systemctl start spotify-player.service
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

# Stop and mask conflicting services (PipeWire)
echo -e "${BLUE}Disabling PipeWire to use PulseAudio...${NC}"
systemctl stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
systemctl disable pipewire pipewire-pulse wireplumber 2>/dev/null || true
systemctl mask pipewire pipewire-pulse wireplumber 2>/dev/null || true
killall -9 pipewire pipewire-pulse wireplumber 2>/dev/null || true

# CRITICAL: Disable bluealsa which conflicts with PulseAudio
echo -e "${BLUE}Disabling bluealsa to prevent conflicts with PulseAudio...${NC}"
systemctl stop bluealsa 2>/dev/null || true
systemctl disable bluealsa 2>/dev/null || true
systemctl mask bluealsa 2>/dev/null || true
killall -9 bluealsa bluealsa-aplay 2>/dev/null || true

# Configure Bluetooth for A2DP only (HiFi audio, no hands-free)
echo -e "${BLUE}Configuring Bluetooth for HiFi audio only...${NC}"
cat > /etc/bluetooth/main.conf << 'EOF'
[General]
Name = raspberrypi
Class = 0x00041C
DiscoverableTimeout = 0
PairableTimeout = 0
FastConnectable = true

[Policy]
AutoEnable=true
EOF

# Disable HFP/HSP profiles, keep only A2DP
cat > /etc/bluetooth/audio.conf << 'EOF'
[General]
Enable=Source,Sink,Media,Socket
Disable=Headset,Gateway
AutoConnect=true
EOF

# Enable Bluetooth service
systemctl enable bluetooth.service
systemctl restart bluetooth.service
sleep 3

# Configure PulseAudio for spotify-kids user
echo -e "${BLUE}Setting up PulseAudio for high-quality audio...${NC}"

# Add spotify-kids user to required groups (including lp for DBus)
usermod -aG bluetooth,audio,pulse-access,lp "$APP_USER"

# Create PulseAudio user config directory
mkdir -p /home/$APP_USER/.config/pulse

# Audio settings optimized for Bluetooth compatibility
cat > /home/$APP_USER/.config/pulse/daemon.conf << 'EOF'
# Standard quality settings for Bluetooth
default-sample-format = s16le
default-sample-rate = 44100
alternate-sample-rate = 48000
resample-method = trivial
avoid-resampling = yes
high-priority = yes
nice-level = -11
realtime-scheduling = yes
realtime-priority = 5
default-fragments = 4
default-fragment-size-msec = 25
EOF

# Create default.pa to load Bluetooth modules
cat > /home/$APP_USER/.config/pulse/default.pa << 'EOF'
.include /etc/pulse/default.pa
load-module module-bluetooth-policy
load-module module-bluetooth-discover
load-module module-switch-on-connect
EOF

# Client config for spotify-kids
cat > /home/$APP_USER/.config/pulse/client.conf << 'EOF'
autospawn = yes
daemon-binary = /usr/bin/pulseaudio
extra-arguments = --log-target=syslog
EOF

chown -R $APP_USER:$APP_USER /home/$APP_USER/.config
chown $APP_USER:$APP_USER /home/$APP_USER/.bashrc

# Create Bluetooth config directory
mkdir -p /home/$APP_USER/.config/bluetooth
chown -R $APP_USER:$APP_USER /home/$APP_USER/.config/bluetooth

# Bluetooth will be configured when devices are paired through the admin interface

# Create dedicated PulseAudio service with DBus session for Bluetooth
cat > /etc/systemd/system/pulseaudio-spotify-kids.service << 'EOF'
[Unit]
Description=PulseAudio for Spotify Kids with Bluetooth
After=bluetooth.service dbus.service
Requires=dbus.service
Wants=bluetooth.service

[Service]
Type=simple
User=spotify-kids
Group=audio

# Environment
Environment="HOME=/home/spotify-kids"
Environment="PULSE_RUNTIME_PATH=/run/user/1001"
Environment="XDG_RUNTIME_DIR=/run/user/1001"

# Start with DBus session (systemd handles runtime directories)
ExecStart=/usr/bin/dbus-launch --exit-with-session /usr/bin/pulseaudio --daemonize=no --log-target=journal --high-priority --realtime

# Permissions
SupplementaryGroups=audio bluetooth lp
PrivateDevices=no

# Auto-restart
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Configure DBus permissions for Bluetooth access
cat > /etc/dbus-1/system.d/spotify-bluetooth.conf << 'EOF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <policy user="spotify-kids">
    <allow own="org.bluez"/>
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.*"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
    <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
  </policy>
  <policy user="spotify-admin">
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.*"/>
    <allow send_interface="org.freedesktop.DBus.Properties"/>
    <allow send_interface="org.freedesktop.DBus.ObjectManager"/>
  </policy>
  <policy group="spotify-pkgmgr">
    <allow send_destination="org.bluez"/>
    <allow send_interface="org.bluez.*"/>
  </policy>
</busconfig>
EOF

# Reload DBus configuration
systemctl reload dbus 2>/dev/null || true

# Enable Bluetooth experimental features for better PulseAudio integration
mkdir -p /etc/systemd/system/bluetooth.service.d
cat > /etc/systemd/system/bluetooth.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/libexec/bluetooth/bluetoothd -E
EOF

# Restart Bluetooth with new configuration
systemctl daemon-reload
systemctl restart bluetooth.service
sleep 3

# Enable and start PulseAudio service
systemctl enable pulseaudio-spotify-kids.service
systemctl start pulseaudio-spotify-kids.service

# Wait for PulseAudio service to be ready
echo -e "${BLUE}Waiting for PulseAudio to be ready...${NC}"
sleep 5  # Give time for DBus session to establish
for i in {1..10}; do
    if sudo -u $APP_USER pactl info >/dev/null 2>&1; then
        echo -e "${GREEN}PulseAudio is ready${NC}"
        # Load Bluetooth modules after PulseAudio is ready
        sudo -u $APP_USER pactl load-module module-bluetooth-policy 2>/dev/null || true
        sudo -u $APP_USER pactl load-module module-bluetooth-discover 2>/dev/null || true
        break
    fi
    echo "Waiting for PulseAudio... ($i/10)"
    sleep 2
done

# Note: PulseAudio's module-bluetooth-policy handles A2DP profile switching automatically
# No additional scripts needed for Bluetooth profile management

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
systemctl stop spotify-kiosk.service 2>/dev/null
systemctl stop pulseaudio-spotify-kids.service 2>/dev/null
systemctl disable spotify-player.service 2>/dev/null
systemctl disable spotify-admin.service 2>/dev/null
systemctl disable spotify-kiosk.service 2>/dev/null
systemctl disable pulseaudio-spotify-kids.service 2>/dev/null
rm -f /etc/systemd/system/spotify*.service
rm -f /etc/systemd/system/pulseaudio-spotify-kids.service
rm -f /etc/nginx/sites-available/spotify-admin
rm -f /etc/nginx/sites-enabled/spotify-admin
rm -f /etc/nginx/sites-available/spotify-admin-ssl
rm -f /etc/nginx/sites-enabled/spotify-admin-ssl
rm -f /etc/sudoers.d/spotify-*
rm -f /etc/sudoers.d/90-spotify-pkgmgr
rm -f /etc/dbus-1/system.d/spotify-bluetooth.conf
rm -rf $APP_DIR
userdel -r $APP_USER 2>/dev/null
userdel spotify-admin 2>/dev/null
groupdel spotify-pkgmgr 2>/dev/null
groupdel spotify-config 2>/dev/null
# Unmask PipeWire if it was masked
systemctl unmask pipewire pipewire-pulse wireplumber 2>/dev/null
rm -f /usr/local/bin/spotify-kids-uninstall
echo "Uninstall complete"
EOF
chmod +x /usr/local/bin/spotify-kids-uninstall

# Get the device IP address
DEVICE_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
CALLBACK_URL="https://${DEVICE_IP}/callback"

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "Admin Panel: ${GREEN}https://${DEVICE_IP}${NC}"
echo -e "Default login: ${YELLOW}admin / changeme${NC}"
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}CRITICAL - Spotify App Setup Required:${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Step 1: Go to Spotify Developer Dashboard${NC}"
echo -e "        ${BLUE}https://developer.spotify.com/dashboard${NC}"
echo ""
echo -e "${YELLOW}Step 2: Create or Edit Your App${NC}"
echo -e "        - Click 'Create App' or select existing app"
echo -e "        - App name: Spotify Kids Player"
echo ""
echo -e "${YELLOW}Step 3: Add EXACTLY This Redirect URI:${NC}"
echo -e "        ${GREEN}${CALLBACK_URL}${NC}"
echo -e "        ⚠️  ${RED}MUST be HTTPS and EXACT match!${NC}"
echo ""
echo -e "${YELLOW}Step 4: Save Your App Settings${NC}"
echo -e "        - Click 'Save' in Spotify Dashboard"
echo ""
echo -e "${YELLOW}Step 5: Get Your Credentials${NC}"
echo -e "        - Copy your Client ID"
echo -e "        - Copy your Client Secret"
echo ""
echo -e "${YELLOW}Step 6: Configure in Admin Panel${NC}"
echo -e "        - Go to ${GREEN}https://${DEVICE_IP}${NC}"
echo -e "        - Enter credentials in Spotify Configuration"
echo -e "        - Click 'Authenticate with Spotify'"
echo ""
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Browser Security Warning:${NC}"
echo -e "Your browser will show a security warning (self-signed certificate)"
echo -e "Click 'Advanced' and 'Proceed to ${DEVICE_IP}' to continue"
echo ""
echo -e "The system will restart in 30 seconds to apply all changes."
echo -e "After restart, the Spotify player will start automatically."
echo ""
echo -e "To uninstall, run: ${YELLOW}sudo spotify-kids-uninstall${NC}"
echo ""

# Restart system
sleep 30
reboot