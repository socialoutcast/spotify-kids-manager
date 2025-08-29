#!/bin/bash

# Spotify Kids Terminal Manager - Installer
# Raspberry Pi terminal-based Spotify client with web admin panel

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
SPOTIFY_USER="spotify-kids"
ADMIN_USER="admin"
ADMIN_PASS="changeme"
SERVICE_NAME="spotify-terminal-admin"
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

# Check for existing installation
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]] || id "$SPOTIFY_USER" &>/dev/null || systemctl is-active --quiet "$SERVICE_NAME"; then
        log_warning "Existing installation detected"
        read -p "Remove existing installation and continue? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing installation..."
            uninstall_all
        else
            log_info "Installation cancelled"
            exit 0
        fi
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
        git \
        curl \
        wget \
        sudo \
        alsa-utils \
        nginx \
        libasound2-dev \
        libssl-dev \
        pkg-config \
        xinit \
        xserver-xorg \
        xserver-xorg-input-libinput \
        unclutter \
        imagemagick \
        fbi
    
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
        spotipy \
        pillow \
        requests
    
    log_success "Dependencies installed"
    
    # Install ncspot
    install_ncspot
}

# Install ncspot (terminal Spotify client)
install_ncspot() {
    log_info "Installing Spotify client..."
    
    # Check if on Raspberry Pi
    if [[ -f /etc/os-release ]] && grep -q "Raspbian\|Raspberry Pi" /etc/os-release; then
        install_raspotify
    else
        install_spotifyd_alternative
    fi
}

# Install raspotify for Raspberry Pi
install_raspotify() {
    log_info "Installing Raspotify (Spotify Connect for Raspberry Pi)..."
    
    # Install raspotify
    log_info "Adding raspotify repository..."
    curl -sSL https://dtcooper.github.io/raspotify/key.asc | apt-key add - 2>/dev/null
    echo 'deb https://dtcooper.github.io/raspotify raspotify main' | tee /etc/apt/sources.list.d/raspotify.list
    apt-get update
    apt-get install -y raspotify || {
        log_error "Failed to install raspotify"
        return 1
    }
    
    # Configure raspotify
    cat > /etc/default/raspotify <<EOF
# Raspotify Configuration
OPTIONS="--username '' --password ''"
BACKEND="alsa"
DEVICE="default"
VOLUME_CTRL="alsa"
BITRATE="160"
EOF
    
    # Restart raspotify
    systemctl restart raspotify
    
    # Create ncspot wrapper for compatibility
    cat > /usr/local/bin/ncspot <<'EOF'
#!/bin/bash
# Wrapper script for raspotify compatibility

case "$1" in
    --version)
        echo "ncspot 0.13.0 (raspotify wrapper)"
        exit 0
        ;;
    --ipc-socket)
        # Start raspotify if not running
        if ! systemctl is-active --quiet raspotify; then
            systemctl start raspotify 2>/dev/null || true
        fi
        # Just keep running for GUI compatibility
        while true; do
            sleep 60
        done
        ;;
    *)
        echo "Raspotify is running as Spotify Connect"
        echo "Device name: $(hostname)"
        echo "Configure via web admin panel"
        
        # Check if device is locked
        if [ -f /opt/spotify-terminal/data/device.lock ]; then
            trap '' INT
        fi
        
        while true; do
            sleep 1
        done
        ;;
esac
EOF
    chmod +x /usr/local/bin/ncspot
    
    log_success "Raspotify installed successfully"
}

# Alternative: Install spotifyd + basic TUI
install_spotifyd_alternative() {
    log_info "Installing spotifyd..."
    
    # Download spotifyd
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64)
            # For ARM64/aarch64, use the armhf build which works on Pi 4
            SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-armhf-slim.tar.gz"
            ;;
        armv7l|armhf)
            SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-armhf-slim.tar.gz"
            ;;
        x86_64)
            SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-slim.tar.gz"
            ;;
        *)
            log_error "Unsupported architecture for spotifyd: $ARCH"
            return 1
            ;;
    esac
    
    log_info "Downloading spotifyd for $ARCH from $SPOTIFYD_URL..."
    wget --no-check-certificate -O /tmp/spotifyd.tar.gz "$SPOTIFYD_URL" || {
        log_error "Failed to download spotifyd from $SPOTIFYD_URL"
        log_info "Trying alternative: installing librespot via apt"
        
        # Alternative: Use librespot from apt
        apt-get install -y librespot || {
            log_error "Failed to install librespot"
            return 1
        }
        
        # Create wrapper for librespot
        cat > /usr/local/bin/spotifyd <<'EOF'
#!/bin/bash
exec librespot --name "Spotify Kids Player" --backend alsa --bitrate 160 --cache /home/spotify-kids/.cache/librespot "$@"
EOF
        chmod +x /usr/local/bin/spotifyd
        log_success "Using librespot as spotifyd alternative"
        return 0
    }
    tar -xzf /tmp/spotifyd.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/spotifyd
    rm /tmp/spotifyd.tar.gz
    
    # Create systemd service for spotifyd
    cat > /etc/systemd/system/spotifyd.service <<'EOF'
[Unit]
Description=Spotify Daemon
After=network.target sound.target

[Service]
Type=simple
ExecStart=/usr/local/bin/spotifyd --no-daemon
Restart=always
RestartSec=10
User=spotify-kids

[Install]
WantedBy=multi-user.target
EOF
    
    # Create ncspot wrapper that uses spotifyd
    cat > /usr/local/bin/ncspot <<'EOF'
#!/bin/bash
# Wrapper script for spotifyd compatibility

case "$1" in
    --version)
        echo "ncspot 0.13.0 (spotifyd wrapper)"
        exit 0
        ;;
    send)
        # Handle IPC commands - spotifyd doesn't support these directly
        shift
        case "$1" in
            playpause|next|previous|play|pause|stop)
                # These would need MPRIS/DBus integration
                echo "Command: $1"
                ;;
            *)
                echo "Unsupported command: $1"
                ;;
        esac
        ;;
    --ipc-socket)
        # Check which backend is available and start it
        if command -v raspotify > /dev/null || systemctl list-units --all | grep -q raspotify; then
            # Use raspotify
            if ! systemctl is-active --quiet raspotify; then
                systemctl start raspotify 2>/dev/null || true
            fi
        elif [ -x /usr/local/bin/spotifyd ]; then
            # Use spotifyd
            if ! pgrep -x spotifyd > /dev/null; then
                /usr/local/bin/spotifyd &
            fi
        else
            echo "No Spotify backend found" >&2
        fi
        # Keep running for GUI compatibility
        while true; do
            sleep 60
        done
        ;;
    *)
        # Interactive mode - show simple interface
        echo "Spotify Kids Player (Spotifyd)"
        echo "=============================="
        echo ""
        echo "Spotifyd is running in background"
        echo "Use the Spotify app on your phone to control playback"
        echo ""
        echo "Device name: $(hostname)"
        echo ""
        echo "Press Ctrl+C to exit (if device is unlocked)"
        
        # Check if device is locked
        if [ -f /opt/spotify-terminal/data/device.lock ]; then
            # Trap Ctrl+C to prevent exit
            trap '' INT
        fi
        
        while true; do
            sleep 1
        done
        ;;
esac
EOF
    chmod +x /usr/local/bin/ncspot
    
    # Enable and start spotifyd service
    systemctl daemon-reload
    systemctl enable spotifyd
    systemctl start spotifyd || true
    
    log_success "Spotifyd installed with ncspot wrapper"
}

# Create restricted user
create_spotify_user() {
    log_info "Creating restricted user '$SPOTIFY_USER'..."
    
    # Create user without sudo access and with limited shell
    useradd -m -s /bin/bash -G audio,video,bluetooth "$SPOTIFY_USER" || true
    
    # Set up user environment
    mkdir -p "/home/$SPOTIFY_USER/.config"
    mkdir -p "/home/$SPOTIFY_USER/.cache"
    mkdir -p "/home/$SPOTIFY_USER/.cache/ncspot"
    mkdir -p "/home/$SPOTIFY_USER/.cache/spotifyd"
    
    # Configure auto-login on tty1
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SPOTIFY_USER --noclear %I \$TERM
EOF
    
    systemctl daemon-reload
    
    log_success "User '$SPOTIFY_USER' created"
}

# Setup terminal Spotify client
setup_spotify_client() {
    log_info "Setting up terminal Spotify client..."
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/web"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/data"
    
    # Create log files with proper permissions
    touch "$INSTALL_DIR/data/login.log"
    touch "$INSTALL_DIR/data/client.log"
    touch "$INSTALL_DIR/data/spotify-auth.log"
    touch "$INSTALL_DIR/data/device.lock" && rm "$INSTALL_DIR/data/device.lock"  # Create and remove to ensure directory is writable
    
    # Set permissions so all users can write logs
    chmod 777 "$INSTALL_DIR/data"
    chmod 666 "$INSTALL_DIR/data/login.log" 2>/dev/null || true
    chmod 666 "$INSTALL_DIR/data/client.log" 2>/dev/null || true
    chmod 666 "$INSTALL_DIR/data/spotify-auth.log" 2>/dev/null || true
    
    # Create spotifyd configuration
    mkdir -p "/home/$SPOTIFY_USER/.config/spotifyd"
    cat > "/home/$SPOTIFY_USER/.config/spotifyd/spotifyd.conf" <<EOF
[global]
# Spotify credentials (will be set via web UI)
username = ""
password = ""

# Audio settings
backend = "alsa"
device = "default"
volume_controller = "alsa"
volume_normalisation = true
normalisation_pregain = -10
bitrate = 160

# Device settings
device_name = "Spotify Kids Player"
device_type = "speaker"

# Cache
cache_path = "/home/$SPOTIFY_USER/.cache/spotifyd"
max_cache_size = 1000000000
EOF
    chmod 600 "/home/$SPOTIFY_USER/.config/spotifyd/spotifyd.conf"
    
    # Also create ncspot config for compatibility
    mkdir -p "/home/$SPOTIFY_USER/.config/ncspot"
    cat > "/home/$SPOTIFY_USER/.config/ncspot/config.toml" <<EOF
[theme]
background = "black"
primary = "green"
secondary = "light white"
title = "white"
playing = "green"
playing_selected = "light green"
playing_bg = "black"
highlight = "light white"
highlight_bg = "#484848"
error = "light red"
error_bg = "red"
statusbar = "black"
statusbar_progress = "green"
statusbar_bg = "green"
cmdline = "light white"
cmdline_bg = "black"
search_match = "light red"

[keybindings]
"q" = "quit"  # Will be disabled when locked

[backend]
backend = "pulseaudio"
EOF
    
    # Create startup script for spotify client
    cat > "$INSTALL_DIR/scripts/spotify-client.sh" <<'EOF'
#!/bin/bash

# Spotify Terminal Client Wrapper  
# This script manages the ncspot client with parental controls

LOCK_FILE="/opt/spotify-terminal/data/device.lock"
CONFIG_FILE="/opt/spotify-terminal/config/client.conf"
LOG_FILE="/opt/spotify-terminal/data/client.log"
SPOTIFY_AUTH_LOG="/opt/spotify-terminal/data/spotify-auth.log"

# Ensure log files are writable
touch "$LOG_FILE" 2>/dev/null || true
chmod 666 "$LOG_FILE" 2>/dev/null || true
touch "$SPOTIFY_AUTH_LOG" 2>/dev/null || true
chmod 666 "$SPOTIFY_AUTH_LOG" 2>/dev/null || true

# Log function for Spotify auth
log_spotify() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$SPOTIFY_AUTH_LOG"
}

# Source configuration
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Check if device is locked
is_locked() {
    [[ -f "$LOCK_FILE" ]]
}

# Start ncspot with appropriate settings  
start_client() {
    # Set terminal settings for better display
    stty sane
    export TERM=linux
    
    log_spotify "Starting Spotify client for user: $USER (HOME=$HOME)"
    
    # Clear screen and reset cursor
    clear
    tput cnorm 2>/dev/null || true  # Show cursor if hidden
    
    # Display header with colors if available
    if command -v tput > /dev/null 2>&1; then
        tput bold
        echo "================================================"
        echo "         Spotify Kids Music Player             "
        echo "================================================"
        tput sgr0
    else
        echo "================================================"
        echo "         Spotify Kids Music Player             "
        echo "================================================"
    fi
    echo ""
    
    # Check if Spotify is disabled
    if [[ "$SPOTIFY_DISABLED" == "true" ]]; then
        log_spotify "Spotify is disabled by administrator"
        echo "Spotify is currently disabled by administrator"
        echo "Please contact your parent to enable it"
        # Keep terminal alive but don't consume CPU
        while true; do
            sleep 3600
        done
    fi
    
    # Check which backend is available and configured
    log_spotify "Checking available Spotify backends..."
    
    # Check raspotify
    if [ -f /etc/default/raspotify ] && systemctl list-units --all | grep -q raspotify; then
        log_spotify "Found raspotify backend"
        # Check if configured
        if grep -q "OPTIONS=" /etc/default/raspotify 2>/dev/null; then
            USERNAME=$(grep "OPTIONS=" /etc/default/raspotify | sed -n "s/.*--username ['\"]\([^'\"]*\)['\"]/\1/p")
            if [ -n "$USERNAME" ]; then
                log_spotify "Raspotify configured for user: $USERNAME"
                # Start raspotify if not running
                if ! systemctl is-active --quiet raspotify; then
                    log_spotify "Starting raspotify service..."
                    sudo systemctl start raspotify 2>&1 | tee -a "$SPOTIFY_AUTH_LOG"
                    sleep 2
                    if systemctl is-active --quiet raspotify; then
                        log_spotify "Raspotify service started successfully"
                    else
                        log_spotify "ERROR: Failed to start raspotify service"
                        journalctl -u raspotify -n 20 --no-pager >> "$SPOTIFY_AUTH_LOG" 2>&1
                    fi
                else
                    log_spotify "Raspotify service already running"
                fi
            else
                log_spotify "WARNING: Raspotify not configured (no username found)"
            fi
        else
            log_spotify "WARNING: Raspotify config exists but no OPTIONS found"
        fi
    fi
    
    # Check spotifyd
    if [ -x /usr/local/bin/spotifyd ]; then
        log_spotify "Found spotifyd backend at /usr/local/bin/spotifyd"
        SPOTIFYD_CONFIG="$HOME/.config/spotifyd/spotifyd.conf"
        if [ -f "$SPOTIFYD_CONFIG" ]; then
            USERNAME=$(grep "^username" "$SPOTIFYD_CONFIG" 2>/dev/null | cut -d= -f2 | tr -d ' ')
            if [ -n "$USERNAME" ]; then
                log_spotify "Spotifyd configured for user: $USERNAME"
                # Start spotifyd if not running
                if ! pgrep -x spotifyd > /dev/null; then
                    log_spotify "Starting spotifyd daemon..."
                    /usr/local/bin/spotifyd 2>&1 | head -20 >> "$SPOTIFY_AUTH_LOG" &
                    SPOTIFYD_PID=$!
                    sleep 3
                    if kill -0 $SPOTIFYD_PID 2>/dev/null; then
                        log_spotify "Spotifyd started with PID: $SPOTIFYD_PID"
                    else
                        log_spotify "ERROR: Spotifyd failed to start"
                    fi
                else
                    log_spotify "Spotifyd already running"
                fi
            else
                log_spotify "WARNING: Spotifyd config exists but no username found"
            fi
        else
            log_spotify "WARNING: Spotifyd binary exists but no config at $SPOTIFYD_CONFIG"
        fi
    fi
    
    # Check ncspot config
    NCSPOT_CONFIG="$HOME/.config/ncspot/config.toml"
    if [ -f "$NCSPOT_CONFIG" ]; then
        USERNAME=$(grep "^username" "$NCSPOT_CONFIG" 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/')
        if [ -n "$USERNAME" ]; then
            log_spotify "ncspot configured for user: $USERNAME"
        else
            log_spotify "WARNING: ncspot config exists but no username found"
        fi
    else
        log_spotify "WARNING: No ncspot config found at $NCSPOT_CONFIG"
    fi
    
    # Start the appropriate client
    if command -v ncspot &> /dev/null; then
        log_spotify "Starting ncspot client..."
        # Use ncspot if available
        if is_locked; then
            log_spotify "Device is locked - starting ncspot in restricted mode"
            # Locked mode - disable quit key
            ncspot --config <(cat ~/.config/ncspot/config.toml | sed '/^"q"/d') 2>&1 | while IFS= read -r line; do
                echo "$line"
                # Log authentication errors
                if echo "$line" | grep -iE "(auth|login|error|fail|401|403|invalid|credential|password)" > /dev/null; then
                    log_spotify "ncspot: $line"
                fi
            done
        else
            log_spotify "Device is unlocked - starting ncspot in normal mode"
            # Unlocked mode - normal operation
            ncspot 2>&1 | while IFS= read -r line; do
                echo "$line"
                # Log authentication errors
                if echo "$line" | grep -iE "(auth|login|error|fail|401|403|invalid|credential|password)" > /dev/null; then
                    log_spotify "ncspot: $line"
                fi
            done
        fi
    elif command -v spotifyd &> /dev/null; then
        log_spotify "ncspot not found, checking for spotifyd..."
        # Use spotifyd with simple UI
        log_spotify "Starting spotifyd daemon..."
        spotifyd --no-daemon --backend alsa 2>&1 | tee -a "$SPOTIFY_AUTH_LOG" &
        if command -v spotify-tui-simple &> /dev/null; then
            log_spotify "Starting spotify-tui-simple..."
            exec spotify-tui-simple
        else
            log_spotify "ERROR: spotify-tui-simple not found"
            echo "Spotifyd is running but no UI available"
            sleep 10
        fi
    else
        log_spotify "ERROR: No Spotify client installed!"
        echo "No Spotify client installed!"
        echo "Please run the installer again"
        sleep 10
        exit 1
    fi
}

# Trap signals to prevent exit when locked
if is_locked; then
    trap '' INT TERM QUIT TSTP
fi

# Main loop
while true; do
    start_client
    
    # If we get here and device is locked, restart
    if is_locked; then
        echo "Restarting player..."
        sleep 2
    else
        # Device unlocked, allow exit
        break
    fi
done
EOF
    
    chmod +x "$INSTALL_DIR/scripts/spotify-client.sh"
    
    # Create auto-start script for native player ONLY (admin panel runs as service)
    cat > "/home/$SPOTIFY_USER/.bash_profile" <<'EOF'
#!/bin/bash
# Auto-start native Spotify player on login (NOT the admin panel)
if [[ "$(tty)" == "/dev/tty1" ]]; then
    # Kill any leftover fbi from boot splash
    killall fbi 2>/dev/null
    
    # Start X server with a simple xinitrc that runs the player
    echo "#!/bin/sh" > /tmp/xinitrc
    echo "exec python3 /opt/spotify-terminal/spotify_player.py" >> /tmp/xinitrc
    chmod +x /tmp/xinitrc
    
    export XINITRC=/tmp/xinitrc
    export HOME=/home/spotify-kids
    export USER=spotify-kids
    
    # Start X with the player
    exec startx -- :0 -nocursor
fi
EOF
    
    # Also create .profile for systems that use it instead of .bash_profile
    cp "/home/$SPOTIFY_USER/.bash_profile" "/home/$SPOTIFY_USER/.profile"
    
    # Create .bashrc that sources .bash_profile
    cat > "/home/$SPOTIFY_USER/.bashrc" <<EOF
# Source bash_profile if on tty1
if [[ -f ~/.bash_profile ]]; then
    source ~/.bash_profile
fi
EOF
    
    # Create touchscreen startup script
    # Copy the proper start-touchscreen.sh script
    if [ -f "$SCRIPT_DIR/scripts/start-touchscreen.sh" ]; then
        cp "$SCRIPT_DIR/scripts/start-touchscreen.sh" "$INSTALL_DIR/scripts/start-touchscreen.sh"
    else
        cat > "$INSTALL_DIR/scripts/start-touchscreen.sh" <<'EOF'
#!/bin/bash
#
# Spotify Kids Touchscreen Startup Script
# Launches the web player interface in kiosk mode
#

LOG_FILE="/opt/spotify-terminal/data/login.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "Starting touchscreen interface..."

# Set environment
export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Let systemd handle Plymouth quit naturally - removing manual quit
# plymouth quit 2>/dev/null || true

# Wait for X to be ready
sleep 2

# Launch the web player
if [ -f /opt/spotify-terminal/scripts/start-web-player.sh ]; then
    log_message "Launching web player..."
    exec /opt/spotify-terminal/scripts/start-web-player.sh
else
    log_message "Web player script not found, launching directly..."
    
    # Start the web player directly
    cd /opt/spotify-terminal
    
    # Kill any existing instances
    pkill -f spotify_player.py 2>/dev/null
    sleep 1
    
    # Start the native Spotify player
    if [ -f /opt/spotify-terminal/spotify_player.py ]; then
        DISPLAY=:0 python3 /opt/spotify-terminal/spotify_player.py >> "$LOG_FILE" 2>&1 &
        PLAYER_PID=$!
        log_message "Started native Spotify player with PID: $PLAYER_PID"
    elif [ -f /home/bkrause/Projects/spotify-kids-manager/spotify_player.py ]; then
        DISPLAY=:0 python3 /home/bkrause/Projects/spotify-kids-manager/spotify_player.py >> "$LOG_FILE" 2>&1 &
        PLAYER_PID=$!
        log_message "Started native Spotify player from project directory with PID: $PLAYER_PID"
    else
        log_message "ERROR: spotify_player.py not found!"
        
        # Fallback: start admin panel
        if [ -f /opt/spotify-terminal/web/app.py ]; then
            python3 /opt/spotify-terminal/web/app.py >> "$LOG_FILE" 2>&1 &
            log_message "Started admin panel as fallback"
        fi
    fi
    
    # Wait for server to start
    sleep 5
    
    # Native player is running, just wait
    wait $PLAYER_PID
fi
EOF
    fi
    
    chmod +x "$INSTALL_DIR/scripts/start-touchscreen.sh"
    
    # Create web player startup script
    cat > "$INSTALL_DIR/scripts/start-web-player.sh" <<'EOF'
#!/bin/bash
#
# Spotify Kids Web Player Launcher
# Starts the web server and opens browser in kiosk mode
#

export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Let systemd handle Plymouth quit naturally - removing manual quit
# plymouth quit 2>/dev/null || true

LOG_FILE="/opt/spotify-terminal/data/web-player.log"

# Ensure log file exists and is writable
touch "$LOG_FILE" 2>/dev/null || true
chmod 666 "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting Spotify Kids Web Player..."

# Check for rapid restarts (crash loop protection)
CRASH_FILE="/tmp/spotify-player-crashes"
CURRENT_TIME=$(date +%s)

if [ -f "$CRASH_FILE" ]; then
    LAST_CRASH=$(cat "$CRASH_FILE")
    TIME_DIFF=$((CURRENT_TIME - LAST_CRASH))
    
    if [ $TIME_DIFF -lt 30 ]; then
        log "ERROR: Detected rapid restart (crash loop). Waiting 30 seconds..."
        echo "Crash loop detected. Waiting 30 seconds before retry..." >&2
        sleep 30
    fi
fi

echo "$CURRENT_TIME" > "$CRASH_FILE"

# Kill any existing instances
pkill -f spotify_player.py 2>/dev/null
sleep 2

# Ensure player file exists
if [ ! -f /opt/spotify-terminal/spotify_player.py ]; then
    log "Player file missing, downloading from GitHub..."
    
    # Download the native player from GitHub
    for file in spotify_player.py; do
        wget -q -O "$file" "https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/$file" || {
            log "ERROR: Failed to download $file"
        }
    done
    
    # Ensure permissions
    chown -R spotify-kids:spotify-kids /opt/spotify-terminal/web
fi

# Start the Spotify player server
log "Starting native Spotify player..."
cd /opt/spotify-terminal
if [ -f spotify_player.py ]; then
    # Install required Python modules if missing
    python3 -c "import tkinter" 2>/dev/null || apt-get install -y python3-tk
    python3 -c "import spotipy" 2>/dev/null || pip3 install spotipy pillow requests
    
    DISPLAY=:0 python3 spotify_player.py >> "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    log "Spotify player server started with PID: $SERVER_PID"
else
    log "CRITICAL ERROR: Could not start Spotify server!"
    exit 1
fi

# Wait for server to start and verify it's running
sleep 3

# Check if server actually started
if [ ! -z "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    log "Server is running on PID $SERVER_PID"
    
    # Wait for port to be ready
    for i in {1..10}; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8888" | grep -q "200\|302"; then
            log "Server is responding on port 8888"
            break
        fi
        log "Waiting for server to respond... ($i/10)"
        sleep 1
    done
else
    log "ERROR: Server failed to start!"
    # Try to start the admin panel as fallback
    if [ -f /opt/spotify-terminal/web/app.py ]; then
        log "Starting admin panel as fallback..."
        python3 /opt/spotify-terminal/web/app.py >> "$LOG_FILE" 2>&1 &
        SERVER_PID=$!
        sleep 3
    fi
fi

# Check if running with X server (graphical mode)
if [ -n "$DISPLAY" ] && xset q &>/dev/null; then
    log "X server detected, starting browser in kiosk mode..."
    
    # Disable screen blanking
    xset s off
    xset -dpms
    xset s noblank
    
    # Hide cursor
    unclutter -idle 0.1 -root &
    
    # Launch Chromium in kiosk mode
    log "Launching Chromium in kiosk mode..."
    
    # Determine which port to use
    PORT=8888
    if ! curl -s -o /dev/null -w "%{http_code}" "http://localhost:8888" | grep -q "200\|302"; then
        log "WARNING: Port 8888 not responding, trying port 8080"
        PORT=8080
    fi
    
    chromium-browser \
        --kiosk \
        --no-first-run \
        --noerrdialogs \
        --disable-infobars \
        --disable-features=TranslateUI \
        --disable-pinch \
        --overscroll-history-navigation=disabled \
        --disable-dev-tools \
        --check-for-update-interval=31536000 \
        --disable-component-update \
        --autoplay-policy=no-user-gesture-required \
        --window-size=1920,1080 \
        --window-position=0,0 \
        --touch-events=enabled \
        --enable-touch-events \
        --enable-touch-drag-drop \
        --app=http://localhost:$PORT \
        >> "$LOG_FILE" 2>&1 &
    
    BROWSER_PID=$!
    log "Browser launched with PID: $BROWSER_PID on port $PORT"
    
    # Monitor and restart if needed
    while true; do
        if ! kill -0 "$BROWSER_PID" 2>/dev/null; then
            log "Browser crashed, waiting before restart..."
            sleep 10
            
            # Clean restart flag
            rm -f "$CRASH_FILE"
            
            # Restart the script
            exec "$0"
        fi
        sleep 5
    done
else
    log "No X server detected, running in headless mode"
    log "Web interface available at http://$(hostname -I | awk '{print $1}'):8888"
    
    # Just keep the server running
    wait $SERVER_PID
fi
EOF
    
    chmod +x "$INSTALL_DIR/scripts/start-web-player.sh"
    
    # Create Python touch GUI for ncspot
    
    # Install web player files
    log_info "Installing web player files..."
    
    # Download native player from GitHub
    wget -q -O "$INSTALL_DIR/spotify_player.py" \
        "https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/spotify_player.py" || {
        log_warning "Failed to download spotify_player.py"
    }
    
    wget -q -O "$INSTALL_DIR/scripts/start-spotify-player.sh" \
        "https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/scripts/start-spotify-player.sh" || {
        log_warning "Failed to download start-spotify-player.sh"
    }
    
    # Install Python dependencies for native player
    # Python dependencies already installed in main install_dependencies function
    
    # Create systemd service for web player
    cat > "/etc/systemd/system/spotify-web-player.service" <<'EOF'
[Unit]
Description=Spotify Kids Web Player
After=network.target sound.target
Wants=network-online.target

[Service]
Type=simple
User=spotify-kids
Group=audio
Environment="HOME=/home/spotify-kids"
Environment="USER=spotify-kids"
WorkingDirectory=/opt/spotify-terminal/web
ExecStart=/opt/spotify-terminal/scripts/start-spotify-player.sh
Restart=always
RestartSec=5
StandardOutput=append:/opt/spotify-terminal/data/web-player.log
StandardError=append:/opt/spotify-terminal/data/web-player-error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # Make scripts executable if they exist
    [ -f "$INSTALL_DIR/spotify_player.py" ] && chmod +x "$INSTALL_DIR/spotify_player.py"
    [ -f "$INSTALL_DIR/scripts/start-spotify-player.sh" ] && chmod +x "$INSTALL_DIR/scripts/start-spotify-player.sh"
    
    
    # Keep multi-user.target as default (no GUI unless touchscreen detected)
    log_info "Setting system to multi-user mode..."
    systemctl set-default multi-user.target 2>/dev/null || true
    
    # Make all scripts executable
    chmod +x "/home/$SPOTIFY_USER/.bash_profile"
    chmod +x "/home/$SPOTIFY_USER/.profile"
    chmod 644 "/home/$SPOTIFY_USER/.bashrc"
    
    # Fix ownership
    chown -R "$SPOTIFY_USER:$SPOTIFY_USER" "/home/$SPOTIFY_USER"
    
    log_success "Spotify client configured"
}
# End of setup_spotify_client

# Setup web admin panel function
setup_web_admin() {
    log_info "Setting up web admin panel..."
    
    # Create Flask application
    cat > "$INSTALL_DIR/web/app.py" <<'EOF'
#!/usr/bin/env python3

from flask import Flask, request, jsonify, render_template_string, session, redirect, url_for
from flask_cors import CORS
from flask_socketio import SocketIO
from werkzeug.security import check_password_hash, generate_password_hash
import os
import json
import subprocess
import dbus
import pulsectl
import threading
from functools import wraps
from datetime import datetime

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration
CONFIG_FILE = "/opt/spotify-terminal/config/admin.json"
LOCK_FILE = "/opt/spotify-terminal/data/device.lock"
CLIENT_CONFIG = "/opt/spotify-terminal/config/client.conf"

# Load or create configuration
def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    else:
        default_config = {
            "admin_user": "admin",
            "admin_pass": generate_password_hash("changeme"),
            "spotify_enabled": True,
            "device_locked": False,
            "bluetooth_devices": [],
            "setup_complete": False
        }
        save_config(default_config)
        return default_config

def save_config(config):
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

# Authentication decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return jsonify({"error": "Authentication required"}), 401
        return f(*args, **kwargs)
    return decorated_function

# HTML Template
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Spotify Kids Manager - Admin Panel</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            background: white;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .header h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
        }
        .status.online { background: #10b981; color: white; }
        .status.offline { background: #ef4444; color: white; }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        .card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .card h2 {
            color: #333;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #f0f0f0;
        }
        .btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            margin: 5px;
            transition: all 0.3s;
        }
        .btn:hover {
            background: #5a67d8;
            transform: translateY(-2px);
        }
        .btn.danger { background: #ef4444; }
        .btn.danger:hover { background: #dc2626; }
        .btn.success { background: #10b981; }
        .btn.success:hover { background: #059669; }
        .form-group {
            margin-bottom: 15px;
        }
        .form-group label {
            display: block;
            margin-bottom: 5px;
            color: #666;
            font-size: 14px;
        }
        .form-group input {
            width: 100%;
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }
        .device-list {
            list-style: none;
            margin-top: 10px;
        }
        .device-item {
            background: #f9f9f9;
            padding: 10px;
            margin-bottom: 10px;
            border-radius: 5px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .device-item span {
            font-size: 12px;
            font-weight: 600;
            padding: 2px 6px;
            border-radius: 3px;
            background: rgba(255,255,255,0.8);
        }
        .toggle {
            position: relative;
            display: inline-block;
            width: 50px;
            height: 24px;
        }
        .toggle input {
            opacity: 0;
            width: 0;
            height: 0;
        }
        .slider {
            position: absolute;
            cursor: pointer;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: #ccc;
            transition: .4s;
            border-radius: 34px;
        }
        .slider:before {
            position: absolute;
            content: "";
            height: 16px;
            width: 16px;
            left: 4px;
            bottom: 4px;
            background-color: white;
            transition: .4s;
            border-radius: 50%;
        }
        input:checked + .slider {
            background-color: #667eea;
        }
        input:checked + .slider:before {
            transform: translateX(26px);
        }
        .alert {
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .alert.success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        .alert.error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎵 Spotify Kids Manager</h1>
            <span class="status online">System Online</span>
        </div>
        
        <div id="alerts"></div>
        
        {% if not logged_in %}
        <div class="card">
            <h2>Admin Login</h2>
            <form id="loginForm">
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" id="username" required>
                </div>
                <div class="form-group">
                    <label>Password</label>
                    <input type="password" id="password" required>
                </div>
                <button type="submit" class="btn">Login</button>
            </form>
        </div>
        {% else %}
        <div class="grid">
            <!-- User Management -->
            <div class="card" style="grid-column: span 2;">
                <h2>User Management</h2>
                <div style="margin-bottom: 20px;">
                    <h3 style="font-size: 16px; margin-bottom: 10px;">Create New User</h3>
                    <div style="display: flex; gap: 10px;">
                        <input type="text" id="newUsername" placeholder="Enter username" style="flex: 1; padding: 8px;">
                        <button class="btn success" onclick="createUser()">Create User</button>
                    </div>
                </div>
                
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
                    <h3 style="font-size: 16px; margin: 0;">Existing Users</h3>
                    <button class="btn" onclick="loadUsers()" title="Refresh user status">↻ Refresh</button>
                </div>
                <div id="usersList">Loading users...</div>
            </div>
            
            <!-- Device Control -->
            <div class="card">
                <h2>Device Control</h2>
                <div class="form-group">
                    <label>Device Lock</label>
                    <label class="toggle">
                        <input type="checkbox" id="deviceLock" {% if device_locked %}checked{% endif %}>
                        <span class="slider"></span>
                    </label>
                    <p style="margin-top: 10px; color: #666; font-size: 12px;">
                        When locked, kids cannot exit the Spotify player
                    </p>
                </div>
                <div class="form-group">
                    <label>Spotify Access</label>
                    <label class="toggle">
                        <input type="checkbox" id="spotifyAccess" {% if spotify_enabled %}checked{% endif %}>
                        <span class="slider"></span>
                    </label>
                    <p style="margin-top: 10px; color: #666; font-size: 12px;">
                        Enable or disable Spotify access completely
                    </p>
                </div>
            </div>
            
            <!-- Bluetooth Devices -->
            <div class="card">
                <h2>Bluetooth Devices</h2>
                <button class="btn" onclick="scanBluetooth()">Scan for Devices</button>
                <div id="bluetoothDevices" class="device-list"></div>
            </div>
            
            <!-- Spotify Configuration -->
            <div class="card" style="grid-column: span 2;">
                <h2>Spotify Configuration</h2>
                <div id="spotifyStatus">
                    <p>Loading...</p>
                </div>
                
                <!-- API Credentials Section -->
                <div style="background: #f5f5f5; padding: 15px; border-radius: 5px; margin-bottom: 20px;">
                    <h3 style="font-size: 16px; margin-bottom: 10px;">Step 1: Spotify API Credentials</h3>
                    <p style="color: #666; font-size: 12px; margin-bottom: 10px;">
                        Get your API credentials from <a href="https://developer.spotify.com/dashboard" target="_blank" style="color: #667eea;">Spotify Developer Dashboard</a>
                    </p>
                    <form id="apiForm">
                        <div class="form-group">
                            <label>Client ID</label>
                            <input type="text" id="clientId" placeholder="Your app's Client ID" style="font-family: monospace;">
                        </div>
                        <div class="form-group">
                            <label>Client Secret</label>
                            <input type="password" id="clientSecret" placeholder="Your app's Client Secret" style="font-family: monospace;">
                        </div>
                        <button type="submit" class="btn">Save API Credentials</button>
                    </form>
                </div>
                
                <!-- Account Login Section -->
                <div style="background: #f5f5f5; padding: 15px; border-radius: 5px;">
                    <h3 style="font-size: 16px; margin-bottom: 10px;">Step 2: Spotify Account Login</h3>
                    <form id="spotifyForm">
                        <div class="form-group">
                            <label>Configure Spotify for User</label>
                            <select id="targetUser" style="width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 5px;">
                                <option value="spotify-kids">spotify-kids (default)</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Spotify Username</label>
                            <input type="text" id="spotifyUsername" placeholder="Your Spotify username (not email)" required>
                            <p style="margin-top: 5px; color: #666; font-size: 12px;">
                                ⚠️ Use your Spotify username, NOT your email address!
                            </p>
                        </div>
                        <div class="form-group">
                            <label>Spotify Password</label>
                            <input type="password" id="spotifyPassword" required>
                            <p style="margin-top: 5px; color: #666; font-size: 12px;">
                                Requires Spotify Premium account
                            </p>
                        </div>
                        <button type="submit" class="btn success">Configure Account</button>
                    </form>
                    
                    <div style="text-align: center; margin: 15px 0;">
                        <span style="color: #999;">OR</span>
                    </div>
                    
                    <button class="btn success" onclick="startOAuth()" style="width: 100%;">
                        🔐 Login with Spotify OAuth
                    </button>
                </div>
            </div>
            
            <!-- Account Settings -->
            <div class="card">
                <h2>Admin Settings</h2>
                <form id="passwordForm">
                    <div class="form-group">
                        <label>New Admin Password</label>
                        <input type="password" id="newPassword" required>
                    </div>
                    <div class="form-group">
                        <label>Confirm Password</label>
                        <input type="password" id="confirmPassword" required>
                    </div>
                    <button type="submit" class="btn">Change Admin Password</button>
                </form>
            </div>
            
            <!-- System Info -->
            <div class="card">
                <h2>System Information</h2>
                <div id="systemInfo">
                    <p>Loading...</p>
                </div>
                <button class="btn danger" onclick="restartService()">Restart Service</button>
                <button class="btn" onclick="viewLogs()">View Service Logs</button>
                <button class="btn" onclick="viewLoginLogs()">View Login Logs</button>
                <button class="btn danger" onclick="rebootSystem()">Reboot System</button>
                <button class="btn danger" onclick="shutdownSystem()">Shutdown</button>
            </div>
        </div>
        
        <div style="margin-top: 20px;">
            <button class="btn danger" onclick="logout()">Logout</button>
            <button class="btn danger" onclick="uninstall()">Uninstall System</button>
        </div>
        {% endif %}
    </div>
    
    <script>
        function showAlert(message, type = 'success') {
            const alertDiv = document.getElementById('alerts');
            alertDiv.innerHTML = `<div class="alert ${type}">${message}</div>`;
            setTimeout(() => alertDiv.innerHTML = '', 5000);
        }
        
        // Login form
        document.getElementById('loginForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const response = await fetch('/api/login', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    username: document.getElementById('username').value,
                    password: document.getElementById('password').value
                })
            });
            if (response.ok) {
                window.location.reload();
            } else {
                showAlert('Invalid credentials', 'error');
            }
        });
        
        // Device lock toggle
        document.getElementById('deviceLock')?.addEventListener('change', async (e) => {
            const response = await fetch('/api/device/lock', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({locked: e.target.checked})
            });
            if (response.ok) {
                showAlert(`Device ${e.target.checked ? 'locked' : 'unlocked'}`);
            }
        });
        
        // Spotify access toggle
        document.getElementById('spotifyAccess')?.addEventListener('change', async (e) => {
            const response = await fetch('/api/spotify/access', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({enabled: e.target.checked})
            });
            if (response.ok) {
                showAlert(`Spotify ${e.target.checked ? 'enabled' : 'disabled'}`);
            }
        });
        
        // Bluetooth scanning
        async function scanBluetooth() {
            showAlert('Scanning for Bluetooth devices...');
            const response = await fetch('/api/bluetooth/scan');
            const devices = await response.json();
            
            const deviceList = document.getElementById('bluetoothDevices');
            deviceList.innerHTML = devices.map(device => `
                <div class="device-item">
                    <span>${device.name || device.address}</span>
                    <button class="btn success" onclick="pairDevice('${device.address}')">
                        ${device.paired ? 'Connect' : 'Pair'}
                    </button>
                </div>
            `).join('');
        }
        
        async function pairDevice(address) {
            const response = await fetch('/api/bluetooth/pair', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({address})
            });
            if (response.ok) {
                showAlert('Device paired successfully');
                scanBluetooth();
            } else {
                showAlert('Failed to pair device', 'error');
            }
        }
        
        // User management functions
        async function loadUsers() {
            const response = await fetch('/api/users');
            const users = await response.json();
            
            const usersList = document.getElementById('usersList');
            const targetSelect = document.getElementById('targetUser');
            
            // Clear and rebuild target user select
            targetSelect.innerHTML = '';
            
            usersList.innerHTML = users.map(user => `
                <div class="device-item">
                    <div>
                        <strong>${user.username}</strong>
                        ${user.auto_login ? '<span style="color: green; margin-left: 10px;">✓ Auto-login</span>' : ''}
                        ${user.is_logged_in ? '<span style="color: #1db954; margin-left: 10px;">● Active</span>' : ''}
                        ${user.spotify_username && user.spotify_username !== '' ? `<span style="color: #1db954; margin-left: 10px;">♪ ${user.spotify_username}</span>` : 
                          (user.spotify_configured ? '<span style="color: orange; margin-left: 10px;">♪ Configured</span>' : '')}
                    </div>
                    <div>
                        ${!user.auto_login ? `<button class="btn" onclick="setAutoLogin('${user.username}')">Set Auto-login</button>` : ''}
                        ${user.username !== 'spotify-kids' ? `<button class="btn danger" onclick="deleteUser('${user.username}')">Delete</button>` : ''}
                    </div>
                </div>
            `).join('');
            
            // Populate target user select
            users.forEach(user => {
                const option = document.createElement('option');
                option.value = user.username;
                option.textContent = user.username + (user.spotify_configured ? ' (configured)' : '');
                targetSelect.appendChild(option);
            });
        }
        
        async function createUser() {
            const username = document.getElementById('newUsername').value.trim();
            if (!username) {
                showAlert('Please enter a username', 'error');
                return;
            }
            
            const response = await fetch('/api/users', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({username})
            });
            
            if (response.ok) {
                showAlert(`User ${username} created successfully`);
                document.getElementById('newUsername').value = '';
                loadUsers();
            } else {
                const error = await response.json();
                showAlert(error.error || 'Failed to create user', 'error');
            }
        }
        
        async function deleteUser(username) {
            if (!confirm(`Delete user ${username}? This will remove all their data.`)) return;
            
            const response = await fetch(`/api/users/${username}`, {
                method: 'DELETE'
            });
            
            if (response.ok) {
                showAlert(`User ${username} deleted`);
                loadUsers();
            } else {
                const error = await response.json();
                showAlert(error.error || 'Failed to delete user', 'error');
            }
        }
        
        async function setAutoLogin(username) {
            const response = await fetch(`/api/users/${username}/autologin`, {
                method: 'POST'
            });
            
            if (response.ok) {
                showAlert(`Auto-login set to ${username}. Reboot to apply.`);
                loadUsers();
            } else {
                const error = await response.json();
                showAlert(error.error || 'Failed to set auto-login', 'error');
            }
        }
        
        // Load Spotify configuration
        async function loadSpotifyConfig() {
            const response = await fetch('/api/spotify/config');
            const config = await response.json();
            
            const statusDiv = document.getElementById('spotifyStatus');
            let statusHTML = '<div style="padding: 10px; background: #f9f9f9; border-radius: 5px;">';
            
            // Show API configuration status
            if (config.api_configured) {
                statusHTML += `
                    <p style="color: green; margin-bottom: 5px;">
                        ✓ API Configured
                        <span style="color: #666; font-size: 11px; margin-left: 10px;">
                            Client ID: ${config.client_id ? config.client_id.substring(0, 8) + '...' : 'Not set'}
                        </span>
                    </p>
                `;
                // Pre-fill the client ID field if it exists
                if (config.client_id && document.getElementById('clientId')) {
                    document.getElementById('clientId').value = config.client_id;
                }
            } else {
                statusHTML += `
                    <p style="color: orange; margin-bottom: 5px;">
                        ⚠️ API Credentials Required
                        <span style="color: #666; font-size: 11px; margin-left: 10px;">
                            Please configure Step 1 below
                        </span>
                    </p>
                `;
            }
            
            // Show account configuration status
            if (config.configured && config.username) {
                statusHTML += `
                    <p style="color: green;">
                        ✓ Account Connected: <strong>${config.username}</strong>
                        <span style="color: #666; font-size: 11px; margin-left: 10px;">
                            via ${config.backend}
                        </span>
                    </p>
                `;
                // Don't auto-fill username field - let user enter new one if needed
            } else if (config.configured) {
                statusHTML += `
                    <p style="color: green;">
                        ✓ Backend Configured
                        <span style="color: #666; font-size: 11px; margin-left: 10px;">
                            Using ${config.backend}
                        </span>
                    </p>
                `;
            } else {
                statusHTML += `
                    <p style="color: #999;">
                        ○ No account connected
                        <span style="color: #666; font-size: 11px; margin-left: 10px;">
                            Configure Step 2 after API setup
                        </span>
                    </p>
                `;
            }
            
            statusHTML += '</div>';
            statusDiv.innerHTML = statusHTML;
        }
        
        // API credentials form
        document.getElementById('apiForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const clientId = document.getElementById('clientId').value;
            const clientSecret = document.getElementById('clientSecret').value;
            
            const response = await fetch('/api/spotify/api-credentials', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({client_id: clientId, client_secret: clientSecret})
            });
            
            if (response.ok) {
                showAlert('✅ API credentials saved successfully');
                document.getElementById('clientSecret').value = '';
                loadSpotifyConfig();
            } else {
                showAlert('Failed to save API credentials', 'error');
            }
        });
        
        // OAuth login (make it global for onclick)
        window.startOAuth = function() {
            window.location.href = '/api/spotify/oauth/authorize';
        }
        
        // Spotify configuration
        document.getElementById('spotifyForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const username = document.getElementById('spotifyUsername').value;
            const password = document.getElementById('spotifyPassword').value;
            const target_user = document.getElementById('targetUser').value;
            
            const response = await fetch('/api/spotify/config', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({username, password, target_user})
            });
            
            if (response.ok) {
                const result = await response.json();
                showAlert(`Spotify configured successfully! Using ${result.backend}`);
                loadSpotifyConfig();
                document.getElementById('spotifyPassword').value = '';
            } else {
                const error = await response.json();
                showAlert(error.error || 'Failed to configure Spotify', 'error');
            }
        });
        
        // Password change
        document.getElementById('passwordForm')?.addEventListener('submit', async (e) => {
            e.preventDefault();
            const newPass = document.getElementById('newPassword').value;
            const confirmPass = document.getElementById('confirmPassword').value;
            
            if (newPass !== confirmPass) {
                showAlert('Passwords do not match', 'error');
                return;
            }
            
            const response = await fetch('/api/password', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({password: newPass})
            });
            
            if (response.ok) {
                showAlert('Password changed successfully');
                document.getElementById('passwordForm').reset();
            } else {
                showAlert('Failed to change password', 'error');
            }
        });
        
        // System functions
        async function restartService() {
            if (!confirm('Restart the service?')) return;
            await fetch('/api/system/restart', {method: 'POST'});
            showAlert('Service restarting...');
        }
        
        async function rebootSystem() {
            if (!confirm('Reboot the entire system? All users will be disconnected.')) return;
            const response = await fetch('/api/system/reboot', {method: 'POST'});
            if (response.ok) {
                showAlert('System rebooting in 5 seconds...');
            }
        }
        
        async function shutdownSystem() {
            if (!confirm('Shutdown the system? You will need to manually power it back on.')) return;
            const response = await fetch('/api/system/shutdown', {method: 'POST'});
            if (response.ok) {
                showAlert('System shutting down in 5 seconds...');
            }
        }
        
        async function viewLogs() {
            const response = await fetch('/api/system/logs');
            const logs = await response.text();
            alert(logs);
        }
        
        async function viewLoginLogs() {
            const response = await fetch('/api/system/login-logs');
            const data = await response.json();
            
            let logDisplay = "=== LOGIN LOGS ===\\n";
            
            if (data.last_login) {
                logDisplay += "\\nLast Login: " + data.last_login + "\\n";
            }
            
            logDisplay += "\\nSpotify Client Status: " + data.status + "\\n";
            
            if (data.login_log) {
                logDisplay += "\\n=== Login History ===\\n" + data.login_log;
            }
            
            if (data.startup_log) {
                logDisplay += "\\n\\n=== Last Startup Log ===\\n" + data.startup_log;
            }
            
            if (data.client_log) {
                logDisplay += "\\n\\n=== Client Log ===\\n" + data.client_log;
            }
            
            if (data.spotify_auth_log) {
                logDisplay += "\\n\\n=== Spotify Authentication Log ===\\n" + data.spotify_auth_log;
            }
            
            // Create a modal or use a better display method
            const logWindow = window.open('', 'Login Logs', 'width=800,height=600');
            logWindow.document.write('<pre>' + logDisplay + '</pre>');
        }
        
        async function logout() {
            await fetch('/api/logout', {method: 'POST'});
            window.location.reload();
        }
        
        async function uninstall() {
            if (!confirm('This will completely remove the Spotify Kids Manager. Continue?')) return;
            if (!confirm('Are you absolutely sure? This cannot be undone!')) return;
            
            await fetch('/api/system/uninstall', {method: 'POST'});
            showAlert('Uninstalling system... The device will reboot.');
        }
        
        // Load system info
        async function loadSystemInfo() {
            const response = await fetch('/api/system/info');
            const info = await response.json();
            document.getElementById('systemInfo').innerHTML = `
                <p><strong>Version:</strong> ${info.version}</p>
                <p><strong>Uptime:</strong> ${info.uptime}</p>
                <p><strong>Memory:</strong> ${info.memory}</p>
                <p><strong>Disk:</strong> ${info.disk}</p>
            `;
        }
        
        if (document.getElementById('systemInfo')) {
            loadSystemInfo();
            setInterval(loadSystemInfo, 30000);
        }
        
        if (document.getElementById('spotifyStatus')) {
            loadSpotifyConfig();
        }
        
        if (document.getElementById('usersList')) {
            loadUsers();
        }
    </script>
</body>
</html>
'''

# Routes
@app.route('/')
def index():
    config = load_config()
    return render_template_string(HTML_TEMPLATE, 
                                 logged_in='logged_in' in session,
                                 device_locked=config.get('device_locked', False),
                                 spotify_enabled=config.get('spotify_enabled', True))

@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    config = load_config()
    
    if data['username'] == config['admin_user'] and check_password_hash(config['admin_pass'], data['password']):
        session['logged_in'] = True
        return jsonify({"success": True})
    return jsonify({"error": "Invalid credentials"}), 401

@app.route('/api/logout', methods=['POST'])
@login_required
def logout():
    session.pop('logged_in', None)
    return jsonify({"success": True})

@app.route('/api/device/lock', methods=['POST'])
@login_required
def device_lock():
    data = request.json
    config = load_config()
    config['device_locked'] = data['locked']
    save_config(config)
    
    # Create or remove lock file
    if data['locked']:
        open(LOCK_FILE, 'a').close()
    else:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    
    return jsonify({"success": True})

@app.route('/api/spotify/access', methods=['POST'])
@login_required
def spotify_access():
    data = request.json
    config = load_config()
    config['spotify_enabled'] = data['enabled']
    save_config(config)
    
    # Update client configuration
    with open(CLIENT_CONFIG, 'w') as f:
        f.write(f"SPOTIFY_DISABLED={'false' if data['enabled'] else 'true'}\n")
    
    # Restart client if disabled
    if not data['enabled']:
        subprocess.run(['pkill', '-f', 'ncspot'], capture_output=True)
    
    return jsonify({"success": True})

@app.route('/api/bluetooth/scan')
@login_required
def bluetooth_scan():
    try:
        # Use bluetoothctl to scan
        subprocess.run(['bluetoothctl', 'scan', 'on'], capture_output=True, timeout=5)
        result = subprocess.run(['bluetoothctl', 'devices'], capture_output=True, text=True)
        
        devices = []
        for line in result.stdout.splitlines():
            if 'Device' in line:
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    devices.append({
                        'address': parts[1],
                        'name': parts[2] if len(parts) > 2 else 'Unknown',
                        'paired': False  # Check pairing status separately
                    })
        
        return jsonify(devices)
    except Exception as e:
        return jsonify([])

@app.route('/api/bluetooth/pair', methods=['POST'])
@login_required
def bluetooth_pair():
    data = request.json
    address = data['address']
    
    try:
        # Pair and connect
        subprocess.run(['bluetoothctl', 'pair', address], capture_output=True, timeout=10)
        subprocess.run(['bluetoothctl', 'connect', address], capture_output=True, timeout=10)
        subprocess.run(['bluetoothctl', 'trust', address], capture_output=True)
        
        # Set as audio sink
        subprocess.run(['pactl', 'set-default-sink', address.replace(':', '_')], capture_output=True)
        
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/password', methods=['POST'])
@login_required
def change_password():
    data = request.json
    config = load_config()
    config['admin_pass'] = generate_password_hash(data['password'])
    save_config(config)
    return jsonify({"success": True})

@app.route('/api/system/info')
@login_required
def system_info():
    # Get system information
    uptime = subprocess.run(['uptime', '-p'], capture_output=True, text=True).stdout.strip()
    memory = subprocess.run(['free', '-h'], capture_output=True, text=True).stdout.splitlines()[1]
    disk = subprocess.run(['df', '-h', '/'], capture_output=True, text=True).stdout.splitlines()[1]
    
    return jsonify({
        'version': '1.0.0',
        'uptime': uptime,
        'memory': memory.split()[2] + ' / ' + memory.split()[1],
        'disk': disk.split()[3] + ' / ' + disk.split()[1]
    })

@app.route('/api/system/logs')
@login_required
def system_logs():
    logs = subprocess.run(['journalctl', '-u', 'spotify-terminal-admin', '-n', '100'], 
                         capture_output=True, text=True).stdout
    return logs

@app.route('/api/system/login-logs')
@login_required
def login_logs():
    """Get login logs for Spotify users"""
    logs = {
        "login_log": "",
        "startup_log": "",
        "client_log": "",
        "spotify_auth_log": "",
        "last_login": None,
        "status": "unknown"
    }
    
    # Read login log
    try:
        if os.path.exists('/opt/spotify-terminal/data/login.log'):
            with open('/opt/spotify-terminal/data/login.log', 'r') as f:
                logs["login_log"] = f.read()
                # Get last login time
                lines = logs["login_log"].strip().split('\\n')
                if lines:
                    for line in reversed(lines):
                        if 'logged in' in line:
                            logs["last_login"] = line
                            break
    except:
        pass
    
    # Read startup log
    try:
        if os.path.exists('/tmp/spotify-startup.log'):
            with open('/tmp/spotify-startup.log', 'r') as f:
                logs["startup_log"] = f.read()
    except:
        pass
    
    # Read client log
    try:
        if os.path.exists('/opt/spotify-terminal/data/client.log'):
            with open('/opt/spotify-terminal/data/client.log', 'r') as f:
                logs["client_log"] = f.read()
    except:
        pass
    
    # Read Spotify authentication log
    try:
        if os.path.exists('/opt/spotify-terminal/data/spotify-auth.log'):
            with open('/opt/spotify-terminal/data/spotify-auth.log', 'r') as f:
                logs["spotify_auth_log"] = f.read()
    except:
        pass
    
    # Check if ncspot is running
    try:
        # Check for web player server or ncspot
        result = subprocess.run(['pgrep', '-f', 'spotify_server.py|ncspot'], capture_output=True, shell=True)
        if result.returncode == 0:
            logs["status"] = "running"
        else:
            # Check if Chromium is running (indicates GUI mode)
            result = subprocess.run(['pgrep', '-f', 'chromium'], capture_output=True)
            if result.returncode == 0:
                logs["status"] = "gui_running"
            else:
                logs["status"] = "not_running"
    except:
        logs["status"] = "error"
    
    return jsonify(logs)

@app.route('/api/system/restart', methods=['POST'])
@login_required
def restart_service():
    subprocess.run(['systemctl', 'restart', 'spotify-terminal-admin'], capture_output=True)
    return jsonify({"success": True})

@app.route('/api/system/uninstall', methods=['POST'])
@login_required
def uninstall():
    # Run uninstall script
    subprocess.Popen(['/opt/spotify-terminal/scripts/uninstall.sh'])
    return jsonify({"success": True})

@app.route('/api/spotify/api-credentials', methods=['POST'])
@login_required
def set_api_credentials():
    """Save Spotify API credentials"""
    data = request.json
    client_id = data.get('client_id', '').strip()
    client_secret = data.get('client_secret', '').strip()
    
    if not client_id or not client_secret:
        return jsonify({"error": "Client ID and Secret are required"}), 400
    
    config = load_config()
    config['spotify_client_id'] = client_id
    config['spotify_client_secret'] = client_secret
    save_config(config)
    
    # Also save to environment for the spotify_server.py to use
    env_file = '/opt/spotify-terminal/config/spotify.env'
    os.makedirs(os.path.dirname(env_file), exist_ok=True)
    with open(env_file, 'w') as f:
        f.write(f"SPOTIFY_CLIENT_ID={client_id}\n")
        f.write(f"SPOTIFY_CLIENT_SECRET={client_secret}\n")
        f.write(f"SPOTIFY_REDIRECT_URI=http://localhost:8888/callback\n")
    
    return jsonify({"success": True, "message": "API credentials saved"})

@app.route('/api/spotify/oauth/authorize')
@login_required
def spotify_oauth_authorize():
    """Start OAuth flow"""
    config = load_config()
    client_id = config.get('spotify_client_id')
    
    if not client_id:
        return jsonify({"error": "Please configure API credentials first"}), 400
    
    # Redirect to Spotify authorization
    redirect_uri = "http://localhost:8888/callback"
    scope = "user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private user-library-read streaming"
    auth_url = f"https://accounts.spotify.com/authorize?client_id={client_id}&response_type=code&redirect_uri={redirect_uri}&scope={scope}"
    
    return redirect(auth_url)

@app.route('/api/spotify/config', methods=['GET'])
@login_required
def get_spotify_config():
    # Get current configuration from our config file
    config = load_config()
    
    spotify_config = {
        "configured": False,
        "username": None,  # Use None instead of empty string
        "backend": "none",
        "api_configured": False,
        "client_id": None
    }
    
    # Check if API credentials are configured
    if config.get('spotify_client_id') and config.get('spotify_client_secret'):
        spotify_config['api_configured'] = True
        spotify_config['client_id'] = config.get('spotify_client_id')
    
    # Check backend configurations
    config_file = "/home/spotify-kids/.config/ncspot/config.toml"
    spotifyd_config = "/home/spotify-kids/.config/spotifyd/spotifyd.conf"
    raspotify_config = "/etc/default/raspotify"
    
    # Check raspotify first (system-wide config)
    if os.path.exists(raspotify_config):
        spotify_config['backend'] = 'raspotify'
        try:
            with open(raspotify_config, 'r') as f:
                content = f.read()
                # Extract username from OPTIONS="--username 'user' --password 'pass'"
                import re
                match = re.search(r"--username\s+['\"]([^'\"]+)['\"]", content)
                if match:
                    spotify_config['username'] = match.group(1)
                    spotify_config['configured'] = True
        except:
            pass
    
    # Check ncspot config if not raspotify
    if not spotify_config['configured'] and os.path.exists(config_file):
        try:
            with open(config_file, 'r') as f:
                content = f.read()
                # Extract username if present
                for line in content.splitlines():
                    if 'username' in line:
                        spotify_config['username'] = line.split('=')[1].strip().strip('"')
                        spotify_config['configured'] = True
                        break
        except:
            pass
    
    # Check if using spotifyd
    if not spotify_config['configured'] and os.path.exists(spotifyd_config):
        spotify_config['backend'] = 'spotifyd'
        try:
            with open(spotifyd_config, 'r') as f:
                content = f.read()
                for line in content.splitlines():
                    if line.startswith('username'):
                        spotify_config['username'] = line.split('=')[1].strip()
                        spotify_config['configured'] = True
                        break
        except:
            pass
    
    # Check for OAuth tokens in config
    if config.get('spotify_oauth_token'):
        spotify_config['configured'] = True
        spotify_config['backend'] = 'oauth'
        if config.get('spotify_username'):
            spotify_config['username'] = config.get('spotify_username')
    
    return jsonify(spotify_config)

@app.route('/api/users', methods=['GET'])
@login_required
def get_users():
    # Get all non-root users that can be used for Spotify
    users = []
    try:
        with open('/etc/passwd', 'r') as f:
            for line in f:
                parts = line.strip().split(':')
                if len(parts) >= 7:
                    username = parts[0]
                    uid = int(parts[2])
                    home = parts[5]
                    shell = parts[6]
                    # Get users with UID >= 1000 (regular users) and valid shells
                    if uid >= 1000 and uid < 65534 and '/home/' in home and 'nologin' not in shell:
                        # Check if this user has Spotify configured
                        spotify_configured = False
                        spotify_username = None
                        
                        # Check ncspot config for Spotify username
                        ncspot_config_path = f"{home}/.config/ncspot/config.toml"
                        if os.path.exists(ncspot_config_path):
                            spotify_configured = True
                            try:
                                with open(ncspot_config_path, 'r') as f:
                                    for line in f:
                                        if line.strip().startswith('username'):
                                            # Extract username from line like: username = "myuser"
                                            spotify_username = line.split('=')[1].strip().strip('"').strip("'")
                                            break
                            except:
                                pass
                        
                        # Check spotifyd config as fallback
                        spotifyd_config_path = f"{home}/.config/spotifyd/spotifyd.conf"
                        if not spotify_username and os.path.exists(spotifyd_config_path):
                            spotify_configured = True
                            try:
                                with open(spotifyd_config_path, 'r') as f:
                                    for line in f:
                                        if line.strip().startswith('username'):
                                            spotify_username = line.split('=')[1].strip().strip('"')
                                            break
                            except:
                                pass
                        
                        # Check raspotify config
                        if not spotify_username and os.path.exists('/etc/default/raspotify'):
                            try:
                                with open('/etc/default/raspotify', 'r') as f:
                                    for line in f:
                                        if 'OPTIONS=' in line and '--username' in line:
                                            # Extract username from OPTIONS="--username 'user' --password 'pass'"
                                            import re
                                            match = re.search(r"--username\s+['\"]([^'\"]+)['\"]", line)
                                            if match:
                                                spotify_username = match.group(1)
                                                spotify_configured = True
                                                break
                            except:
                                pass
                        
                        # Check if ncspot is currently running for this user
                        is_logged_in = False
                        try:
                            # Check if ncspot process is running for this user
                            result = subprocess.run(['pgrep', '-u', username, '-f', 'ncspot'], 
                                                  capture_output=True)
                            if result.returncode == 0:
                                is_logged_in = True
                        except:
                            pass
                        
                        # Check if this is the auto-login user
                        auto_login = False
                        getty_override = "/etc/systemd/system/getty@tty1.service.d/override.conf"
                        if os.path.exists(getty_override):
                            with open(getty_override, 'r') as f:
                                if f'--autologin {username}' in f.read():
                                    auto_login = True
                        
                        users.append({
                            'username': username,
                            'uid': uid,
                            'home': home,
                            'spotify_configured': spotify_configured,
                            'spotify_username': spotify_username if spotify_username else None,  # Ensure None, not empty string
                            'is_logged_in': is_logged_in,
                            'auto_login': auto_login
                        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    
    return jsonify(users)

@app.route('/api/users', methods=['POST'])
@login_required
def create_user():
    data = request.json
    username = data.get('username', '').strip()
    
    if not username:
        return jsonify({"error": "Username required"}), 400
    
    # Validate username (alphanumeric and underscore only)
    if not username.replace('_', '').isalnum():
        return jsonify({"error": "Invalid username. Use only letters, numbers, and underscores"}), 400
    
    # Check if user already exists
    result = subprocess.run(['id', username], capture_output=True)
    if result.returncode == 0:
        return jsonify({"error": f"User {username} already exists"}), 400
    
    # Create user without sudo access
    try:
        # Create user with home directory, bash shell, and audio/video/bluetooth groups
        subprocess.run([
            'useradd', '-m', 
            '-s', '/bin/bash',
            '-G', 'audio,video,bluetooth',
            username
        ], check=True)
        
        # Set up user directories
        home_dir = f"/home/{username}"
        subprocess.run(['mkdir', '-p', f"{home_dir}/.config"], check=True)
        subprocess.run(['mkdir', '-p', f"{home_dir}/.cache"], check=True)
        subprocess.run(['mkdir', '-p', f"{home_dir}/.cache/ncspot"], check=True)
        subprocess.run(['mkdir', '-p', f"{home_dir}/.cache/spotifyd"], check=True)
        
        # Set ownership
        subprocess.run(['chown', '-R', f'{username}:{username}', home_dir], check=True)
        
        # Create bash profile for auto-start (terminal mode)
        bash_profile = f"{home_dir}/.bash_profile"
        with open(bash_profile, 'w') as f:
            f.write(f'''#!/bin/bash
# Auto-start Spotify client on login (terminal mode)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] User {username} logged in on $(tty)" >> /opt/spotify-terminal/data/login.log
if [[ "$(tty)" == "/dev/tty1" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Spotify Kids Manager for user {username}..." >> /opt/spotify-terminal/data/login.log
    echo "Starting Spotify Kids Manager in terminal mode..." > /tmp/spotify-startup.log
    chmod 666 /tmp/spotify-startup.log 2>/dev/null || true
    export HOME={home_dir}
    export USER={username}
    export TERM=linux
    
    # Log environment
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HOME=$HOME, USER=$USER, TTY=$(tty)" >> /opt/spotify-terminal/data/login.log
    
    # Clear the screen
    clear
    
    # Check if spotify-client.sh exists
    if [ -f /opt/spotify-terminal/scripts/spotify-client.sh ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting spotify-client.sh for user {username}" >> /opt/spotify-terminal/data/login.log
        exec /opt/spotify-terminal/scripts/spotify-client.sh 2>> /tmp/spotify-startup.log
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: spotify-client.sh not found!" >> /opt/spotify-terminal/data/login.log
        echo "ERROR: Spotify client script not found"
        echo "Press any key to continue..."
        read -n 1
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] User {username} on $(tty) - not tty1, skipping auto-start" >> /opt/spotify-terminal/data/login.log
fi
''')
        
        # Also create .profile
        profile = f"{home_dir}/.profile"
        with open(profile, 'w') as f:
            f.write(f'''#!/bin/bash
# Auto-start Spotify client on login (terminal mode)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] User {username} logged in on $(tty)" >> /opt/spotify-terminal/data/login.log
if [[ "$(tty)" == "/dev/tty1" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Spotify Kids Manager for user {username}..." >> /opt/spotify-terminal/data/login.log
    echo "Starting Spotify Kids Manager in terminal mode..." > /tmp/spotify-startup.log
    chmod 666 /tmp/spotify-startup.log 2>/dev/null || true
    export HOME={home_dir}
    export USER={username}
    export TERM=linux
    
    # Log environment
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HOME=$HOME, USER=$USER, TTY=$(tty)" >> /opt/spotify-terminal/data/login.log
    
    # Clear the screen
    clear
    
    # Check if spotify-client.sh exists
    if [ -f /opt/spotify-terminal/scripts/spotify-client.sh ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting spotify-client.sh for user {username}" >> /opt/spotify-terminal/data/login.log
        exec /opt/spotify-terminal/scripts/spotify-client.sh 2>> /tmp/spotify-startup.log
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: spotify-client.sh not found!" >> /opt/spotify-terminal/data/login.log
        echo "ERROR: Spotify client script not found"
        echo "Press any key to continue..."
        read -n 1
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] User {username} on $(tty) - not tty1, skipping auto-start" >> /opt/spotify-terminal/data/login.log
fi
''')
        
        # Create .bashrc
        bashrc = f"{home_dir}/.bashrc"
        with open(bashrc, 'w') as f:
            f.write('''# Source bash_profile if on tty1
if [[ -f ~/.bash_profile ]]; then
    source ~/.bash_profile
fi
''')
        
        # Set permissions
        subprocess.run(['chmod', '+x', bash_profile], check=True)
        subprocess.run(['chmod', '+x', profile], check=True)
        subprocess.run(['chmod', '644', bashrc], check=True)
        subprocess.run(['chown', f'{username}:{username}', bash_profile], check=True)
        subprocess.run(['chown', f'{username}:{username}', profile], check=True)
        subprocess.run(['chown', f'{username}:{username}', bashrc], check=True)
        
        return jsonify({
            "success": True, 
            "message": f"User {username} created successfully",
            "username": username
        })
        
    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Failed to create user: {str(e)}"}), 500

@app.route('/api/users/<username>', methods=['DELETE'])
@login_required
def delete_user(username):
    # Don't allow deleting the default spotify-kids user
    if username == "spotify-kids":
        return jsonify({"error": "Cannot delete the default spotify-kids user"}), 400
    
    # Check if user exists
    result = subprocess.run(['id', username], capture_output=True)
    if result.returncode != 0:
        return jsonify({"error": f"User {username} does not exist"}), 404
    
    try:
        # Remove from auto-login if configured
        getty_override = "/etc/systemd/system/getty@tty1.service.d/override.conf"
        if os.path.exists(getty_override):
            with open(getty_override, 'r') as f:
                content = f.read()
            if f'--autologin {username}' in content:
                # Reset to default spotify-kids user
                set_autologin_user("spotify-kids")
        
        # Kill any processes owned by the user
        subprocess.run(['pkill', '-u', username], capture_output=True)
        
        # Delete the user and their home directory
        subprocess.run(['userdel', '-r', username], check=True)
        
        return jsonify({"success": True, "message": f"User {username} deleted"})
        
    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Failed to delete user: {str(e)}"}), 500

@app.route('/api/users/<username>/autologin', methods=['POST'])
@login_required
def set_user_autologin(username):
    # Check if user exists
    result = subprocess.run(['id', username], capture_output=True)
    if result.returncode != 0:
        return jsonify({"error": f"User {username} does not exist"}), 404
    
    try:
        set_autologin_user(username)
        return jsonify({"success": True, "message": f"Auto-login set to {username}"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def set_autologin_user(username):
    """Helper function to set auto-login user"""
    getty_override = "/etc/systemd/system/getty@tty1.service.d/override.conf"
    os.makedirs(os.path.dirname(getty_override), exist_ok=True)
    
    with open(getty_override, 'w') as f:
        f.write(f'''[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin {username} --noclear %I \$TERM
''')
    
    # Reload systemd
    subprocess.run(['systemctl', 'daemon-reload'])
    subprocess.run(['systemctl', 'restart', 'getty@tty1.service'])

@app.route('/api/spotify/config', methods=['POST'])
@login_required
def set_spotify_config():
    data = request.json
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()
    target_user = data.get('target_user', 'spotify-kids').strip()  # Which user to configure
    
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    
    # Check if target user exists
    result = subprocess.run(['id', target_user], capture_output=True)
    if result.returncode != 0:
        return jsonify({"error": f"User {target_user} does not exist"}), 404
    
    # Get user's home directory
    home_dir = f"/home/{target_user}"
    if not os.path.exists(home_dir):
        return jsonify({"error": f"Home directory for {target_user} not found"}), 500
    
    # Detect which backend we're using
    backend = "ncspot"
    if os.path.exists("/etc/default/raspotify"):
        backend = "raspotify"
    elif os.path.exists("/usr/local/bin/spotifyd"):
        backend = "spotifyd"
    
    if backend == "ncspot":
        # Configure ncspot for target user
        config_dir = f"{home_dir}/.config/ncspot"
        config_file = f"{config_dir}/config.toml"
        
        os.makedirs(config_dir, exist_ok=True)
        
        # Create ncspot config with credentials
        config_content = f'''[theme]
background = "black"
primary = "green"
secondary = "light white"
title = "white"
playing = "green"
playing_selected = "light green"
playing_bg = "black"
highlight = "light white"
highlight_bg = "#484848"
error = "light red"
error_bg = "red"
statusbar = "black"
statusbar_progress = "green"
statusbar_bg = "green"
cmdline = "light white"
cmdline_bg = "black"
search_match = "light red"

[backend]
backend = "pulseaudio"
username = "{username}"
password = "{password}"
bitrate = 320
enable_cache = true

[cache]
enabled = true
path = "{home_dir}/.cache/ncspot"
size = 10000

[keybindings]
"q" = "quit"
'''
        
        with open(config_file, 'w') as f:
            f.write(config_content)
        
        # Set proper ownership
        subprocess.run(['chown', '-R', f'{target_user}:{target_user}', config_dir])
        
        # Also create credentials cache file for ncspot
        creds_file = f"{config_dir}/credentials.json"
        creds_content = {
            "username": username,
            "auth_type": "password",
            "password": password
        }
        
        with open(creds_file, 'w') as f:
            json.dump(creds_content, f)
        
        subprocess.run(['chmod', '600', creds_file])
        subprocess.run(['chown', f'{target_user}:{target_user}', creds_file])
        
    elif backend == "raspotify":
        # Configure raspotify system-wide (it doesn't use per-user config)
        raspotify_config = "/etc/default/raspotify"
        
        # Create raspotify config with credentials
        config_content = f'''# Raspotify configuration
OPTIONS="--username '{username}' --password '{password}' --backend alsa --device-name 'Spotify Kids Player' --bitrate 320"
BACKEND="alsa"
VOLUME_NORMALISATION="true"
NORMALISATION_PREGAIN="-10"
'''
        
        with open(raspotify_config, 'w') as f:
            f.write(config_content)
        
        # Set proper permissions
        subprocess.run(['chmod', '644', raspotify_config])
        
        # Restart raspotify service
        subprocess.run(['systemctl', 'restart', 'raspotify'], capture_output=True)
        
    else:
        # Configure spotifyd for target user
        config_dir = f"{home_dir}/.config/spotifyd"
        config_file = f"{config_dir}/spotifyd.conf"
        
        os.makedirs(config_dir, exist_ok=True)
        
        # Create spotifyd config
        config_content = f'''[global]
username = {username}
password = {password}
backend = alsa
device_name = Spotify Kids Player
bitrate = 320
cache_path = {home_dir}/.cache/spotifyd
max_cache_size = 10000000000
cache = true
volume_normalisation = true
normalisation_pregain = -10
'''
        
        with open(config_file, 'w') as f:
            f.write(config_content)
        
        # Set proper ownership
        subprocess.run(['chown', '-R', f'{target_user}:{target_user}', config_dir])
        subprocess.run(['chmod', '600', config_file])
        
        # Restart spotifyd if running
        subprocess.run(['systemctl', 'restart', 'spotifyd'], capture_output=True)
    
    # Save to our config
    config = load_config()
    config['spotify_configured'] = True
    config['spotify_username'] = username
    save_config(config)
    
    # Restart the target user's session to apply changes
    subprocess.run(['pkill', '-u', target_user], capture_output=True)
    
    return jsonify({"success": True, "message": f"Spotify configured for {target_user} with username {username}", "backend": backend, "user": target_user})

@app.route('/api/system/reboot', methods=['POST'])
@login_required
def reboot_system():
    # Schedule a reboot in 5 seconds to allow response to be sent
    import threading
    def do_reboot():
        import time
        time.sleep(5)
        # Try multiple commands to ensure it works
        try:
            subprocess.run(['/sbin/reboot'], check=True)
        except:
            try:
                subprocess.run(['systemctl', 'reboot'], check=True)
            except:
                subprocess.run(['reboot'], check=True)
    
    threading.Thread(target=do_reboot, daemon=True).start()
    return jsonify({"success": True, "message": "System will reboot in 5 seconds"})

@app.route('/api/system/shutdown', methods=['POST'])
@login_required
def shutdown_system():
    # Schedule a shutdown in 5 seconds to allow response to be sent
    import threading
    def do_shutdown():
        import time
        time.sleep(5)
        try:
            subprocess.run(['/sbin/poweroff'], check=True)
        except:
            try:
                subprocess.run(['systemctl', 'poweroff'], check=True)
            except:
                subprocess.run(['poweroff'], check=True)
    
    threading.Thread(target=do_shutdown, daemon=True).start()
    return jsonify({"success": True, "message": "System will shutdown in 5 seconds"})

if __name__ == '__main__':
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)
    os.makedirs(os.path.dirname(CLIENT_CONFIG), exist_ok=True)
    
    app.run(host='0.0.0.0', port=5001, debug=False)
EOF
    
    # Make app.py executable if it exists
    [ -f "$INSTALL_DIR/web/app.py" ] && chmod +x "$INSTALL_DIR/web/app.py"
    
    log_success "Web admin panel created"
    
    # Copy web player files
    log_info "Installing web player files..."
    
    # Download from GitHub if local files don't exist
    if [ -d "$SCRIPT_DIR/web" ]; then
        log_info "Copying web player files from local directory..."
        cp "$SCRIPT_DIR/spotify_player.py" "$INSTALL_DIR/" 2>/dev/null || true
    else
        log_info "Downloading web player files from GitHub..."
        for file in spotify_player.py; do
            wget -q -O "$INSTALL_DIR/web/$file" \
                "https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/$file" || {
                    log_warning "Could not download $file"
                }
        done
    fi
    
    # Install Python dependencies for native player
    # Python dependencies already installed in main install_dependencies function
    
    # Ensure permissions
    chown -R root:root "$INSTALL_DIR/web"
    chmod 755 "$INSTALL_DIR/web"
    chmod 644 "$INSTALL_DIR/web/"*.py "$INSTALL_DIR/web/"*.html "$INSTALL_DIR/web/"*.js 2>/dev/null || true
    
    log_success "Web player files installed"
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Spotify Terminal Admin Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/web
ExecStart=/usr/bin/python3 $INSTALL_DIR/web/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    # Configure nginx reverse proxy
    cat > "/etc/nginx/sites-available/spotify-admin" <<EOF
server {
    listen $WEB_PORT;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:5001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
    
    # Enable nginx site
    ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Start services
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    systemctl restart nginx
    
    log_success "Services configured and started"
}

# Create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    cat > "$INSTALL_DIR/scripts/uninstall.sh" <<'EOF'
#!/bin/bash

# Spotify Terminal Manager - Uninstaller

echo "Starting uninstallation..."

# Stop services
systemctl stop spotify-terminal-admin
systemctl disable spotify-terminal-admin
systemctl stop getty@tty1

# Remove systemd files
rm -f /etc/systemd/system/spotify-terminal-admin.service
rm -rf /etc/systemd/system/getty@tty1.service.d/

# Remove nginx configuration
rm -f /etc/nginx/sites-enabled/spotify-admin
rm -f /etc/nginx/sites-available/spotify-admin
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
systemctl restart nginx

# Remove user
pkill -u spotify-kids
userdel -r spotify-kids 2>/dev/null

# Remove installation directory
rm -rf /opt/spotify-terminal

# Remove packages (optional - commented out to avoid breaking other software)
# apt-get remove -y ncspot

# Reload systemd
systemctl daemon-reload

echo "Uninstallation complete. Rebooting in 5 seconds..."
sleep 5
reboot
EOF
    
    chmod +x "$INSTALL_DIR/scripts/uninstall.sh"
    
    log_success "Uninstall script created"
}

# Install custom boot splash screen (simple version for RPi)
install_bootsplash() {
    log_info "Installing simple boot splash..."
    
    # Check if we're on Raspberry Pi
    if [[ ! -f /proc/device-tree/model ]] || ! grep -q "Raspberry Pi" /proc/device-tree/model; then
        log_warning "Not running on Raspberry Pi, skipping boot splash"
        return
    fi
    
    # fbi already installed in main dependencies
    
    # Create splash directory
    mkdir -p /usr/share/pixmaps
    
    # Create simple Spotify Kids logo splash (black background with green logo)
    if command -v convert >/dev/null 2>&1; then
        log_info "Creating boot splash image..."
        convert -size 1920x1080 xc:black \
            -fill '#1DB954' \
            -draw "circle 960,540 960,640" \
            -fill black \
            -draw "arc 920,500 1000,580 340,20" \
            -draw "arc 900,520 1020,560 340,20" \
            -draw "arc 880,540 1040,540 340,20" \
            /usr/share/pixmaps/splash.png 2>/dev/null || {
                # Solid black fallback
                convert -size 1920x1080 xc:black /usr/share/pixmaps/splash.png 2>/dev/null
            }
    fi
    
    # Find cmdline.txt location
    if [ -f /boot/cmdline.txt ]; then
        CMDLINE="/boot/cmdline.txt"
    elif [ -f /boot/firmware/cmdline.txt ]; then  
        CMDLINE="/boot/firmware/cmdline.txt"
    else
        log_warning "cmdline.txt not found, skipping boot parameters"
        return
    fi
    
    # Backup and modify cmdline.txt for quiet boot
    cp "$CMDLINE" "$INSTALL_DIR/config/cmdline.txt.backup" 2>/dev/null || true
    if ! grep -q "logo.nologo" "$CMDLINE"; then
        sed -i 's/$/ logo.nologo consoleblank=1/' "$CMDLINE"
    fi
    
    # Find config.txt location
    if [ -f /boot/config.txt ]; then
        CONFIG="/boot/config.txt"
    elif [ -f /boot/firmware/config.txt ]; then
        CONFIG="/boot/firmware/config.txt"  
    else
        log_warning "config.txt not found"
        return
    fi
    
    # Disable rainbow splash
    if ! grep -q "disable_splash=1" "$CONFIG"; then
        echo "disable_splash=1" >> "$CONFIG"
    fi
    
    # Create simple splash service
    cat > /etc/systemd/system/bootsplash.service <<EOF
[Unit]
Description=Boot splash screen
DefaultDependencies=no
After=local-fs.target
Before=getty.target

[Service]
Type=forking
ExecStart=/usr/bin/fbi -T 1 -noverbose -a /usr/share/pixmaps/splash.png
ExecStop=/usr/bin/killall fbi
RemainAfterExit=yes
StandardInput=tty
StandardOutput=tty

[Install]
WantedBy=sysinit.target
EOF
    
    systemctl enable bootsplash.service 2>/dev/null || true
    
    log_success "Simple boot splash configured"
    return  # Exit here, skip all the complex Plymouth stuff
}

# Test and repair web admin panel
test_and_repair_web() {
    log_info "Testing web admin panel..."
    
    # Give services time to start
    sleep 3
    
    # Test if nginx is responding
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WEB_PORT" | grep -q "502"; then
        log_warning "502 Bad Gateway detected - attempting to fix..."
        
        # Check if Flask app is running
        if ! pgrep -f "app.py" > /dev/null; then
            log_warning "Flask app not running - checking why..."
            
            # Check if Python dependencies are installed
            log_info "Python dependencies should already be installed..."
            
            # Test Flask app directly
            log_info "Testing Flask app directly..."
            cd "$INSTALL_DIR/web"
            timeout 5 python3 app.py > /tmp/flask_test.log 2>&1 &
            sleep 2
            
            if pgrep -f "app.py" > /dev/null; then
                log_success "Flask app can run - restarting service..."
                pkill -f "app.py"
                systemctl restart "$SERVICE_NAME"
                sleep 3
            else
                log_error "Flask app failed to start. Check /tmp/flask_test.log"
                cat /tmp/flask_test.log
                
                # Try to fix common issues
                log_info "Attempting automatic repair..."
                
                # Fix permissions
                # Make app.py executable if it exists
    [ -f "$INSTALL_DIR/web/app.py" ] && chmod +x "$INSTALL_DIR/web/app.py"
                chown -R root:root "$INSTALL_DIR"
                
                # Ensure config directories exist
                mkdir -p "$INSTALL_DIR/config"
                mkdir -p "$INSTALL_DIR/data"
                touch "$INSTALL_DIR/config/admin.json"
                touch "$INSTALL_DIR/config/client.conf"
                
                # Restart service again
                systemctl daemon-reload
                systemctl restart "$SERVICE_NAME"
                sleep 3
            fi
        fi
        
        # Check nginx configuration
        if ! nginx -t 2>/dev/null; then
            log_warning "Nginx configuration error - fixing..."
            
            # Recreate nginx config
            cat > "/etc/nginx/sites-available/spotify-admin" <<EOF
server {
    listen $WEB_PORT;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:5001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
            ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/
            nginx -s reload
        fi
        
        # Final test
        sleep 2
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WEB_PORT")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            log_success "Web admin panel is working!"
        else
            log_warning "Web panel returned HTTP $HTTP_CODE"
            log_info "Checking service logs..."
            journalctl -u "$SERVICE_NAME" -n 20 --no-pager
        fi
    else
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WEB_PORT")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
            log_success "Web admin panel is working! (HTTP $HTTP_CODE)"
        else
            log_warning "Web panel returned HTTP $HTTP_CODE - may need login"
        fi
    fi
    
    # Show access URL
    IP=$(hostname -I | awk '{print $1}')
    log_info "Testing external access at http://$IP:$WEB_PORT ..."
    
    # Test from external IP
    if curl -s -o /dev/null -w "%{http_code}" "http://$IP:$WEB_PORT" | grep -q "200\|302"; then
        log_success "External access confirmed!"
    else
        log_warning "Cannot access from external IP - checking firewall..."
        
        # Check if port is open
        if ! ss -tln | grep -q ":$WEB_PORT"; then
            log_error "Port $WEB_PORT is not listening"
            systemctl status nginx --no-pager
        else
            log_info "Port $WEB_PORT is listening - may be firewall issue"
        fi
    fi
}

# Function to uninstall everything (used when re-running installer)
uninstall_all() {
    log_info "Removing ALL traces of installation..."
    
    # Stop all services first
    log_info "Stopping all services..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    systemctl stop raspotify 2>/dev/null || true
    systemctl stop spotifyd 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true
    
    # Kill all related processes forcefully
    log_info "Killing all related processes..."
    pkill -9 -f "app.py" 2>/dev/null || true
    pkill -9 -f "ncspot" 2>/dev/null || true
    pkill -9 -f "spotify_player.py" 2>/dev/null || true
    pkill -9 -f "start-web-player" 2>/dev/null || true
    pkill -9 -f "start-touchscreen" 2>/dev/null || true
    pkill -9 -u "$SPOTIFY_USER" 2>/dev/null || true
    
    # Clean up any lingering browser processes
    pkill -9 chrome 2>/dev/null || true
    
    # Find and remove ALL users created by our system
    log_info "Removing all created users..."
    
    # Remove the main spotify-kids user
    if id "$SPOTIFY_USER" &>/dev/null; then
        log_info "Removing user: $SPOTIFY_USER"
        # Kill all processes for this user first
        pkill -9 -u "$SPOTIFY_USER" 2>/dev/null || true
        sleep 1
        # Force remove user
        userdel -rf "$SPOTIFY_USER" 2>/dev/null || true
        # If userdel fails, manually remove
        rm -rf "/home/$SPOTIFY_USER" 2>/dev/null || true
    fi
    
    # Find and remove any other users created via the admin panel
    for user_home in /home/*; do
        username=$(basename "$user_home")
        # Skip system users and root
        if [[ "$username" != "pi" ]] && [[ "$username" != "root" ]] && [[ "$username" != "$SUDO_USER" ]]; then
            # Check if user has our Spotify setup files
            if [[ -f "$user_home/.bash_profile" ]] && grep -q "spotify" "$user_home/.bash_profile" 2>/dev/null; then
                log_info "Removing user created by admin panel: $username"
                pkill -9 -u "$username" 2>/dev/null || true
                sleep 1
                userdel -rf "$username" 2>/dev/null || true
                rm -rf "$user_home" 2>/dev/null || true
            fi
        fi
    done
    
    # Remove ALL systemd files
    log_info "Removing systemd configurations..."
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -f "/etc/systemd/system/spotify-"* 2>/dev/null || true
    rm -f "/lib/systemd/system/spotify-"* 2>/dev/null || true
    
    # Remove auto-login configurations for all ttys
    for i in {1..6}; do
        rm -rf "/etc/systemd/system/getty@tty$i.service.d/"
    done
    
    # Clean up systemd user services
    rm -rf /home/*/.config/systemd/user/spotify-* 2>/dev/null || true
    
    # Remove nginx config completely
    log_info "Removing nginx configurations..."
    rm -f /etc/nginx/sites-enabled/spotify-admin
    rm -f /etc/nginx/sites-available/spotify-admin
    rm -f /etc/nginx/sites-enabled/spotify*
    rm -f /etc/nginx/sites-available/spotify*
    
    # Remove all installation directories
    log_info "Removing installation directories..."
    rm -rf "$INSTALL_DIR"
    rm -rf /opt/spotify-terminal
    rm -rf /opt/spotify-kids
    rm -rf /opt/spotify*
    
    # Clean up all config and cache directories
    log_info "Cleaning up config and cache..."
    rm -rf /home/*/.config/ncspot
    rm -rf /home/*/.cache/ncspot
    rm -rf /home/*/.cache/spotifyd
    rm -rf /home/*/.config/spotify*
    rm -rf /home/*/.cache/spotify*
    rm -rf /root/.config/ncspot
    rm -rf /root/.cache/ncspot
    rm -rf /root/.config/spotify*
    rm -rf /root/.cache/spotify*
    
    # Remove any temporary files
    rm -rf /tmp/spotify* 2>/dev/null || true
    rm -rf /tmp/*touch* 2>/dev/null || true
    rm -f /tmp/flask_test.log 2>/dev/null || true
    rm -f /tmp/spotify-startup.log 2>/dev/null || true
    
    # Clean up logs
    rm -rf /var/log/spotify* 2>/dev/null || true
    
    # Clean up Python packages (optional - commented out to avoid removing system packages)
    # pip3 uninstall -y flask flask-cors flask-socketio werkzeug dbus-python pulsectl spotipy 2>/dev/null || true
    
    # Clean up any leftover X sessions
    rm -rf /tmp/.X* 2>/dev/null || true
    
    # Restore original boot splash
    log_info "Restoring original boot splash..."
    
    # Remove our splash service
    systemctl disable bootsplash.service 2>/dev/null || true
    rm -f /etc/systemd/system/bootsplash.service
    
    # Remove splash image
    rm -f /usr/share/pixmaps/splash.png
    
    # Restore cmdline.txt if we have backup
    if [ -f "$INSTALL_DIR/config/cmdline.txt.backup" ]; then
        if [ -f /boot/cmdline.txt ]; then
            cp "$INSTALL_DIR/config/cmdline.txt.backup" /boot/cmdline.txt
        elif [ -f /boot/firmware/cmdline.txt ]; then
            cp "$INSTALL_DIR/config/cmdline.txt.backup" /boot/firmware/cmdline.txt
        fi
    fi
    
    # Remove disable_splash from config.txt
    for config in /boot/config.txt /boot/firmware/config.txt; do
        [ -f "$config" ] && sed -i '/disable_splash=1/d' "$config"
    done
    
    # Restore boot configuration files
    if [ -f "$INSTALL_DIR/config/cmdline.txt.backup" ]; then
        cp "$INSTALL_DIR/config/cmdline.txt.backup" /boot/cmdline.txt 2>/dev/null || true
    elif [ -f /boot/cmdline.txt.backup ]; then
        cp /boot/cmdline.txt.backup /boot/cmdline.txt 2>/dev/null || true
    fi
    
    if [ -f "$INSTALL_DIR/config/grub.backup" ]; then
        cp "$INSTALL_DIR/config/grub.backup" /etc/default/grub 2>/dev/null || true
        update-grub >/dev/null 2>&1 || true
    elif [ -f /etc/default/grub.backup ]; then
        cp /etc/default/grub.backup /etc/default/grub 2>/dev/null || true
        update-grub >/dev/null 2>&1 || true
    fi
    
    # Update initramfs to remove our theme
    update-initramfs -u >/dev/null 2>&1 || true
    
    # Reset default runlevel back to graphical if it was changed
    systemctl set-default graphical.target 2>/dev/null || true
    
    # Reload systemd and restart nginx
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null || true
    systemctl restart nginx 2>/dev/null || true
    
    log_success "ALL traces of installation removed completely"
}

# Main installation flow
main() {
    # Check for help parameter
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        echo "Spotify Kids Terminal Manager - Installer"
        echo ""
        echo "Usage: sudo ./install.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h      Show this help message"
        echo "  --reset, -r     Complete reset - remove everything and reinstall"
        echo "  --diagnose, -d  Run diagnostics to troubleshoot issues"
        echo "  --uninstall     Remove the installation completely"
        echo ""
        echo "Examples:"
        echo "  sudo ./install.sh           # Normal installation"
        echo "  sudo ./install.sh --reset   # Complete reset and reinstall"
        echo "  sudo ./install.sh --diagnose # Diagnose 502 or other issues"
        echo ""
        exit 0
    fi
    
    # Check for uninstall parameter
    if [[ "$1" == "--uninstall" ]]; then
        clear
        echo "============================================"
        echo "    UNINSTALL"
        echo "============================================"
        echo ""
        check_root
        uninstall_all
        log_success "Uninstallation complete"
        exit 0
    fi
    
    # Check for diagnostic parameter
    if [[ "$1" == "--diagnose" ]] || [[ "$1" == "-d" ]]; then
        clear
        echo "============================================"
        echo "    DIAGNOSTIC MODE"
        echo "============================================"
        echo ""
        check_root
        
        log_info "Running diagnostics..."
        
        # Check installation
        if [ -d "$INSTALL_DIR" ]; then
            log_success "Installation directory exists"
            ls -la "$INSTALL_DIR/"
        else
            log_error "Not installed at $INSTALL_DIR"
        fi
        
        echo ""
        log_info "Checking services..."
        systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || log_error "Service not found"
        
        echo ""
        log_info "Checking nginx..."
        systemctl status nginx --no-pager 2>/dev/null || log_error "Nginx not running"
        
        echo ""
        log_info "Checking ports..."
        ss -tln | grep -E ":(8080|5001)" || log_error "Ports not listening"
        
        echo ""
        log_info "Testing Flask app directly..."
        if [ -f "$INSTALL_DIR/web/app.py" ]; then
            cd "$INSTALL_DIR/web"
            timeout 3 python3 -c "import flask; print('Flask available')" || log_error "Flask not installed"
            timeout 5 python3 app.py 2>&1 | head -20
        else
            log_error "Flask app not found"
        fi
        
        echo ""
        log_info "Checking logs..."
        journalctl -u "$SERVICE_NAME" -n 30 --no-pager
        
        echo ""
        log_info "Testing web access..."
        curl -v "http://localhost:$WEB_PORT" 2>&1 | head -30
        
        exit 0
    fi
    
    # Check for reset parameter
    if [[ "$1" == "--reset" ]] || [[ "$1" == "-r" ]]; then
        clear
        echo "============================================"
        echo "    COMPLETE SYSTEM RESET"
        echo "============================================"
        echo ""
        log_warning "Removing everything and reinstalling..."
        
        check_root
        log_info "Performing complete reset..."
        
        # Force uninstall everything
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        
        # Kill all related processes
        pkill -f "app.py" 2>/dev/null || true
        pkill -f "ncspot" 2>/dev/null || true
        pkill -f "spotify_player.py" 2>/dev/null || true
        pkill -u "$SPOTIFY_USER" 2>/dev/null || true
        
        # Find and remove ALL users created by our system
        log_info "Removing all created users..."
        
        # Remove the main spotify-kids user
        if id "$SPOTIFY_USER" &>/dev/null; then
            log_info "Removing user: $SPOTIFY_USER"
            pkill -u "$SPOTIFY_USER" 2>/dev/null || true
            userdel -rf "$SPOTIFY_USER" 2>/dev/null || true
        fi
        
        # Find and remove any other users created via the admin panel
        # These users would have been created without sudo and with specific groups
        for user_home in /home/*; do
            username=$(basename "$user_home")
            # Skip system users and root
            if [[ "$username" != "pi" ]] && [[ "$username" != "root" ]] && [[ "$username" != "$SUDO_USER" ]]; then
                # Check if user has our Spotify setup files
                if [[ -f "$user_home/.bash_profile" ]] && grep -q "spotify-client.sh" "$user_home/.bash_profile" 2>/dev/null; then
                    log_info "Removing user created by admin panel: $username"
                    pkill -u "$username" 2>/dev/null || true
                    userdel -rf "$username" 2>/dev/null || true
                fi
            fi
        done
        
        # Remove all config files and data
        log_info "Removing all configuration and data..."
        rm -rf "$INSTALL_DIR"
        rm -rf /opt/spotify-terminal
        rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        rm -rf /etc/systemd/system/getty@tty1.service.d/
        rm -f /etc/nginx/sites-enabled/spotify-admin
        rm -f /etc/nginx/sites-available/spotify-admin
        
        # Remove ncspot configs for all users
        rm -rf /home/*/.config/ncspot
        rm -rf /home/*/.cache/ncspot
        rm -rf /home/*/.cache/spotifyd
        rm -rf /root/.config/ncspot
        rm -rf /root/.cache/ncspot
        
        # Clean up Python packages
        pip3 uninstall -y flask flask-cors flask-socketio werkzeug dbus-python pulsectl spotipy 2>/dev/null || true
        
        # Reset nginx to default
        apt-get remove --purge -y nginx nginx-common 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf /etc/nginx
        
        # Remove auto-login configurations for all ttys
        for i in {1..6}; do
            rm -rf "/etc/systemd/system/getty@tty$i.service.d/"
        done
        
        # Reset default runlevel back to graphical if it was changed
        systemctl set-default graphical.target 2>/dev/null || true
        
        # Reload systemd
        systemctl daemon-reload
        
        log_success "Complete reset done. Starting fresh installation..."
        echo ""
        sleep 2
    fi
    
    clear
    echo "============================================"
    echo "    Spotify Kids Terminal Manager"
    echo "    Installation Script v1.0"
    echo "============================================"
    echo ""
    
    check_root
    detect_system
    
    # Skip existing installation check if we just reset
    if [[ "$1" != "--reset" ]] && [[ "$1" != "-r" ]]; then
        check_existing_installation
    fi
    
    log_info "Starting installation..."
    
    install_dependencies
    create_spotify_user
    setup_spotify_client
    
    # The setup_web_admin function contains a very large heredoc
    # which can cause bash parsing issues. Try to call it, but handle failure
    
    # Try to call setup_web_admin, but if it fails due to parsing, create web app manually
    setup_web_admin || {
        log_warning "Web admin setup encountered an issue, using alternative method..."
        
        # Ensure web directory exists
        mkdir -p "$INSTALL_DIR/web"
        
        # Download the Flask app from GitHub as fallback
        wget -q -O "$INSTALL_DIR/web/app.py" \
            "https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/app.py" 2>/dev/null || {
            
            # If download fails, create minimal app
            cat > "$INSTALL_DIR/web/app.py" << 'MINIMAL_APP'
#!/usr/bin/env python3
from flask import Flask, jsonify
app = Flask(__name__)
app.config['SECRET_KEY'] = 'temp-key'

@app.route('/')
def index():
    return jsonify({"status": "Web admin panel running (minimal mode)"})

if __name__ == '__main__':
    import os
    os.makedirs('/opt/spotify-terminal/config', exist_ok=True)
    os.makedirs('/opt/spotify-terminal/data', exist_ok=True)
    app.run(host='0.0.0.0', port=5001, debug=False)
MINIMAL_APP
        }
        
        [ -f "$INSTALL_DIR/web/app.py" ] && chmod +x "$INSTALL_DIR/web/app.py"
        log_success "Web admin panel created (alternative method)"
    }
    create_systemd_service
    create_uninstall_script
    install_bootsplash
    
    # Test and fix web panel if needed
    test_and_repair_web
    
    echo ""
    log_success "Installation complete!"
    echo ""
    echo "============================================"
    echo "  Access the admin panel at:"
    echo "  http://$(hostname -I | awk '{print $1}'):$WEB_PORT"
    echo ""
    echo "  Default credentials:"
    echo "  Username: admin"
    echo "  Password: changeme"
    echo ""
    echo "  IMPORTANT: Change the password immediately!"
    echo "============================================"
    echo ""
    echo "The device will reboot in 10 seconds to apply all changes..."
    echo "Press Ctrl+C to cancel reboot"
    
    sleep 10
    reboot
}

# Run main function
main "$@"