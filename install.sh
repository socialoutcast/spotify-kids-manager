#!/bin/bash

# Spotify Kids Terminal Manager - Installer
# Native Python Spotify player with web admin panel

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/spotify-terminal"
WEB_PORT=8080
ADMIN_PORT=5001
SPOTIFY_USER="spotify-kids"
ADMIN_USER="admin"
ADMIN_PASS="changeme"
SERVICE_NAME="spotify-terminal-admin"
PLAYER_SERVICE="spotify-native-player"
GITHUB_REPO="https://github.com/socialoutcast/spotify-kids-manager"
BRANCH="main"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect system information
detect_system() {
    log_info "Detecting system information..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS information"
        exit 1
    fi
    
    ARCH=$(uname -m)
    
    log_info "Detected: $OS $VERSION ($ARCH)"
    
    # Check if running on Raspberry Pi
    if [[ -f /proc/device-tree/model ]]; then
        PI_MODEL=$(cat /proc/device-tree/model | tr -d '\0')
        log_info "Raspberry Pi detected: $PI_MODEL"
    else
        log_warning "Not running on Raspberry Pi - some features may not work"
    fi
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    apt-get update
    
    # Core dependencies
    apt-get install -y \
        python3 \
        python3-pip \
        python3-venv \
        python3-tk \
        python3-pil \
        git \
        curl \
        wget \
        sudo \
        bluez \
        bluez-tools \
        pulseaudio-module-bluetooth \
        alsa-utils \
        screen \
        tmux \
        nginx \
        cargo \
        build-essential \
        libasound2-dev \
        libssl-dev \
        libdbus-1-dev \
        pkg-config \
        xinput-calibrator \
        libinput-tools \
        xinit \
        xserver-xorg \
        xserver-xorg-input-libinput \
        unclutter \
        xinput
    
    # Additional packages for native player
    apt-get install -y \
        python3-tk \
        python3-pil \
        python3-spotipy \
        2>/dev/null || true
    
    # Python packages for admin panel and native player
    pip3 install --break-system-packages \
        flask \
        flask-cors \
        flask-socketio \
        werkzeug \
        python-dotenv \
        dbus-python \
        pulsectl \
        spotipy \
        pillow \
        requests
    
    log_success "Dependencies installed"
}

# Create user
create_user() {
    log_info "Creating Spotify user..."
    
    if id "$SPOTIFY_USER" &>/dev/null; then
        log_info "User $SPOTIFY_USER already exists"
    else
        useradd -m -s /bin/bash -G audio,video,bluetooth,input "$SPOTIFY_USER"
        log_success "User $SPOTIFY_USER created"
    fi
    
    # Set up user directories
    su - "$SPOTIFY_USER" -c "mkdir -p ~/.config ~/.cache ~/.spotify-terminal"
}

# Install Spotify backend (raspotify or spotifyd)
install_spotify_backend() {
    log_info "Installing Spotify backend..."
    
    # Check if on Raspberry Pi
    if [[ -f /etc/os-release ]] && grep -q "Raspbian\|Raspberry Pi" /etc/os-release; then
        # Install raspotify
        log_info "Installing Raspotify (Spotify Connect for Raspberry Pi)..."
        curl -sSL https://dtcooper.github.io/raspotify/key.asc | apt-key add - 2>/dev/null
        echo 'deb https://dtcooper.github.io/raspotify raspotify main' | tee /etc/apt/sources.list.d/raspotify.list
        apt-get update
        apt-get install -y raspotify || log_warning "Failed to install raspotify"
    else
        # Install spotifyd
        log_info "Installing spotifyd..."
        ARCH=$(uname -m)
        case "$ARCH" in
            aarch64|arm64)
                SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-armhf-slim.tar.gz"
                ;;
            armv7l|armhf)
                SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-armhf-slim.tar.gz"
                ;;
            x86_64)
                SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-slim.tar.gz"
                ;;
            *)
                log_warning "Unsupported architecture for spotifyd: $ARCH"
                return 1
                ;;
        esac
        
        wget --no-check-certificate -O /tmp/spotifyd.tar.gz "$SPOTIFYD_URL" && \
        tar -xzf /tmp/spotifyd.tar.gz -C /usr/local/bin/ && \
        chmod +x /usr/local/bin/spotifyd && \
        rm /tmp/spotifyd.tar.gz || log_warning "Failed to install spotifyd"
    fi
}

# Create installation directories
create_directories() {
    log_info "Creating installation directories..."
    
    mkdir -p "$INSTALL_DIR"/{scripts,config,data,web}
    chown -R "$SPOTIFY_USER:$SPOTIFY_USER" "$INSTALL_DIR"
    
    log_success "Directories created"
}

# Install application files
install_application() {
    log_info "Installing application files..."
    
    # Download or copy native player
    if [[ -f "spotify_player.py" ]]; then
        log_info "Copying native player from local directory..."
        cp spotify_player.py "$INSTALL_DIR/"
    else
        log_info "Downloading native player from GitHub..."
        wget -q -O "$INSTALL_DIR/spotify_player.py" \
            "https://raw.githubusercontent.com/$GITHUB_REPO/$BRANCH/spotify_player.py" || {
            log_error "Failed to download spotify_player.py"
            exit 1
        }
    fi
    
    # Download or copy admin panel
    if [[ -f "web/app.py" ]]; then
        log_info "Copying admin panel from local directory..."
        cp web/app.py "$INSTALL_DIR/web/"
    else
        log_info "Downloading admin panel from GitHub..."
        wget -q -O "$INSTALL_DIR/web/app.py" \
            "https://raw.githubusercontent.com/$GITHUB_REPO/$BRANCH/web/app.py" || {
            log_error "Failed to download admin panel"
            exit 1
        }
    fi
    
    # Set permissions
    chmod +x "$INSTALL_DIR/spotify_player.py"
    chmod +x "$INSTALL_DIR/web/app.py"
    chown -R "$SPOTIFY_USER:$SPOTIFY_USER" "$INSTALL_DIR"
    
    log_success "Application files installed"
}

# Create startup scripts
create_startup_scripts() {
    log_info "Creating startup scripts..."
    
    # Native player startup script
    cat > "$INSTALL_DIR/scripts/start-native-player.sh" <<'EOF'
#!/bin/bash
#
# Spotify Kids Native Player Launcher
#

export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

LOG_FILE="/opt/spotify-terminal/data/player.log"

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || true
chmod 666 "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting Spotify Kids Native Player..."

# Kill any existing instances
pkill -f spotify_player.py 2>/dev/null
sleep 2

# Start X server if not running
if ! xset q &>/dev/null; then
    log "Starting X server..."
    xinit -- :0 -nocursor &
    sleep 5
fi

# Start the native player
if [ -f /opt/spotify-terminal/spotify_player.py ]; then
    log "Launching native player..."
    python3 /opt/spotify-terminal/spotify_player.py >> "$LOG_FILE" 2>&1
else
    log "ERROR: spotify_player.py not found!"
    exit 1
fi
EOF
    
    # Complete system startup script
    cat > "$INSTALL_DIR/scripts/start-complete-system.sh" <<'EOF'
#!/bin/bash
#
# Start both admin panel and native player
#

# Start admin panel
echo "Starting admin panel on port 5001 (proxied through nginx on 8080)..."
python3 /opt/spotify-terminal/web/app.py &

# Wait a moment
sleep 3

# Start native player
echo "Starting native Spotify player..."
exec /opt/spotify-terminal/scripts/start-native-player.sh
EOF
    
    # Set permissions
    chmod +x "$INSTALL_DIR/scripts/start-native-player.sh"
    chmod +x "$INSTALL_DIR/scripts/start-complete-system.sh"
    
    log_success "Startup scripts created"
}

# Create systemd services
create_systemd_services() {
    log_info "Creating systemd services..."
    
    # Admin panel service
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Spotify Kids Manager Admin Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/web
ExecStart=/usr/bin/python3 $INSTALL_DIR/web/app.py
Restart=always
RestartSec=10
Environment="PORT=$ADMIN_PORT"

[Install]
WantedBy=multi-user.target
EOF
    
    # Native player service
    cat > "/etc/systemd/system/$PLAYER_SERVICE.service" <<EOF
[Unit]
Description=Spotify Kids Native Player
After=network.target graphical.target

[Service]
Type=simple
User=$SPOTIFY_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/scripts/start-native-player.sh
Restart=always
RestartSec=10
Environment="DISPLAY=:0"
Environment="HOME=/home/$SPOTIFY_USER"

[Install]
WantedBy=graphical.target
EOF
    
    # Reload systemd
    systemctl daemon-reload
    
    log_success "Systemd services created"
}

# Configure auto-login
configure_autologin() {
    log_info "Configuring auto-login for $SPOTIFY_USER..."
    
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SPOTIFY_USER --noclear %I \$TERM
EOF
    
    systemctl daemon-reload
    systemctl restart getty@tty1.service
    
    log_success "Auto-login configured"
}

# Configure user profile
configure_user_profile() {
    log_info "Configuring user profile..."
    
    # Create .bash_profile for auto-start
    cat > "/home/$SPOTIFY_USER/.bash_profile" <<'EOF'
#!/bin/bash

# Auto-start Spotify Kids Manager on login
if [[ "$(tty)" == "/dev/tty1" ]]; then
    echo "Starting Spotify Kids Manager..."
    
    # Start admin panel if not running
    if ! pgrep -f "app.py" > /dev/null; then
        python3 /opt/spotify-terminal/web/app.py &
        sleep 3
    fi
    
    # Start native player
    exec /opt/spotify-terminal/scripts/start-native-player.sh
fi
EOF
    
    chown "$SPOTIFY_USER:$SPOTIFY_USER" "/home/$SPOTIFY_USER/.bash_profile"
    chmod +x "/home/$SPOTIFY_USER/.bash_profile"
    
    log_success "User profile configured"
}

# Create initial configuration
create_initial_config() {
    log_info "Creating initial configuration..."
    
    # Admin configuration
    cat > "$INSTALL_DIR/config/admin.json" <<EOF
{
    "admin_user": "$ADMIN_USER",
    "admin_pass": "$(python3 -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('$ADMIN_PASS'))")",
    "spotify_enabled": true,
    "device_locked": false,
    "bluetooth_devices": [],
    "setup_complete": false
}
EOF
    
    # Create empty Spotify config
    cat > "$INSTALL_DIR/config/spotify.json" <<EOF
{
    "configured": false
}
EOF
    
    chown -R "$SPOTIFY_USER:$SPOTIFY_USER" "$INSTALL_DIR/config"
    chmod 600 "$INSTALL_DIR/config/admin.json"
    
    log_success "Initial configuration created"
}

# Configure nginx
configure_nginx() {
    log_info "Configuring nginx proxy..."
    
    # Create nginx configuration
    cat > "/etc/nginx/sites-available/spotify-admin" <<EOF
server {
    listen $WEB_PORT;
    server_name localhost;
    
    location / {
        proxy_pass http://127.0.0.1:$ADMIN_PORT;
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
    
    # Enable the site
    ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/
    
    # Remove default site if it exists
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    nginx -t && systemctl reload nginx
    
    log_success "Nginx configured"
}

# Enable services
enable_services() {
    log_info "Enabling services..."
    
    systemctl enable "$SERVICE_NAME"
    systemctl enable "$PLAYER_SERVICE"
    
    log_success "Services enabled"
}

# Start services
start_services() {
    log_info "Starting services..."
    
    systemctl start "$SERVICE_NAME"
    
    # Only start player if X is available
    if [[ -n "$DISPLAY" ]] || systemctl is-active --quiet graphical.target; then
        systemctl start "$PLAYER_SERVICE"
    else
        log_warning "Graphical environment not available, player service not started"
        log_info "Player will start automatically after reboot"
    fi
    
    log_success "Services started"
}

# Main installation function
main() {
    log_info "=== Spotify Kids Manager Installation ==="
    
    check_root
    detect_system
    install_dependencies
    install_spotify_backend
    create_user
    create_directories
    install_application
    create_startup_scripts
    create_systemd_services
    configure_nginx
    configure_autologin
    configure_user_profile
    create_initial_config
    enable_services
    start_services
    
    log_success "=== Installation Complete ==="
    echo ""
    log_info "Admin Panel: http://localhost:$WEB_PORT"
    log_info "Default credentials: admin / changeme"
    echo ""
    log_info "The native Spotify player will start automatically on boot"
    log_info "Configure Spotify API credentials through the admin panel"
    echo ""
    log_warning "Please reboot to ensure all services start correctly"
    echo ""
    read -p "Reboot now? (y/n): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    fi
}

# Run main function
main "$@"