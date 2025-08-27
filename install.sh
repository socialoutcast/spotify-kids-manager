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
        xinit \
        x11-xserver-utils \
        openbox \
        rxvt-unicode \
        fonts-dejavu-core \
        nginx \
        cargo \
        build-essential \
        libasound2-dev \
        libssl-dev \
        libdbus-1-dev \
        pkg-config
    
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
    log_info "Installing ncspot (this may take a few minutes)..."
    
    # Check if ncspot is already installed
    if command -v ncspot &> /dev/null; then
        log_success "ncspot is already installed"
        return 0
    fi
    
    # Try to install from cargo
    if command -v cargo &> /dev/null; then
        log_info "Building ncspot from source with cargo..."
        
        # Install using cargo (for the spotify-kids user)
        sudo -u "$SPOTIFY_USER" cargo install ncspot --no-default-features --features alsa_backend 2>/dev/null || \
        cargo install ncspot --no-default-features --features alsa_backend || {
            log_warning "Cargo installation failed, trying alternative..."
            
            # Alternative: Install pre-built binary
            log_info "Downloading pre-built ncspot binary..."
            
            # Detect architecture
            ARCH=$(uname -m)
            case "$ARCH" in
                aarch64|arm64)
                    NCSPOT_ARCH="aarch64"
                    ;;
                armv7l|armhf)
                    NCSPOT_ARCH="armv7"
                    ;;
                x86_64)
                    NCSPOT_ARCH="x86_64"
                    ;;
                *)
                    log_error "Unsupported architecture: $ARCH"
                    log_info "Using alternative: spotify-tui"
                    apt-get install -y spotify-tui 2>/dev/null || true
                    return 1
                    ;;
            esac
            
            # Download from GitHub releases (if available)
            NCSPOT_VERSION="0.13.4"
            NCSPOT_URL="https://github.com/hrkfdn/ncspot/releases/download/v${NCSPOT_VERSION}/ncspot-v${NCSPOT_VERSION}-linux-${NCSPOT_ARCH}.tar.gz"
            
            if wget -q --spider "$NCSPOT_URL" 2>/dev/null; then
                wget -q -O /tmp/ncspot.tar.gz "$NCSPOT_URL"
                tar -xzf /tmp/ncspot.tar.gz -C /usr/local/bin/
                chmod +x /usr/local/bin/ncspot
                rm /tmp/ncspot.tar.gz
                log_success "ncspot installed from pre-built binary"
            else
                log_warning "Pre-built binary not available"
                
                # Last resort: build from source
                log_info "Building ncspot from source..."
                cd /tmp
                git clone https://github.com/hrkfdn/ncspot.git
                cd ncspot
                cargo build --release --no-default-features --features alsa_backend
                cp target/release/ncspot /usr/local/bin/
                chmod +x /usr/local/bin/ncspot
                cd /
                rm -rf /tmp/ncspot
                log_success "ncspot built from source"
            fi
        }
    else
        log_error "Cargo not available, cannot install ncspot"
        log_info "Using alternative: installing spotifyd instead"
        
        # Install spotifyd as alternative
        install_spotifyd_alternative
    fi
}

# Alternative: Install spotifyd + basic TUI
install_spotifyd_alternative() {
    log_info "Installing spotifyd as alternative..."
    
    # Download spotifyd
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|arm64)
            SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-armv6-slim.tar.gz"
            ;;
        armv7l|armhf)
            SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-armv7-slim.tar.gz"
            ;;
        x86_64)
            SPOTIFYD_URL="https://github.com/Spotifyd/spotifyd/releases/latest/download/spotifyd-linux-slim.tar.gz"
            ;;
        *)
            log_error "Unsupported architecture for spotifyd: $ARCH"
            return 1
            ;;
    esac
    
    wget -q -O /tmp/spotifyd.tar.gz "$SPOTIFYD_URL"
    tar -xzf /tmp/spotifyd.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/spotifyd
    rm /tmp/spotifyd.tar.gz
    
    # Create a simple TUI wrapper
    cat > /usr/local/bin/spotify-tui-simple <<'EOF'
#!/bin/bash
echo "Spotify Kids Player"
echo "=================="
echo ""
echo "Spotifyd is running in background"
echo "Use the Spotify app on your phone to control playback"
echo ""
echo "Press Ctrl+C to exit (if unlocked)"
while true; do
    sleep 1
done
EOF
    chmod +x /usr/local/bin/spotify-tui-simple
    
    log_success "Spotifyd alternative installed"
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
    
    # Create ncspot configuration
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

# Source configuration
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Check if device is locked
is_locked() {
    [[ -f "$LOCK_FILE" ]]
}

# Start ncspot with appropriate settings
start_client() {
    # Clear screen
    clear
    
    # Display header
    echo "================================================"
    echo "         Spotify Kids Music Player             "
    echo "================================================"
    echo ""
    
    # Check if Spotify is disabled
    if [[ "$SPOTIFY_DISABLED" == "true" ]]; then
        echo "Spotify is currently disabled by administrator"
        echo "Please contact your parent to enable it"
        sleep infinity
        exit 0
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
    
    # Create auto-start script
    cat > "/home/$SPOTIFY_USER/.bash_profile" <<EOF
# Auto-start Spotify client on login
if [[ "\$(tty)" == "/dev/tty1" ]]; then
    # Start X session with Spotify client
    startx /opt/spotify-terminal/scripts/start-x.sh
fi
EOF
    
    # Create X session startup script
    cat > "$INSTALL_DIR/scripts/start-x.sh" <<'EOF'
#!/bin/bash

# Disable screen blanking and power management
xset s off
xset -dpms
xset s noblank

# Hide cursor after 1 second of inactivity
unclutter -idle 1 &

# Start window manager (minimal)
openbox &

# Start terminal with Spotify client in fullscreen
exec urxvt -fn "xft:DejaVu Sans Mono:size=14" \
    -bg black -fg green \
    -geometry 1000x1000 \
    +sb \
    -e /opt/spotify-terminal/scripts/spotify-client.sh
EOF
    
    chmod +x "$INSTALL_DIR/scripts/start-x.sh"
    
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
                <button class="btn" onclick="viewLogs()">View Logs</button>
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
            
            const response = await fetch('/api/spotify/config', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({username, password})
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
        
        async function viewLogs() {
            const response = await fetch('/api/system/logs');
            const logs = await response.text();
            alert(logs);
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

@app.route('/api/spotify/config', methods=['POST'])
@login_required
def set_spotify_config():
    data = request.json
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()
    
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    
    # Detect which backend we're using
    backend = "ncspot"
    if os.path.exists("/usr/local/bin/spotifyd"):
        backend = "spotifyd"
    
    if backend == "ncspot":
        # Configure ncspot
        config_dir = "/home/spotify-kids/.config/ncspot"
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
path = "/home/spotify-kids/.cache/ncspot"
size = 10000

[keybindings]
"q" = "quit"
'''
        
        with open(config_file, 'w') as f:
            f.write(config_content)
        
        # Set proper ownership
        subprocess.run(['chown', '-R', 'spotify-kids:spotify-kids', config_dir])
        
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
        subprocess.run(['chown', 'spotify-kids:spotify-kids', creds_file])
        
    else:
        # Configure spotifyd
        config_dir = "/home/spotify-kids/.config/spotifyd"
        config_file = f"{config_dir}/spotifyd.conf"
        
        os.makedirs(config_dir, exist_ok=True)
        
        # Create spotifyd config
        config_content = f'''[global]
username = {username}
password = {password}
backend = alsa
device_name = Spotify Kids Player
bitrate = 320
cache_path = /home/spotify-kids/.cache/spotifyd
max_cache_size = 10000000000
cache = true
volume_normalisation = true
normalisation_pregain = -10
'''
        
        with open(config_file, 'w') as f:
            f.write(config_content)
        
        # Set proper ownership
        subprocess.run(['chown', '-R', 'spotify-kids:spotify-kids', config_dir])
        subprocess.run(['chmod', '600', config_file])
        
        # Restart spotifyd if running
        subprocess.run(['systemctl', 'restart', 'spotifyd'], capture_output=True)
    
    # Save to our config
    config = load_config()
    config['spotify_configured'] = True
    config['spotify_username'] = username
    save_config(config)
    
    # Restart the spotify user session to apply changes
    subprocess.run(['pkill', '-u', 'spotify-kids'], capture_output=True)
    
    return jsonify({"success": True, "message": f"Spotify configured for {username}", "backend": backend})

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
    log_info "Removing existing installation..."
    
    # Stop services
    systemctl stop "$SERVICE_NAME" 2>/dev/null
    systemctl disable "$SERVICE_NAME" 2>/dev/null
    
    # Remove systemd files
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    rm -rf /etc/systemd/system/getty@tty1.service.d/
    
    # Remove nginx config
    rm -f /etc/nginx/sites-enabled/spotify-admin
    rm -f /etc/nginx/sites-available/spotify-admin
    
    # Remove user
    pkill -u "$SPOTIFY_USER" 2>/dev/null
    userdel -r "$SPOTIFY_USER" 2>/dev/null
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    # Reload systemd
    systemctl daemon-reload
    systemctl restart nginx 2>/dev/null
    
    log_success "Existing installation removed"
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
        log_warning "This will completely remove and reinstall everything!"
        read -p "Are you sure you want to reset? (yes/no): " -r
        if [[ ! $REPLY == "yes" ]]; then
            log_info "Reset cancelled"
            exit 0
        fi
        
        check_root
        log_info "Performing complete reset..."
        
        # Force uninstall everything
        systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        systemctl stop nginx 2>/dev/null || true
        
        # Kill all related processes
        pkill -f "app.py" 2>/dev/null || true
        pkill -f "ncspot" 2>/dev/null || true
        pkill -u "$SPOTIFY_USER" 2>/dev/null || true
        
        # Remove everything
        rm -rf "$INSTALL_DIR"
        rm -f "/etc/systemd/system/$SERVICE_NAME.service"
        rm -rf /etc/systemd/system/getty@tty1.service.d/
        rm -f /etc/nginx/sites-enabled/spotify-admin
        rm -f /etc/nginx/sites-available/spotify-admin
        userdel -rf "$SPOTIFY_USER" 2>/dev/null || true
        
        # Clean up Python packages
        pip3 uninstall -y flask flask-cors flask-socketio werkzeug dbus-python pulsectl 2>/dev/null || true
        
        # Reset nginx to default
        apt-get remove --purge -y nginx nginx-common 2>/dev/null || true
        apt-get autoremove -y 2>/dev/null || true
        rm -rf /etc/nginx
        
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