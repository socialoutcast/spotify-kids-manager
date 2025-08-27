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

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || true
chmod 666 "$LOG_FILE" 2>/dev/null || true

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
        echo "Spotify is currently disabled by administrator"
        echo "Please contact your parent to enable it"
        # Keep terminal alive but don't consume CPU
        while true; do
            sleep 3600
        done
    fi
    
    # Start the appropriate client
    if command -v ncspot &> /dev/null; then
        # Use ncspot if available
        if is_locked; then
            # Locked mode - disable quit key
            exec ncspot --config <(cat ~/.config/ncspot/config.toml | sed '/^"q"/d')
        else
            # Unlocked mode - normal operation
            exec ncspot
        fi
    elif command -v spotifyd &> /dev/null; then
        # Use spotifyd with simple UI
        spotifyd --no-daemon --backend alsa &
        exec spotify-tui-simple
    else
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

class SpotifyTouchGUI(Gtk.Window):
    def __init__(self):
        super().__init__(title="Spotify Kids Manager")
        self.fullscreen()
        self.connect("destroy", self.on_quit)
        
        # Check device lock status FIRST
        self.locked = os.path.exists("/opt/spotify-terminal/data/device.lock")
        
        # Start ncspot in background
        self.ncspot_process = None
        self.start_ncspot()
        
        # Create UI (after locked is set)
        self.setup_ui()
        
    def setup_ui(self):
        # Main container
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(main_box)
        
        # Header with now playing info
        header_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        header_box.set_size_request(-1, 150)
        main_box.pack_start(header_box, False, False, 0)
        
        self.now_playing_label = Gtk.Label()
        self.now_playing_label.set_markup("<span size='x-large' weight='bold'>Loading...</span>")
        header_box.pack_start(self.now_playing_label, True, True, 10)
        
        # Control buttons (large for touch)
        control_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        control_box.set_size_request(-1, 200)
        control_box.set_spacing(20)
        control_box.set_margin_start(20)
        control_box.set_margin_end(20)
        main_box.pack_start(control_box, False, False, 20)
        
        # Previous button
        prev_btn = Gtk.Button()
        prev_btn.set_label("⏮")
        prev_btn.get_style_context().add_class("control-button")
        prev_btn.connect("clicked", lambda x: self.send_ncspot_command("previous"))
        control_box.pack_start(prev_btn, True, True, 0)
        
        # Play/Pause button
        self.play_btn = Gtk.Button()
        self.play_btn.set_label("⏸")
        self.play_btn.get_style_context().add_class("control-button")
        self.play_btn.connect("clicked", lambda x: self.send_ncspot_command("playpause"))
        control_box.pack_start(self.play_btn, True, True, 0)
        
        # Next button
        next_btn = Gtk.Button()
        next_btn.set_label("⏭")
        next_btn.get_style_context().add_class("control-button")
        next_btn.connect("clicked", lambda x: self.send_ncspot_command("next"))
        control_box.pack_start(next_btn, True, True, 0)
        
        # Volume control
        volume_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        volume_box.set_size_request(-1, 100)
        volume_box.set_margin_start(20)
        volume_box.set_margin_end(20)
        main_box.pack_start(volume_box, False, False, 10)
        
        volume_label = Gtk.Label(label="Volume: ")
        volume_box.pack_start(volume_label, False, False, 10)
        
        self.volume_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL)
        self.volume_scale.set_range(0, 100)
        self.volume_scale.set_value(50)
        self.volume_scale.set_draw_value(True)
        self.volume_scale.connect("value-changed", self.on_volume_changed)
        volume_box.pack_start(self.volume_scale, True, True, 10)
        
        # Navigation tabs
        tab_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        tab_box.set_size_request(-1, 60)
        tab_box.set_margin_start(20)
        tab_box.set_margin_end(20)
        main_box.pack_start(tab_box, False, False, 10)
        
        playlists_btn = Gtk.Button(label="Playlists")
        playlists_btn.set_size_request(150, 50)
        playlists_btn.connect("clicked", lambda x: self.show_playlists())
        tab_box.pack_start(playlists_btn, False, False, 5)
        
        albums_btn = Gtk.Button(label="Albums")
        albums_btn.set_size_request(150, 50)
        albums_btn.connect("clicked", lambda x: self.show_albums())
        tab_box.pack_start(albums_btn, False, False, 5)
        
        artists_btn = Gtk.Button(label="Artists")
        artists_btn.set_size_request(150, 50)
        artists_btn.connect("clicked", lambda x: self.show_artists())
        tab_box.pack_start(artists_btn, False, False, 5)
        
        search_btn = Gtk.Button(label="Search")
        search_btn.set_size_request(150, 50)
        search_btn.connect("clicked", lambda x: self.show_search())
        tab_box.pack_start(search_btn, False, False, 5)
        
        # Search section (initially hidden)
        self.search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.search_box.set_size_request(-1, 80)
        self.search_box.set_margin_start(20)
        self.search_box.set_margin_end(20)
        main_box.pack_start(self.search_box, False, False, 10)
        
        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text("Search for music...")
        self.search_entry.connect("activate", self.on_search)
        self.search_entry.connect("focus-in-event", self.show_keyboard)
        self.search_box.pack_start(self.search_entry, True, True, 10)
        
        do_search_btn = Gtk.Button(label="Go")
        do_search_btn.connect("clicked", lambda x: self.on_search(None))
        self.search_box.pack_start(do_search_btn, False, False, 10)
        
        self.search_box.hide()  # Hide by default
        
        # Results/content area with scrolling
        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        main_box.pack_start(scrolled, True, True, 10)
        
        self.content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.content_box.set_spacing(10)
        scrolled.add(self.content_box)
        
        # Load playlists on startup
        self.show_playlists()
        
        # Exit button (only show if not locked)
        if not self.locked:
            exit_btn = Gtk.Button(label="Exit")
            exit_btn.connect("clicked", self.on_quit)
            main_box.pack_start(exit_btn, False, False, 10)
        
        # Apply CSS for touch-friendly styling
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data(b"""
            .control-button {
                font-size: 48px;
                min-height: 150px;
                min-width: 150px;
                background: #1db954;
                color: white;
                border-radius: 10px;
            }
            .control-button:hover {
                background: #1ed760;
            }
            GtkEntry {
                font-size: 24px;
                min-height: 60px;
                padding: 10px;
                border-radius: 5px;
            }
            GtkButton {
                font-size: 20px;
                min-height: 60px;
                padding: 10px;
                background: #f0f0f0;
                border: 1px solid #ccc;
                border-radius: 5px;
                margin: 2px;
            }
            GtkButton:hover {
                background: #e0e0e0;
            }
            GtkButton:active {
                background: #d0d0d0;
            }
            GtkLabel {
                font-size: 18px;
                padding: 5px;
            }
            #loading {
                font-size: 24px;
                color: #666;
            }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )
        
    def start_ncspot(self):
        """Start ncspot in background with IPC enabled"""
        try:
            # Log Spotify authentication attempt
            with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Starting ncspot for user {os.environ.get('USER', 'unknown')}\n")
            
            # Kill any existing ncspot instances
            subprocess.run(["pkill", "-f", "ncspot"], capture_output=True)
            time.sleep(1)
            
            # Check if ncspot config exists
            config_path = f"/home/{os.environ.get('USER', 'spotify-kids')}/.config/ncspot/config.toml"
            if os.path.exists(config_path):
                with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                    f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Found ncspot config at {config_path}\n")
                # Try to extract username
                try:
                    with open(config_path, 'r') as cfg:
                        for line in cfg:
                            if 'username' in line:
                                with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                                    f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Config contains: {line.strip()}\n")
                                break
                except Exception as e:
                    with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                        f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Error reading config: {e}\n")
            else:
                with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                    f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] No ncspot config found at {config_path}\n")
            
            # Start ncspot with IPC socket
            self.ncspot_process = subprocess.Popen(
                ["ncspot", "--ipc-socket", "/tmp/ncspot.sock"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            
            with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ncspot process started with PID {self.ncspot_process.pid}\n")
            
            # Give it time to start
            time.sleep(3)
            
            # Check if authentication succeeded by monitoring stderr
            threading.Thread(target=self.monitor_ncspot_auth, daemon=True).start()
            
            # Start status update thread
            self.update_thread = threading.Thread(target=self.update_status_loop, daemon=True)
            self.update_thread.start()
            
        except Exception as e:
            with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Failed to start ncspot: {e}\n")
            print(f"Failed to start ncspot: {e}")
    
    def monitor_ncspot_auth(self):
        """Monitor ncspot stderr for authentication messages"""
        try:
            for line in self.ncspot_process.stderr:
                line_str = line.decode('utf-8', errors='ignore')
                with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                    f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] ncspot: {line_str}")
                # Check for authentication errors
                if "authentication" in line_str.lower() or "login" in line_str.lower() or "error" in line_str.lower():
                    with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                        f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] AUTH EVENT: {line_str}")
        except Exception as e:
            with open("/opt/spotify-terminal/data/spotify-auth.log", "a") as f:
                f.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Monitor error: {e}\n")
            
    def send_ncspot_command(self, command):
        """Send command to ncspot via IPC"""
        try:
            subprocess.run(
                ["ncspot", "send", command, "--socket", "/tmp/ncspot.sock"],
                capture_output=True,
                timeout=2
            )
        except Exception as e:
            print(f"Failed to send command: {e}")
            
    def on_volume_changed(self, scale):
        """Handle volume changes"""
        volume = int(scale.get_value())
        try:
            subprocess.run(["amixer", "set", "Master", f"{volume}%"], capture_output=True)
        except:
            pass
            
    def show_keyboard(self, widget, event):
        """Show on-screen keyboard when text field is focused"""
        try:
            subprocess.Popen(["matchbox-keyboard"])
        except:
            pass
        return False
        
    def show_playlists(self):
        """Show user's playlists"""
        self.search_box.hide()
        self.clear_content()
        
        # Add loading message
        loading_label = Gtk.Label(label="Loading playlists...")
        loading_label.set_name("loading")
        self.content_box.pack_start(loading_label, False, False, 10)
        self.content_box.show_all()
        
        # Send command to ncspot to navigate to playlists
        self.send_ncspot_command("focus playlists")
        
        # Simulate playlist items (in real implementation, parse ncspot output)
        GLib.timeout_add(500, self.load_playlists)
    
    def load_playlists(self):
        """Load playlists from ncspot"""
        self.clear_content()
        
        # Example playlists - in real implementation, get from ncspot
        playlists = [
            "Liked Songs",
            "Kids Music",
            "Disney Favorites",
            "Bedtime Songs",
            "Morning Playlist"
        ]
        
        for playlist in playlists:
            item_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
            item_box.set_size_request(-1, 80)
            
            # Playlist button
            btn = Gtk.Button(label=playlist)
            btn.set_size_request(-1, 70)
            btn.connect("clicked", lambda x, p=playlist: self.open_playlist(p))
            item_box.pack_start(btn, True, True, 5)
            
            # Play button
            play_btn = Gtk.Button(label="▶")
            play_btn.set_size_request(70, 70)
            play_btn.connect("clicked", lambda x, p=playlist: self.play_playlist(p))
            item_box.pack_start(play_btn, False, False, 5)
            
            self.content_box.pack_start(item_box, False, False, 5)
        
        self.content_box.show_all()
        return False  # Don't repeat
    
    def open_playlist(self, playlist_name):
        """Open a specific playlist"""
        self.clear_content()
        
        # Show back button
        back_btn = Gtk.Button(label="← Back to Playlists")
        back_btn.set_size_request(-1, 60)
        back_btn.connect("clicked", lambda x: self.show_playlists())
        self.content_box.pack_start(back_btn, False, False, 10)
        
        # Show playlist name
        title_label = Gtk.Label(label=playlist_name)
        title_label.set_markup(f"<span size='x-large' weight='bold'>{playlist_name}</span>")
        self.content_box.pack_start(title_label, False, False, 10)
        
        # Play all button
        play_all_btn = Gtk.Button(label="▶ Play All")
        play_all_btn.set_size_request(-1, 60)
        play_all_btn.connect("clicked", lambda x: self.play_playlist(playlist_name))
        self.content_box.pack_start(play_all_btn, False, False, 10)
        
        # Example tracks - in real implementation, get from ncspot
        tracks = [
            "Song 1 - Artist A",
            "Song 2 - Artist B",
            "Song 3 - Artist C",
            "Song 4 - Artist D"
        ]
        
        for i, track in enumerate(tracks):
            track_btn = Gtk.Button(label=track)
            track_btn.set_size_request(-1, 60)
            track_btn.connect("clicked", lambda x, t=track, idx=i: self.play_track(playlist_name, idx))
            self.content_box.pack_start(track_btn, False, False, 5)
        
        self.content_box.show_all()
    
    def play_playlist(self, playlist_name):
        """Play entire playlist"""
        self.send_ncspot_command(f"play {playlist_name}")
        # Update now playing label
        self.now_playing_label.set_markup(f"<span size='x-large' weight='bold'>Playing: {playlist_name}</span>")
    
    def play_track(self, playlist_name, track_index):
        """Play specific track from playlist"""
        self.send_ncspot_command(f"play {track_index}")
    
    def show_albums(self):
        """Show saved albums"""
        self.search_box.hide()
        self.clear_content()
        
        loading_label = Gtk.Label(label="Loading albums...")
        self.content_box.pack_start(loading_label, False, False, 10)
        self.content_box.show_all()
        
        # Send command to ncspot
        self.send_ncspot_command("focus albums")
        
        # TODO: Parse ncspot output for actual albums
        GLib.timeout_add(500, lambda: self.show_placeholder("Albums"))
    
    def show_artists(self):
        """Show followed artists"""
        self.search_box.hide()
        self.clear_content()
        
        loading_label = Gtk.Label(label="Loading artists...")
        self.content_box.pack_start(loading_label, False, False, 10)
        self.content_box.show_all()
        
        # Send command to ncspot
        self.send_ncspot_command("focus artists")
        
        # TODO: Parse ncspot output for actual artists
        GLib.timeout_add(500, lambda: self.show_placeholder("Artists"))
    
    def show_search(self):
        """Show search interface"""
        self.clear_content()
        self.search_box.show()
        self.search_entry.grab_focus()
    
    def show_placeholder(self, content_type):
        """Show placeholder for unimplemented sections"""
        self.clear_content()
        label = Gtk.Label(label=f"{content_type} will be displayed here")
        self.content_box.pack_start(label, False, False, 10)
        self.content_box.show_all()
        return False
    
    def clear_content(self):
        """Clear the content area"""
        for child in self.content_box.get_children():
            self.content_box.remove(child)
    
    def on_search(self, widget):
        """Handle search"""
        query = self.search_entry.get_text().strip()
        if not query:
            return
            
        self.clear_content()
        
        # Send search to ncspot
        self.send_ncspot_command(f"search {query}")
        
        # Show search results
        label = Gtk.Label(label=f"Search results for: {query}")
        self.content_box.pack_start(label, False, False, 5)
        
        # TODO: Parse actual search results from ncspot
        results = [
            f"Track: {query} Song 1",
            f"Track: {query} Song 2",
            f"Album: {query} Album",
            f"Artist: {query} Artist"
        ]
        
        for result in results:
            result_btn = Gtk.Button(label=result)
            result_btn.set_size_request(-1, 60)
            result_btn.connect("clicked", lambda x, r=result: self.play_search_result(r))
            self.content_box.pack_start(result_btn, False, False, 5)
        
        self.content_box.show_all()
    
    def play_search_result(self, result):
        """Play a search result"""
        self.send_ncspot_command("play")
        self.now_playing_label.set_markup(f"<span size='x-large' weight='bold'>Playing: {result}</span>")
        
    def update_status_loop(self):
        """Update now playing info periodically"""
        while True:
            try:
                # Try to get status from ncspot
                result = subprocess.run(
                    ["ncspot", "send", "status", "--socket", "/tmp/ncspot.sock"],
                    capture_output=True,
                    text=True,
                    timeout=2
                )
                
                if result.returncode == 0:
                    # Parse and update UI
                    GLib.idle_add(self.update_now_playing, result.stdout)
                    
            except:
                pass
                
            time.sleep(2)
            
    def update_now_playing(self, status):
        """Update the now playing label"""
        # This would parse the actual ncspot status
        # For now, just show something
        self.now_playing_label.set_markup("<span size='x-large' weight='bold'>Spotify Music Player</span>")
        
    def on_quit(self, widget=None):
        """Clean shutdown"""
        if self.ncspot_process:
            self.ncspot_process.terminate()
            try:
                self.ncspot_process.wait(timeout=5)
            except:
                self.ncspot_process.kill()
        Gtk.main_quit()
        
def main():
    # Handle signals
    signal.signal(signal.SIGINT, lambda x, y: Gtk.main_quit())
    
    # Create and show window
    window = SpotifyTouchGUI()
    window.show_all()
    
    # Start GTK main loop
    Gtk.main()
    
if __name__ == "__main__":
    main()
EOF
    
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
    
    spotify_config = {
        "configured": False,
        "username": "",
        "backend": "ncspot"
    }
    
    # Check ncspot config
    if os.path.exists(config_file):
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
    if os.path.exists(spotifyd_config):
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
                                            spotify_username = line.split('=')[1].strip()
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
    if os.path.exists("/usr/local/bin/spotifyd"):
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