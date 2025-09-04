#!/bin/bash

# Spotify Kids Manager - Release-based Installer
# This version downloads pre-packaged releases instead of source files
# Usage: curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install-release.sh | sudo bash

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
REPO_URL="https://github.com/socialoutcast/spotify-kids-manager"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Spotify Kids Manager - Installer${NC}"
echo -e "${GREEN}================================${NC}"
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   echo "Please run: curl -sSL $REPO_URL/raw/main/install-release.sh | sudo bash"
   exit 1
fi

# Detect system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
else
    echo -e "${RED}Cannot detect operating system${NC}"
    exit 1
fi

echo -e "${YELLOW}Detected OS: $OS $VER${NC}"

# Get the device IP address
DEVICE_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$DEVICE_IP" ]; then
    DEVICE_IP="localhost"
fi

# Function to download from GitHub releases
download_release_asset() {
    local asset_name=$1
    local output_path=$2
    
    echo -e "${YELLOW}Downloading $asset_name...${NC}"
    
    # Get latest release URL
    local latest_release_url="$REPO_URL/releases/latest/download/$asset_name"
    
    # Download with retry logic
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        if wget -q --show-progress "$latest_release_url" -O "$output_path"; then
            echo -e "${GREEN}✓ Downloaded $asset_name${NC}"
            return 0
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                echo -e "${YELLOW}Download failed, retrying... ($retry/$max_retries)${NC}"
                sleep 2
            fi
        fi
    done
    
    echo -e "${RED}Failed to download $asset_name${NC}"
    return 1
}

# Stop existing services if they exist
echo -e "${YELLOW}Stopping existing services...${NC}"
systemctl stop spotify-player 2>/dev/null || true
systemctl stop spotify-admin 2>/dev/null || true
systemctl stop spotify-kiosk 2>/dev/null || true
systemctl stop pulseaudio-spotify-kids 2>/dev/null || true

# Install system dependencies
echo -e "${YELLOW}Installing system dependencies...${NC}"
apt-get update
apt-get install -y \
    python3 python3-pip python3-venv \
    nodejs npm \
    nginx \
    git \
    curl wget \
    chromium-browser \
    xinit xorg \
    openbox \
    unclutter \
    alsa-utils \
    pulseaudio \
    pulseaudio-module-bluetooth \
    bluez \
    openssl \
    sudo

# Disable conflicting services
echo -e "${YELLOW}Configuring audio system...${NC}"
systemctl stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
systemctl disable pipewire pipewire-pulse wireplumber 2>/dev/null || true
systemctl mask pipewire pipewire-pulse wireplumber 2>/dev/null || true
systemctl stop bluealsa 2>/dev/null || true
systemctl disable bluealsa 2>/dev/null || true
systemctl mask bluealsa 2>/dev/null || true

# Create application user
if ! id "$APP_USER" &>/dev/null; then
    echo -e "${YELLOW}Creating application user...${NC}"
    useradd -r -m -s /bin/bash -d /home/$APP_USER $APP_USER
    usermod -a -G audio,video,bluetooth,pulse-access,input,tty,dialout,gpio,lp $APP_USER
fi

# Get user UID for later use
APP_USER_UID=$(id -u $APP_USER)

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p $APP_DIR
mkdir -p $CONFIG_DIR
mkdir -p $CONFIG_DIR/cache
mkdir -p /var/log/spotify-kids
mkdir -p /home/$APP_USER/.config/pulse
mkdir -p /home/$APP_USER/.config/openbox

# Download release packages
echo -e "${YELLOW}Downloading application packages from GitHub releases...${NC}"

TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR

# Download the packages
if ! download_release_asset "spotify-kids-web.tar.gz" "web.tar.gz"; then
    echo -e "${RED}Failed to download web package. Please check if a release exists at:${NC}"
    echo -e "${YELLOW}$REPO_URL/releases${NC}"
    exit 1
fi

if ! download_release_asset "spotify-kids-player.tar.gz" "player.tar.gz"; then
    echo -e "${RED}Failed to download player package${NC}"
    exit 1
fi

if ! download_release_asset "kiosk_launcher.sh" "kiosk_launcher.sh"; then
    echo -e "${YELLOW}Warning: Could not download kiosk_launcher.sh, will create default${NC}"
fi

# Extract packages
echo -e "${YELLOW}Extracting packages...${NC}"
tar xzf web.tar.gz -C $APP_DIR/
tar xzf player.tar.gz -C $APP_DIR/

# Copy or create kiosk launcher
if [ -f "kiosk_launcher.sh" ]; then
    cp kiosk_launcher.sh $APP_DIR/
else
    # Create default kiosk launcher if download failed
    cat > "$APP_DIR/kiosk_launcher.sh" << 'EOF'
#!/bin/bash

# Spotify Kids Player Kiosk Mode Launcher
# Set PulseAudio environment FIRST (before any exec redirects)
APP_USER_UID=$(id -u spotify-kids)
export PULSE_RUNTIME_PATH=/run/user/$APP_USER_UID
export XDG_RUNTIME_DIR=/run/user/$APP_USER_UID
export PULSE_SERVER=/run/user/$APP_USER_UID/pulse/native
export HOME=/home/spotify-kids

# Redirect all output to /dev/null to prevent terminal flashing
exec > /dev/null 2>&1

# Change to a directory the spotify-kids user has access to
cd /opt/spotify-kids || cd /tmp

# Wait for network to be ready
sleep 10

# Auto-detect the display
if [ -z "$DISPLAY" ]; then
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
fi

chmod +x "$APP_DIR/kiosk_launcher.sh"
chown $APP_USER:$APP_USER "$APP_DIR/kiosk_launcher.sh"

# Cleanup temp directory
cd /
rm -rf $TEMP_DIR

# Create a shared group for config access
groupadd -f spotify-config
usermod -a -G spotify-config $APP_USER
usermod -a -G spotify-config spotify-admin 2>/dev/null || true

# Create package manager privilege group
groupadd -f spotify-pkgmgr
usermod -a -G spotify-pkgmgr $APP_USER

# Add sudoers entry for package management
cat > /etc/sudoers.d/90-spotify-pkgmgr << 'EOF'
# Allow spotify-pkgmgr group to run package management commands
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/apt-get update
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/apt-get install *
%spotify-pkgmgr ALL=(ALL) NOPASSWD: /usr/bin/dpkg *
EOF

chmod 440 /etc/sudoers.d/90-spotify-pkgmgr

# Install Python dependencies for web admin
echo -e "${YELLOW}Installing Python dependencies...${NC}"
cd $APP_DIR/web
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask flask-cors flask-login spotipy requests python-dotenv

# Create default admin user
python3 -c "
import sys
sys.path.insert(0, '$APP_DIR')
from web.app import db, User
import os
db_path = '$CONFIG_DIR/admin.db'
os.makedirs(os.path.dirname(db_path), exist_ok=True)
from werkzeug.security import generate_password_hash

# Create database
import sqlite3
conn = sqlite3.connect(db_path)
c = conn.cursor()
c.execute('''CREATE TABLE IF NOT EXISTS users
             (id INTEGER PRIMARY KEY, username TEXT UNIQUE, password TEXT, 
              is_active INTEGER DEFAULT 1, last_login TEXT)''')

# Add default admin user
try:
    password_hash = generate_password_hash('changeme')
    c.execute('INSERT INTO users (username, password) VALUES (?, ?)', 
              ('admin', password_hash))
    print('Created default admin user')
except:
    print('Admin user already exists')
    
conn.commit()
conn.close()
" 2>/dev/null || echo "Admin user setup completed"

deactivate

# Set up PulseAudio
echo -e "${YELLOW}Configuring PulseAudio...${NC}"

# Configure Bluetooth
cat > /etc/bluetooth/main.conf << 'EOF'
[General]
Enable=Source,Sink,Media,Socket
DiscoverableTimeout = 0
AlwaysPairable = true
FastConnectable = true

[Policy]
AutoEnable=true
EOF

# Create Bluetooth override to add -E flag
mkdir -p /etc/systemd/system/bluetooth.service.d
cat > /etc/systemd/system/bluetooth.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=/usr/lib/bluetooth/bluetoothd -E
EOF

# Create PulseAudio config for spotify-kids user
cat > /home/$APP_USER/.config/pulse/daemon.conf << 'EOF'
default-sample-format = s16le
default-sample-rate = 44100
alternate-sample-rate = 48000
resample-method = speex-float-1
enable-lfe-remixing = no
high-priority = yes
nice-level = -11
realtime-scheduling = yes
realtime-priority = 5
default-fragments = 4
default-fragment-size-msec = 25
EOF

# Create PulseAudio default.pa configuration
cat > /home/$APP_USER/.config/pulse/default.pa << 'EOF'
.include /etc/pulse/default.pa

# Bluetooth support with auto-switching
.ifexists module-bluetooth-policy.so
load-module module-bluetooth-policy auto_switch=2
.endif

.ifexists module-bluetooth-discover.so
load-module module-bluetooth-discover
.endif

# Automatically switch to new devices when they appear
load-module module-switch-on-connect
EOF

# Create system-wide PulseAudio client config to prevent conflicts
cat > /etc/pulse/client.conf << 'EOF'
autospawn = no
EOF

# Create systemd service for PulseAudio
cat > /etc/systemd/system/pulseaudio-spotify-kids.service << EOF
[Unit]
Description=PulseAudio for Spotify Kids
After=bluetooth.target sound.target
Wants=bluetooth.target

[Service]
Type=forking
User=$APP_USER
Group=audio
SupplementaryGroups=bluetooth pulse-access lp
Environment="HOME=/home/$APP_USER"
Environment="XDG_RUNTIME_DIR=/run/user/$APP_USER_UID"
ExecStart=/usr/bin/pulseaudio --start --log-target=syslog
ExecStop=/usr/bin/pulseaudio --kill
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Generate SSL certificate for HTTPS (required for Spotify OAuth)
echo -e "${YELLOW}Generating SSL certificate for HTTPS...${NC}"
SSL_DIR="$APP_DIR/ssl"
mkdir -p $SSL_DIR

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout $SSL_DIR/server.key \
    -out $SSL_DIR/server.crt \
    -subj "/C=US/ST=State/L=City/O=SpotifyKids/CN=$DEVICE_IP" \
    2>/dev/null

# Set proper permissions
chown -R $APP_USER:$APP_USER $SSL_DIR
chmod 600 $SSL_DIR/server.key
chmod 644 $SSL_DIR/server.crt

# Configure nginx
echo -e "${YELLOW}Configuring nginx...${NC}"
cat > /etc/nginx/sites-available/spotify-admin << EOF
# HTTPS server - main configuration
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name $DEVICE_IP;

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
    server_name $DEVICE_IP;
    return 301 https://\$server_name\$request_uri;
}

# Port 8080 - redirect to HTTPS for backward compatibility
server {
    listen 8080;
    listen [::]:8080;
    server_name $DEVICE_IP;
    return 301 https://$DEVICE_IP\$request_uri;
}
EOF

# Remove default nginx site and enable admin panel
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/

# Create systemd services
echo -e "${YELLOW}Creating systemd services...${NC}"

# Spotify Player Service
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
Environment="PULSE_RUNTIME_PATH=/run/user/$APP_USER_UID"
Environment="XDG_RUNTIME_DIR=/run/user/$APP_USER_UID"
Environment="PULSE_SERVER=/run/user/$APP_USER_UID/pulse/native"
Environment="HOME=/home/$APP_USER"
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

# Admin Panel Service
cat > /etc/systemd/system/spotify-admin.service << EOF
[Unit]
Description=Spotify Kids Admin Panel
After=network.target spotify-player.service pulseaudio-spotify-kids.service
Wants=spotify-player.service pulseaudio-spotify-kids.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR/web
Environment="SPOTIFY_CONFIG_DIR=$CONFIG_DIR"
Environment="PULSE_RUNTIME_PATH=/run/user/$APP_USER_UID"
Environment="XDG_RUNTIME_DIR=/run/user/$APP_USER_UID"
Environment="PULSE_SERVER=/run/user/$APP_USER_UID/pulse/native"
ExecStartPre=$APP_DIR/web/venv/bin/pip install -q -r requirements.txt 2>/dev/null || true
ExecStart=$APP_DIR/web/venv/bin/python app.py
Restart=always
StandardOutput=journal
StandardError=journal
SyslogIdentifier=spotify-admin

[Install]
WantedBy=multi-user.target
EOF

# Kiosk Service
cat > /etc/systemd/system/spotify-kiosk.service << EOF
[Unit]
Description=Spotify Kids Kiosk Mode
After=graphical.target spotify-player.service
Wants=graphical.target
Requires=spotify-player.service

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
Environment="HOME=/home/$APP_USER"
Environment="DISPLAY=:0"
Environment="PULSE_RUNTIME_PATH=/run/user/$APP_USER_UID"
Environment="XDG_RUNTIME_DIR=/run/user/$APP_USER_UID"
Environment="PULSE_SERVER=/run/user/$APP_USER_UID/pulse/native"
ExecStartPre=/bin/sleep 10
ExecStart=$APP_DIR/kiosk_launcher.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=spotify-kiosk

[Install]
WantedBy=graphical.target
EOF

# Set permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R $APP_USER:$APP_USER $APP_DIR
chown -R $APP_USER:spotify-config $CONFIG_DIR
chmod -R 775 $CONFIG_DIR
chmod -R 755 $APP_DIR
chown -R $APP_USER:$APP_USER /var/log/spotify-kids
chmod 755 /var/log/spotify-kids
chown -R $APP_USER:$APP_USER /home/$APP_USER/.config
chmod 755 /home/$APP_USER/.config/pulse

# Enable and start services
echo -e "${YELLOW}Enabling services...${NC}"
systemctl daemon-reload
systemctl enable pulseaudio-spotify-kids.service
systemctl enable spotify-player.service
systemctl enable spotify-admin.service
systemctl enable nginx

echo -e "${YELLOW}Starting services...${NC}"
systemctl restart bluetooth
systemctl start pulseaudio-spotify-kids.service
systemctl start spotify-player.service
systemctl start spotify-admin.service
systemctl restart nginx

# Wait for services to start
sleep 5

# Check service status
echo -e "${YELLOW}Checking service status...${NC}"
for service in pulseaudio-spotify-kids spotify-player spotify-admin nginx; do
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓ $service is running${NC}"
    else
        echo -e "${RED}✗ $service failed to start${NC}"
        systemctl status $service --no-pager | head -10
    fi
done

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
rm -f /etc/sudoers.d/spotify-*
rm -f /etc/sudoers.d/90-spotify-pkgmgr
rm -f /etc/dbus-1/system.d/spotify-bluetooth.conf
rm -rf $APP_DIR
userdel -r $APP_USER 2>/dev/null
userdel spotify-admin 2>/dev/null
groupdel spotify-pkgmgr 2>/dev/null
groupdel spotify-config 2>/dev/null
# Unmask PipeWire and bluealsa if they were masked
systemctl unmask pipewire pipewire-pulse wireplumber 2>/dev/null
systemctl unmask bluealsa 2>/dev/null
# Remove Bluetooth configuration files
rm -f /etc/systemd/system/bluetooth.service.d/override.conf
rm -f /etc/bluetooth/audio.conf
# Remove PulseAudio system config
rm -f /etc/pulse/client.conf
rm -f /usr/local/bin/spotify-kids-uninstall
echo "Uninstall complete"
EOF
chmod +x /usr/local/bin/spotify-kids-uninstall

# Final output
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
echo -e "${YELLOW}1. Go to: https://developer.spotify.com/dashboard${NC}"
echo -e "${YELLOW}2. Create a new app (or use existing)${NC}"
echo -e "${YELLOW}3. Add this Redirect URI:${NC}"
echo -e "   ${GREEN}${CALLBACK_URL}${NC}"
echo -e "${YELLOW}4. Save your Client ID and Client Secret${NC}"
echo -e "${YELLOW}5. Enter them in the admin panel${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Optional: For kiosk mode (auto-start player on boot):${NC}"
echo -e "Enable with: ${GREEN}sudo systemctl enable spotify-kiosk.service${NC}"
echo ""
echo -e "After restart, the Spotify player will start automatically."
echo ""
echo -e "To uninstall, run: ${YELLOW}sudo spotify-kids-uninstall${NC}"
echo ""
echo -e "Your browser will show a security warning (self-signed certificate)"
echo -e "This is normal - click 'Advanced' and 'Proceed' to continue"