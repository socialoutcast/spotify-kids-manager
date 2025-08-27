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
        ncspot \
        screen \
        tmux \
        xinit \
        x11-xserver-utils \
        openbox \
        rxvt-unicode \
        fonts-dejavu-core \
        nginx
    
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
}

# Create restricted user
create_spotify_user() {
    log_info "Creating restricted user '$SPOTIFY_USER'..."
    
    # Create user without sudo access and with limited shell
    useradd -m -s /bin/bash -G audio,video,bluetooth "$SPOTIFY_USER" || true
    
    # Set up user environment
    mkdir -p "/home/$SPOTIFY_USER/.config"
    mkdir -p "/home/$SPOTIFY_USER/.cache"
    
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
    
    # Start ncspot
    if is_locked; then
        # Locked mode - disable quit key
        exec ncspot --config <(cat ~/.config/ncspot/config.toml | sed '/^"q"/d')
    else
        # Unlocked mode - normal operation
        exec ncspot
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
            
            <!-- Account Settings -->
            <div class="card">
                <h2>Account Settings</h2>
                <form id="passwordForm">
                    <div class="form-group">
                        <label>New Password</label>
                        <input type="password" id="newPassword" required>
                    </div>
                    <div class="form-group">
                        <label>Confirm Password</label>
                        <input type="password" id="confirmPassword" required>
                    </div>
                    <button type="submit" class="btn">Change Password</button>
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
    clear
    echo "============================================"
    echo "    Spotify Kids Terminal Manager"
    echo "    Installation Script v1.0"
    echo "============================================"
    echo ""
    
    check_root
    detect_system
    check_existing_installation
    
    log_info "Starting installation..."
    
    install_dependencies
    create_spotify_user
    setup_spotify_client
    setup_web_admin
    create_systemd_service
    create_uninstall_script
    
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