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
        python3-venv \
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
        matchbox-keyboard \
        xinit \
        xserver-xorg \
        xserver-xorg-input-libinput \
        openbox \
        unclutter \
        xterm \
        xinput \
        python3-gi \
        python3-gi-cairo \
        gir1.2-gtk-3.0 \
        python3-pydbus
    
    # Additional packages for GUI Spotify client (for touchscreen)
    apt-get install -y \
        qt5-default \
        qtmultimedia5-dev \
        libqt5svg5-dev \
        cmake \
        spotify-client \
        chromium-browser \
        2>/dev/null || true
    
    # Python packages for web admin
    pip3 install --break-system-packages \
        flask \
        flask-cors \
        flask-socketio \
        werkzeug \
        python-dotenv \
        dbus-python \
        pulsectl
    
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
    
    # Create auto-start scripts with minimal X for touchscreen support
    cat > "/home/$SPOTIFY_USER/.bash_profile" <<'EOF'
#!/bin/bash
# Auto-start Spotify client on login
echo "[$(date '+%Y-%m-%d %H:%M:%S')] User spotify-kids logged in on $(tty)" >> /opt/spotify-terminal/data/login.log
if [[ "$(tty)" == "/dev/tty1" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Spotify Kids Manager for user spotify-kids..." >> /opt/spotify-terminal/data/login.log
    echo "Starting Spotify Kids Manager..." > /tmp/spotify-startup.log
    chmod 666 /tmp/spotify-startup.log 2>/dev/null || true
    export HOME=/home/spotify-kids
    export USER=spotify-kids
    
    # Log environment
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HOME=$HOME, USER=$USER, TTY=$(tty)" >> /opt/spotify-terminal/data/login.log
    
    # Check for touchscreen
    if ls /dev/input/by-path/*event* 2>/dev/null | xargs -I{} udevadm info --query=property --name={} | grep -q "ID_INPUT_TOUCHSCREEN=1"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Touchscreen detected, starting GUI mode" >> /opt/spotify-terminal/data/login.log
        echo "Touchscreen detected, starting with GUI support..." >> /tmp/spotify-startup.log
        # Start minimal X with touchscreen support
        exec startx /opt/spotify-terminal/scripts/start-touchscreen.sh -- -nocursor 2>> /tmp/spotify-startup.log
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] No touchscreen, starting terminal mode" >> /opt/spotify-terminal/data/login.log
        echo "No touchscreen, starting in terminal mode..." >> /tmp/spotify-startup.log
        # Check if spotify-client.sh exists
        if [ -f /opt/spotify-terminal/scripts/spotify-client.sh ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting spotify-client.sh" >> /opt/spotify-terminal/data/login.log
            exec /opt/spotify-terminal/scripts/spotify-client.sh 2>> /tmp/spotify-startup.log
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: spotify-client.sh not found!" >> /opt/spotify-terminal/data/login.log
            echo "ERROR: Spotify client script not found at /opt/spotify-terminal/scripts/spotify-client.sh" >> /tmp/spotify-startup.log
            echo "Please check installation. Press any key to continue..."
            read -n 1
        fi
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] User on $(tty) - not tty1, skipping auto-start" >> /opt/spotify-terminal/data/login.log
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
    cat > "$INSTALL_DIR/scripts/start-touchscreen.sh" <<'EOF'
#!/bin/bash

# Minimal X session for touchscreen support
echo "Starting touchscreen session at $(date)" >> /tmp/spotify-touch.log

# Set display
export DISPLAY=:0

# Configure touchscreen input
xinput set-prop "$(xinput list --name-only | grep -i touch | head -1)" "libinput Tapping Enabled" 1 2>/dev/null || true

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Hide cursor
unclutter -idle 0.1 &

# Start minimal window manager
openbox &

# Start on-screen keyboard daemon
matchbox-keyboard --daemon &
KEYBOARD_PID=$!
echo "Started on-screen keyboard (PID: $KEYBOARD_PID)" >> /tmp/spotify-touch.log

# Start ncspot in a terminal with touch support
echo "Starting ncspot with touch interface..." >> /tmp/spotify-touch.log

# Create a simple touch wrapper for ncspot using Python and GTK
python3 /opt/spotify-terminal/scripts/spotify-touch-gui.py &

# Wait for GUI
wait
EOF
    
    chmod +x "$INSTALL_DIR/scripts/start-touchscreen.sh"
    
    # Create Python touch GUI for ncspot
    cat > "$INSTALL_DIR/scripts/spotify-touch-gui.py" <<'EOF'
#!/usr/bin/env python3

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib
import subprocess
import os
import signal
import sys
import threading
import time
import json
import dbus

class SpotifyTouchGUI(Gtk.Window):
    def __init__(self):
        super().__init__(title="Spotify Kids Manager")
        self.fullscreen()
        self.connect("destroy", self.on_quit)
        
        # Check device lock status FIRST
        self.locked = os.path.exists("/opt/spotify-terminal/data/device.lock")
        
        # Initialize backend detection
        self.backend = self.detect_backend()
        
        # Start backend service
        self.start_backend()
        
        # Create UI
        self.setup_ui()
        
        # Initialize Bluetooth
        self.init_bluetooth()
        
        # Update status periodically
        GLib.timeout_add(5000, self.update_status)
        
    def detect_backend(self):
        """Detect which Spotify backend is available"""
        if os.path.exists("/etc/default/raspotify"):
            return "raspotify"
        elif os.path.exists("/usr/local/bin/spotifyd"):
            return "spotifyd"
        elif subprocess.run(["which", "ncspot"], capture_output=True).returncode == 0:
            return "ncspot"
        return None
        
    def start_backend(self):
        """Start the appropriate Spotify backend"""
        try:
            with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Touch GUI starting backend: {self.backend}\n")
            
            if self.backend == "raspotify":
                # Start raspotify service
                subprocess.run(["sudo", "systemctl", "start", "raspotify"], capture_output=True)
                time.sleep(2)
            elif self.backend == "spotifyd":
                # Start spotifyd daemon
                subprocess.Popen(["/usr/local/bin/spotifyd", "--no-daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                time.sleep(2)
            elif self.backend == "ncspot":
                # ncspot will be started when needed for commands
                pass
                
        except Exception as e:
            print(f"Error starting backend: {e}")
            
    def setup_ui(self):
        # Main container
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(main_box)
        
        # Header
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header_box.set_size_request(-1, 100)
        header_box.get_style_context().add_class("header")
        main_box.pack_start(header_box, False, False, 0)
        
        # Title
        title_label = Gtk.Label()
        title_label.set_markup("<span size='xx-large' weight='bold'>🎵 Spotify Kids</span>")
        header_box.pack_start(title_label, False, False, 20)
        
        # Status indicator
        self.status_label = Gtk.Label()
        self.update_status_label()
        header_box.pack_end(self.status_label, False, False, 20)
        
        # Tab bar
        tab_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        tab_bar.set_size_request(-1, 80)
        tab_bar.get_style_context().add_class("tab-bar")
        main_box.pack_start(tab_bar, False, False, 0)
        
        # Tab buttons
        tabs = [
            ("🎵 Now Playing", self.show_now_playing),
            ("📚 Playlists", self.show_playlists),
            ("🔍 Search", self.show_search),
            ("🎨 Albums", self.show_albums),
            ("🎤 Artists", self.show_artists),
            ("🔊 Bluetooth", self.show_bluetooth)
        ]
        
        self.tab_buttons = []
        for label, callback in tabs:
            btn = Gtk.Button(label=label)
            btn.connect("clicked", lambda x, cb=callback: self.switch_tab(cb))
            btn.get_style_context().add_class("tab-button")
            tab_bar.pack_start(btn, True, True, 2)
            self.tab_buttons.append(btn)
        
        # Content area with stack for different views
        self.content_stack = Gtk.Stack()
        self.content_stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        main_box.pack_start(self.content_stack, True, True, 0)
        
        # Create different views
        self.create_now_playing_view()
        self.create_playlists_view()
        self.create_search_view()
        self.create_albums_view()
        self.create_artists_view()
        self.create_bluetooth_view()
        
        # Show now playing by default
        self.show_now_playing()
        
        # Exit button (only if not locked)
        if not self.locked:
            exit_btn = Gtk.Button(label="Exit")
            exit_btn.connect("clicked", self.on_quit)
            exit_btn.get_style_context().add_class("exit-button")
            main_box.pack_start(exit_btn, False, False, 10)
        
        # Apply CSS styling
        self.apply_css()
        
    def create_now_playing_view(self):
        """Create the now playing view"""
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.set_spacing(20)
        
        # Album art placeholder
        art_frame = Gtk.Frame()
        art_frame.set_size_request(400, 400)
        art_frame.get_style_context().add_class("album-art")
        self.album_art = Gtk.Image()
        self.album_art.set_from_icon_name("media-optical", Gtk.IconSize.DIALOG)
        art_frame.add(self.album_art)
        
        # Center the album art
        art_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        art_box.pack_start(Gtk.Label(), True, True, 0)
        art_box.pack_start(art_frame, False, False, 0)
        art_box.pack_start(Gtk.Label(), True, True, 0)
        box.pack_start(art_box, False, False, 20)
        
        # Track info
        self.track_label = Gtk.Label()
        self.track_label.set_markup("<span size='x-large' weight='bold'>No track playing</span>")
        box.pack_start(self.track_label, False, False, 10)
        
        self.artist_label = Gtk.Label()
        self.artist_label.set_markup("<span size='large'>Select something to play</span>")
        box.pack_start(self.artist_label, False, False, 5)
        
        # Progress bar
        self.progress_bar = Gtk.ProgressBar()
        self.progress_bar.set_size_request(-1, 30)
        box.pack_start(self.progress_bar, False, False, 20)
        
        # Control buttons
        controls = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        controls.set_spacing(20)
        controls.set_halign(Gtk.Align.CENTER)
        
        # Shuffle button
        shuffle_btn = Gtk.Button(label="🔀")
        shuffle_btn.connect("clicked", lambda x: self.send_command("shuffle"))
        shuffle_btn.get_style_context().add_class("control-button")
        controls.pack_start(shuffle_btn, False, False, 0)
        
        # Previous
        prev_btn = Gtk.Button(label="⏮")
        prev_btn.connect("clicked", lambda x: self.send_command("previous"))
        prev_btn.get_style_context().add_class("control-button")
        controls.pack_start(prev_btn, False, False, 0)
        
        # Play/Pause
        self.play_btn = Gtk.Button(label="▶")
        self.play_btn.connect("clicked", lambda x: self.send_command("playpause"))
        self.play_btn.get_style_context().add_class("control-button-primary")
        controls.pack_start(self.play_btn, False, False, 0)
        
        # Next
        next_btn = Gtk.Button(label="⏭")
        next_btn.connect("clicked", lambda x: self.send_command("next"))
        next_btn.get_style_context().add_class("control-button")
        controls.pack_start(next_btn, False, False, 0)
        
        # Repeat button
        repeat_btn = Gtk.Button(label="🔁")
        repeat_btn.connect("clicked", lambda x: self.send_command("repeat"))
        repeat_btn.get_style_context().add_class("control-button")
        controls.pack_start(repeat_btn, False, False, 0)
        
        box.pack_start(controls, False, False, 20)
        
        # Volume control
        volume_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        volume_box.set_spacing(10)
        volume_box.set_halign(Gtk.Align.CENTER)
        volume_box.set_size_request(600, -1)
        
        volume_label = Gtk.Label(label="🔊")
        volume_box.pack_start(volume_label, False, False, 10)
        
        self.volume_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self.volume_scale.set_range(0, 100)
        self.volume_scale.set_value(70)
        self.volume_scale.set_draw_value(True)
        self.volume_scale.connect("value-changed", self.on_volume_changed)
        volume_box.pack_start(self.volume_scale, True, True, 10)
        
        box.pack_start(volume_box, False, False, 20)
        
        self.content_stack.add_named(box, "now_playing")
        
    def create_playlists_view(self):
        """Create the playlists view"""
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        
        self.playlists_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.playlists_box.set_spacing(10)
        scrolled.add(self.playlists_box)
        
        # Add loading message
        loading = Gtk.Label(label="Loading playlists...")
        loading.get_style_context().add_class("loading")
        self.playlists_box.pack_start(loading, False, False, 20)
        
        self.content_stack.add_named(scrolled, "playlists")
        
    def create_search_view(self):
        """Create the search view"""
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.set_spacing(20)
        
        # Search box
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        search_box.set_margin_start(20)
        search_box.set_margin_end(20)
        search_box.set_margin_top(20)
        
        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text("Search for songs, artists, or albums...")
        self.search_entry.connect("activate", self.on_search)
        self.search_entry.connect("focus-in-event", self.show_keyboard)
        self.search_entry.get_style_context().add_class("search-entry")
        search_box.pack_start(self.search_entry, True, True, 10)
        
        search_btn = Gtk.Button(label="🔍 Search")
        search_btn.connect("clicked", lambda x: self.on_search(None))
        search_btn.get_style_context().add_class("search-button")
        search_box.pack_start(search_btn, False, False, 10)
        
        box.pack_start(search_box, False, False, 0)
        
        # Search results
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        
        self.search_results = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.search_results.set_spacing(5)
        scrolled.add(self.search_results)
        
        box.pack_start(scrolled, True, True, 10)
        
        self.content_stack.add_named(box, "search")
        
    def create_albums_view(self):
        """Create the albums view"""
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        
        self.albums_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.albums_box.set_spacing(10)
        scrolled.add(self.albums_box)
        
        # Add loading message
        loading = Gtk.Label(label="Loading albums...")
        loading.get_style_context().add_class("loading")
        self.albums_box.pack_start(loading, False, False, 20)
        
        self.content_stack.add_named(scrolled, "albums")
        
    def create_artists_view(self):
        """Create the artists view"""
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        
        self.artists_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.artists_box.set_spacing(10)
        scrolled.add(self.artists_box)
        
        # Add loading message
        loading = Gtk.Label(label="Loading artists...")
        loading.get_style_context().add_class("loading")
        self.artists_box.pack_start(loading, False, False, 20)
        
        self.content_stack.add_named(scrolled, "artists")
        
    def create_bluetooth_view(self):
        """Create the Bluetooth devices view"""
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        box.set_spacing(20)
        
        # Header
        header = Gtk.Label()
        header.set_markup("<span size='large' weight='bold'>Bluetooth Audio Devices</span>")
        box.pack_start(header, False, False, 20)
        
        # Scan button
        scan_btn = Gtk.Button(label="🔍 Scan for Devices")
        scan_btn.connect("clicked", self.scan_bluetooth)
        scan_btn.get_style_context().add_class("scan-button")
        box.pack_start(scan_btn, False, False, 10)
        
        # Device list
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        
        self.bluetooth_list = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.bluetooth_list.set_spacing(5)
        scrolled.add(self.bluetooth_list)
        
        box.pack_start(scrolled, True, True, 10)
        
        self.content_stack.add_named(box, "bluetooth")
        
        # Load current devices
        self.refresh_bluetooth_devices()
        
    def apply_css(self):
        """Apply CSS styling for touch-friendly interface"""
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(b"""
            window {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            }
            .header {
                background: rgba(255, 255, 255, 0.95);
                padding: 20px;
                border-radius: 0 0 20px 20px;
            }
            .tab-bar {
                background: rgba(255, 255, 255, 0.9);
                padding: 10px;
            }
            .tab-button {
                font-size: 18px;
                min-height: 60px;
                background: transparent;
                border: 2px solid transparent;
                border-radius: 10px;
                margin: 2px;
            }
            .tab-button:hover {
                background: rgba(102, 126, 234, 0.1);
                border-color: #667eea;
            }
            .tab-button:active {
                background: rgba(102, 126, 234, 0.2);
            }
            .control-button {
                font-size: 36px;
                min-height: 80px;
                min-width: 80px;
                background: rgba(255, 255, 255, 0.9);
                border: 2px solid #667eea;
                border-radius: 50%;
                margin: 5px;
            }
            .control-button:hover {
                background: #667eea;
                color: white;
            }
            .control-button-primary {
                font-size: 48px;
                min-height: 100px;
                min-width: 100px;
                background: #1db954;
                color: white;
                border: none;
                border-radius: 50%;
                margin: 5px;
            }
            .control-button-primary:hover {
                background: #1ed760;
            }
            .search-entry {
                font-size: 20px;
                min-height: 60px;
                padding: 10px;
                border-radius: 30px;
                border: 2px solid #667eea;
            }
            .search-button {
                font-size: 18px;
                min-height: 60px;
                padding: 0 30px;
                background: #667eea;
                color: white;
                border-radius: 30px;
            }
            .playlist-item, .album-item, .artist-item, .search-result {
                background: rgba(255, 255, 255, 0.95);
                padding: 20px;
                margin: 5px 20px;
                border-radius: 10px;
                font-size: 18px;
            }
            .playlist-item:hover, .album-item:hover, .artist-item:hover, .search-result:hover {
                background: white;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            }
            .bluetooth-device {
                background: rgba(255, 255, 255, 0.95);
                padding: 20px;
                margin: 5px 20px;
                border-radius: 10px;
                font-size: 16px;
            }
            .bluetooth-device:hover {
                background: white;
            }
            .connected {
                border-left: 5px solid #1db954;
            }
            .scan-button {
                font-size: 20px;
                min-height: 60px;
                padding: 0 40px;
                background: #667eea;
                color: white;
                border-radius: 30px;
            }
            .album-art {
                background: white;
                border-radius: 20px;
                padding: 20px;
            }
            .loading {
                font-size: 24px;
                color: #666;
                padding: 40px;
            }
            .exit-button {
                background: #ef4444;
                color: white;
                font-size: 18px;
                min-height: 50px;
                margin: 10px;
                border-radius: 10px;
            }
            .exit-button:hover {
                background: #dc2626;
            }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        
    def switch_tab(self, callback):
        """Switch to a different tab"""
        callback()
        
    def show_now_playing(self):
        """Show the now playing view"""
        self.content_stack.set_visible_child_name("now_playing")
        self.update_now_playing()
        
    def show_playlists(self):
        """Show and load playlists"""
        self.content_stack.set_visible_child_name("playlists")
        self.load_playlists()
        
    def show_search(self):
        """Show the search view"""
        self.content_stack.set_visible_child_name("search")
        self.search_entry.grab_focus()
        
    def show_albums(self):
        """Show and load albums"""
        self.content_stack.set_visible_child_name("albums")
        self.load_albums()
        
    def show_artists(self):
        """Show and load artists"""
        self.content_stack.set_visible_child_name("artists")
        self.load_artists()
        
    def show_bluetooth(self):
        """Show Bluetooth devices"""
        self.content_stack.set_visible_child_name("bluetooth")
        self.refresh_bluetooth_devices()
        
    def send_command(self, command):
        """Send command to Spotify backend"""
        try:
            if self.backend == "ncspot":
                # Use ncspot's IPC
                subprocess.run(["ncspot", command], capture_output=True)
            elif self.backend == "raspotify" or self.backend == "spotifyd":
                # Use playerctl or dbus for Spotify Connect
                subprocess.run(["playerctl", command], capture_output=True)
        except Exception as e:
            print(f"Error sending command: {e}")
            
    def load_playlists(self):
        """Load user's playlists"""
        # Clear existing items
        for child in self.playlists_box.get_children():
            child.destroy()
            
        # This would normally fetch from Spotify API
        # For now, show sample playlists
        playlists = [
            "Kids Favorites",
            "Disney Hits",
            "Bedtime Songs",
            "Dance Party",
            "Sing Along",
            "Movie Soundtracks"
        ]
        
        for playlist in playlists:
            item = Gtk.Button(label=f"📚 {playlist}")
            item.get_style_context().add_class("playlist-item")
            item.connect("clicked", lambda x, p=playlist: self.play_playlist(p))
            self.playlists_box.pack_start(item, False, False, 0)
            
        self.playlists_box.show_all()
        
    def load_albums(self):
        """Load saved albums"""
        # Clear existing items
        for child in self.albums_box.get_children():
            child.destroy()
            
        # Sample albums
        albums = [
            "Frozen Soundtrack",
            "Moana Soundtrack",
            "The Lion King",
            "Encanto",
            "Sing 2"
        ]
        
        for album in albums:
            item = Gtk.Button(label=f"💿 {album}")
            item.get_style_context().add_class("album-item")
            item.connect("clicked", lambda x, a=album: self.play_album(a))
            self.albums_box.pack_start(item, False, False, 0)
            
        self.albums_box.show_all()
        
    def load_artists(self):
        """Load followed artists"""
        # Clear existing items
        for child in self.artists_box.get_children():
            child.destroy()
            
        # Sample artists
        artists = [
            "Disney",
            "Kidz Bop",
            "The Wiggles",
            "Cocomelon",
            "Super Simple Songs"
        ]
        
        for artist in artists:
            item = Gtk.Button(label=f"🎤 {artist}")
            item.get_style_context().add_class("artist-item")
            item.connect("clicked", lambda x, a=artist: self.play_artist(a))
            self.artists_box.pack_start(item, False, False, 0)
            
        self.artists_box.show_all()
        
    def on_search(self, widget):
        """Perform search"""
        query = self.search_entry.get_text().strip()
        if not query:
            return
            
        # Clear previous results
        for child in self.search_results.get_children():
            child.destroy()
            
        # Show loading
        loading = Gtk.Label(label="Searching...")
        loading.get_style_context().add_class("loading")
        self.search_results.pack_start(loading, False, False, 20)
        self.search_results.show_all()
        
        # This would normally search Spotify
        # For now, show sample results
        GLib.timeout_add(500, lambda: self.show_search_results(query))
        
    def show_search_results(self, query):
        """Display search results"""
        # Clear loading message
        for child in self.search_results.get_children():
            child.destroy()
            
        # Sample results
        results = [
            f"🎵 Song: {query} - Artist Name",
            f"💿 Album: {query} Album",
            f"🎤 Artist: {query}",
            f"📚 Playlist: {query} Mix"
        ]
        
        for result in results:
            item = Gtk.Button(label=result)
            item.get_style_context().add_class("search-result")
            item.connect("clicked", lambda x, r=result: self.play_search_result(r))
            self.search_results.pack_start(item, False, False, 0)
            
        self.search_results.show_all()
        return False
        
    def init_bluetooth(self):
        """Initialize Bluetooth support"""
        try:
            self.bus = dbus.SystemBus()
        except:
            self.bus = None
            
    def refresh_bluetooth_devices(self):
        """Refresh list of Bluetooth devices"""
        # Clear existing items
        for child in self.bluetooth_list.get_children():
            child.destroy()
            
        try:
            # Get paired devices
            result = subprocess.run(["bluetoothctl", "devices"], capture_output=True, text=True)
            
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if "Device" in line:
                        parts = line.split(" ", 2)
                        if len(parts) >= 3:
                            address = parts[1]
                            name = parts[2]
                            
                            # Create device item
                            device_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
                            device_box.get_style_context().add_class("bluetooth-device")
                            
                            # Check if connected
                            info_result = subprocess.run(["bluetoothctl", "info", address], capture_output=True, text=True)
                            connected = "Connected: yes" in info_result.stdout
                            
                            if connected:
                                device_box.get_style_context().add_class("connected")
                            
                            # Device info
                            info_label = Gtk.Label(label=f"🔊 {name}")
                            info_label.set_halign(Gtk.Align.START)
                            device_box.pack_start(info_label, True, True, 10)
                            
                            # Connect/Disconnect button
                            if connected:
                                btn = Gtk.Button(label="Disconnect")
                                btn.connect("clicked", lambda x, a=address: self.disconnect_bluetooth(a))
                            else:
                                btn = Gtk.Button(label="Connect")
                                btn.connect("clicked", lambda x, a=address: self.connect_bluetooth(a))
                            
                            device_box.pack_start(btn, False, False, 10)
                            
                            self.bluetooth_list.pack_start(device_box, False, False, 0)
            else:
                label = Gtk.Label(label="No Bluetooth devices found")
                self.bluetooth_list.pack_start(label, False, False, 20)
                
        except Exception as e:
            label = Gtk.Label(label=f"Error: {e}")
            self.bluetooth_list.pack_start(label, False, False, 20)
            
        self.bluetooth_list.show_all()
        
    def scan_bluetooth(self, widget):
        """Scan for new Bluetooth devices"""
        # Show scanning message
        for child in self.bluetooth_list.get_children():
            child.destroy()
            
        label = Gtk.Label(label="Scanning for devices...")
        label.get_style_context().add_class("loading")
        self.bluetooth_list.pack_start(label, False, False, 20)
        self.bluetooth_list.show_all()
        
        # Start scan in background
        def scan():
            subprocess.run(["bluetoothctl", "scan", "on"], capture_output=True, timeout=10)
            GLib.idle_add(self.refresh_bluetooth_devices)
            
        thread = threading.Thread(target=scan)
        thread.daemon = True
        thread.start()
        
    def connect_bluetooth(self, address):
        """Connect to a Bluetooth device"""
        try:
            subprocess.run(["bluetoothctl", "connect", address], capture_output=True)
            GLib.timeout_add(2000, self.refresh_bluetooth_devices)
        except Exception as e:
            print(f"Error connecting: {e}")
            
    def disconnect_bluetooth(self, address):
        """Disconnect from a Bluetooth device"""
        try:
            subprocess.run(["bluetoothctl", "disconnect", address], capture_output=True)
            GLib.timeout_add(1000, self.refresh_bluetooth_devices)
        except Exception as e:
            print(f"Error disconnecting: {e}")
            
    def show_keyboard(self, widget, event):
        """Show on-screen keyboard for text input"""
        try:
            subprocess.Popen(["matchbox-keyboard"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except:
            pass
        return False
        
    def update_status_label(self):
        """Update the status label"""
        if self.backend:
            self.status_label.set_markup(f"<span size='medium'>✓ {self.backend} ready</span>")
        else:
            self.status_label.set_markup("<span size='medium' color='red'>✗ No backend</span>")
            
    def update_status(self):
        """Update various status indicators"""
        self.update_now_playing()
        return True
        
    def update_now_playing(self):
        """Update now playing information"""
        try:
            # Try to get current track info
            if self.backend in ["raspotify", "spotifyd"]:
                # Use playerctl for Spotify Connect backends
                title = subprocess.run(["playerctl", "metadata", "title"], capture_output=True, text=True).stdout.strip()
                artist = subprocess.run(["playerctl", "metadata", "artist"], capture_output=True, text=True).stdout.strip()
                status = subprocess.run(["playerctl", "status"], capture_output=True, text=True).stdout.strip()
                
                if title:
                    self.track_label.set_markup(f"<span size='x-large' weight='bold'>{title}</span>")
                    self.artist_label.set_markup(f"<span size='large'>{artist}</span>")
                    
                if status == "Playing":
                    self.play_btn.set_label("⏸")
                else:
                    self.play_btn.set_label("▶")
        except:
            pass
            
    def on_volume_changed(self, widget):
        """Handle volume change"""
        volume = int(widget.get_value())
        try:
            subprocess.run(["amixer", "sset", "Master", f"{volume}%"], capture_output=True)
        except:
            pass
            
    def play_playlist(self, playlist):
        """Play a playlist"""
        print(f"Playing playlist: {playlist}")
        # This would normally use Spotify API to play the playlist
        
    def play_album(self, album):
        """Play an album"""
        print(f"Playing album: {album}")
        
    def play_artist(self, artist):
        """Play artist's top tracks"""
        print(f"Playing artist: {artist}")
        
    def play_search_result(self, result):
        """Play a search result"""
        print(f"Playing: {result}")
        
    def on_quit(self, widget=None):
        """Quit the application"""
        if not self.locked:
            Gtk.main_quit()
            
def main():
    app = SpotifyTouchGUI()
    app.show_all()
    
    # Trap signals if locked
    if app.locked:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        
    Gtk.main()
    
if __name__ == "__main__":
    main()EOF
    
    chmod +x "$INSTALL_DIR/scripts/spotify-touch-gui.py"
    
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

# Setup web admin panel
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
            <div class="card">
                <h2>Spotify Account</h2>
                <div id="spotifyStatus">
                    <p>Loading...</p>
                </div>
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
                    <button type="submit" class="btn success">Configure Spotify</button>
                </form>
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
                        ${user.spotify_username ? `<span style="color: #1db954; margin-left: 10px;">♪ ${user.spotify_username}</span>` : 
                          (user.spotify_configured ? '<span style="color: orange; margin-left: 10px;">♪ Not logged in</span>' : '')}
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
            if (config.configured) {
                statusDiv.innerHTML = `
                    <p style="color: green;">✓ Configured for: <strong>${config.username}</strong></p>
                    <p style="color: #666; font-size: 12px;">Using: ${config.backend}</p>
                `;
                document.getElementById('spotifyUsername').value = config.username;
            } else {
                statusDiv.innerHTML = `
                    <p style="color: red;">✗ Not configured</p>
                    <p style="color: #666; font-size: 12px;">Please enter your Spotify credentials</p>
                `;
            }
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
        result = subprocess.run(['pgrep', '-f', 'ncspot'], capture_output=True)
        if result.returncode == 0:
            logs["status"] = "running"
        else:
            logs["status"] = "not_running"
    except:
        pass
    
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

@app.route('/api/spotify/config', methods=['GET'])
@login_required
def get_spotify_config():
    # Get current Spotify configuration
    config_file = "/home/spotify-kids/.config/ncspot/config.toml"
    spotifyd_config = "/home/spotify-kids/.config/spotifyd/spotifyd.conf"
    raspotify_config = "/etc/default/raspotify"
    
    spotify_config = {
        "configured": False,
        "username": "",
        "backend": "ncspot"
    }
    
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
                            'spotify_username': spotify_username,
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
    
    chmod +x "$INSTALL_DIR/web/app.py"
    
    log_success "Web admin panel created"
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
            log_info "Installing/verifying Python dependencies..."
            pip3 install --break-system-packages flask flask-cors flask-socketio werkzeug python-dotenv dbus-python pulsectl 2>/dev/null || \
            pip3 install flask flask-cors flask-socketio werkzeug python-dotenv dbus-python pulsectl 2>/dev/null || \
            python3 -m pip install flask flask-cors flask-socketio werkzeug python-dotenv dbus-python pulsectl 2>/dev/null
            
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
                chmod +x "$INSTALL_DIR/web/app.py"
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
    
    # Stop services
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    systemctl stop nginx 2>/dev/null
    
    # Kill all related processes
    pkill -f "app.py" 2>/dev/null || true
    pkill -f "ncspot" 2>/dev/null || true
    pkill -f "spotify-touch-gui" 2>/dev/null || true
    pkill -f "matchbox-keyboard" 2>/dev/null || true
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
    
    # Remove systemd files
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    
    # Remove auto-login configurations for all ttys
    for i in {1..6}; do
        rm -rf "/etc/systemd/system/getty@tty$i.service.d/"
    done
    
    # Remove nginx config
    rm -f /etc/nginx/sites-enabled/spotify-admin
    rm -f /etc/nginx/sites-available/spotify-admin
    
    # Remove all installation directories
    rm -rf "$INSTALL_DIR"
    rm -rf /opt/spotify-terminal
    
    # Remove ncspot configs for all users
    rm -rf /home/*/.config/ncspot
    rm -rf /home/*/.cache/ncspot
    rm -rf /home/*/.cache/spotifyd
    rm -rf /root/.config/ncspot
    rm -rf /root/.cache/ncspot
    
    # Clean up Python packages (optional - commented out to avoid removing system packages)
    # pip3 uninstall -y flask flask-cors flask-socketio werkzeug dbus-python pulsectl 2>/dev/null || true
    
    # Reset default runlevel back to graphical if it was changed
    systemctl set-default graphical.target 2>/dev/null || true
    
    # Reload systemd
    systemctl daemon-reload
    systemctl restart nginx 2>/dev/null
    
    log_success "ALL traces of installation removed"
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
        pkill -f "spotify-touch-gui" 2>/dev/null || true
        pkill -f "matchbox-keyboard" 2>/dev/null || true
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
        pip3 uninstall -y flask flask-cors flask-socketio werkzeug dbus-python pulsectl 2>/dev/null || true
        
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
    setup_web_admin
    create_systemd_service
    create_uninstall_script
    
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