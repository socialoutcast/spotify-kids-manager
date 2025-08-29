#!/usr/bin/env python3

from flask import Flask, request, jsonify, session, redirect, url_for, render_template_string
from flask_cors import CORS
from werkzeug.security import check_password_hash, generate_password_hash
import os
import json
import subprocess
import psutil
from datetime import datetime

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
CORS(app)

# Configuration
CONFIG_DIR = os.environ.get('SPOTIFY_CONFIG_DIR', '/opt/spotify-kids/config')
CONFIG_FILE = os.path.join(CONFIG_DIR, 'admin_config.json')
SPOTIFY_CONFIG_FILE = os.path.join(CONFIG_DIR, 'spotify_config.json')

# Default admin credentials
DEFAULT_ADMIN_USER = 'admin'
DEFAULT_ADMIN_PASS = 'changeme'

def load_config():
    """Load admin configuration"""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    else:
        # Create default config
        default_config = {
            'admin_user': DEFAULT_ADMIN_USER,
            'admin_pass': generate_password_hash(DEFAULT_ADMIN_PASS),
            'device_locked': False,
            'allowed_playlists': [],
            'blocked_content': [],
            'volume_limit': 85,
            'time_restrictions': {
                'enabled': False,
                'start_time': '07:00',
                'end_time': '21:00'
            }
        }
        save_config(default_config)
        return default_config

def save_config(config):
    """Save admin configuration"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def load_spotify_config():
    """Load Spotify API configuration"""
    if os.path.exists(SPOTIFY_CONFIG_FILE):
        with open(SPOTIFY_CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {}

def save_spotify_config(config):
    """Save Spotify API configuration"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(SPOTIFY_CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

# HTML Template
ADMIN_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Spotify Kids Admin Panel</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
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
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 5px;
            font-size: 14px;
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
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .card h2 {
            color: #333;
            margin-bottom: 15px;
            font-size: 20px;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            color: #666;
            font-size: 14px;
        }
        input, select, textarea {
            width: 100%;
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }
        button {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            font-weight: bold;
        }
        button:hover {
            background: #5a67d8;
        }
        button.danger {
            background: #ef4444;
        }
        button.danger:hover {
            background: #dc2626;
        }
        .toggle {
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .switch {
            position: relative;
            display: inline-block;
            width: 50px;
            height: 24px;
        }
        .switch input {
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
            border-radius: 24px;
        }
        .slider:before {
            position: absolute;
            content: "";
            height: 18px;
            width: 18px;
            left: 3px;
            bottom: 3px;
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
        .playlist-list {
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 10px;
        }
        .playlist-item {
            padding: 5px;
            margin-bottom: 5px;
            background: #f3f4f6;
            border-radius: 3px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 10px;
        }
        .stat {
            text-align: center;
            padding: 10px;
            background: #f3f4f6;
            border-radius: 5px;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
            color: #667eea;
        }
        .stat-label {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }
        {% if not logged_in %}
        .login-container {
            max-width: 400px;
            margin: 100px auto;
        }
        {% endif %}
    </style>
</head>
<body>
    <div class="container">
        {% if logged_in %}
        <div class="header">
            <h1>🎵 Spotify Kids Admin Panel</h1>
            <span class="status {{ 'online' if player_status else 'offline' }}">
                Player: {{ 'Online' if player_status else 'Offline' }}
            </span>
        </div>
        
        <div class="grid">
            <!-- Device Control -->
            <div class="card">
                <h2>🔒 Device Control</h2>
                <div class="toggle">
                    <label>Device Lock</label>
                    <label class="switch">
                        <input type="checkbox" id="deviceLock" {{ 'checked' if config.device_locked else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <p style="color: #666; font-size: 12px; margin-top: 10px;">
                    When locked, playback controls are disabled on the device.
                </p>
            </div>
            
            <!-- Volume Control -->
            <div class="card">
                <h2>🔊 Volume Control</h2>
                <div class="form-group">
                    <label>Maximum Volume Limit</label>
                    <input type="range" id="volumeLimit" min="0" max="100" value="{{ config.volume_limit }}">
                    <span id="volumeValue">{{ config.volume_limit }}%</span>
                </div>
            </div>
            
            <!-- Time Restrictions -->
            <div class="card">
                <h2>⏰ Time Restrictions</h2>
                <div class="toggle">
                    <label>Enable Time Restrictions</label>
                    <label class="switch">
                        <input type="checkbox" id="timeRestrictions" {{ 'checked' if config.time_restrictions.enabled else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <div class="form-group">
                    <label>Start Time</label>
                    <input type="time" id="startTime" value="{{ config.time_restrictions.start_time }}">
                </div>
                <div class="form-group">
                    <label>End Time</label>
                    <input type="time" id="endTime" value="{{ config.time_restrictions.end_time }}">
                </div>
            </div>
            
            <!-- Spotify Configuration -->
            <div class="card">
                <h2>🎵 Spotify Configuration</h2>
                <div class="form-group">
                    <label>Client ID</label>
                    <input type="text" id="clientId" value="{{ spotify_config.get('client_id', '') }}" placeholder="Enter Spotify Client ID">
                </div>
                <div class="form-group">
                    <label>Client Secret</label>
                    <input type="password" id="clientSecret" value="{{ spotify_config.get('client_secret', '') }}" placeholder="Enter Spotify Client Secret">
                </div>
                <button onclick="saveSpotifyConfig()">Save Spotify Config</button>
            </div>
            
            <!-- Player Control -->
            <div class="card">
                <h2>🎮 Player Control</h2>
                <button onclick="controlPlayer('restart')">Restart Player</button>
                <button onclick="controlPlayer('stop')" class="danger">Stop Player</button>
                <div style="margin-top: 15px;">
                    <button onclick="controlPlayer('play')">▶ Play</button>
                    <button onclick="controlPlayer('pause')">⏸ Pause</button>
                    <button onclick="controlPlayer('next')">⏭ Next</button>
                </div>
            </div>
            
            <!-- System Stats -->
            <div class="card">
                <h2>📊 System Status</h2>
                <div class="stats">
                    <div class="stat">
                        <div class="stat-value">{{ cpu_usage }}%</div>
                        <div class="stat-label">CPU Usage</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{{ memory_usage }}%</div>
                        <div class="stat-label">Memory Usage</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{{ disk_usage }}%</div>
                        <div class="stat-label">Disk Usage</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{{ uptime }}</div>
                        <div class="stat-label">Uptime</div>
                    </div>
                </div>
            </div>
            
            <!-- Admin Settings -->
            <div class="card">
                <h2>⚙️ Admin Settings</h2>
                <div class="form-group">
                    <label>Admin Username</label>
                    <input type="text" id="adminUser" value="{{ config.admin_user }}">
                </div>
                <div class="form-group">
                    <label>New Password</label>
                    <input type="password" id="adminPass" placeholder="Leave blank to keep current">
                </div>
                <button onclick="saveAdminSettings()">Update Settings</button>
                <button onclick="logout()" class="danger" style="margin-left: 10px;">Logout</button>
            </div>
        </div>
        
        {% else %}
        <!-- Login Form -->
        <div class="login-container">
            <div class="card">
                <h2>🔐 Admin Login</h2>
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" id="loginUser" value="admin">
                </div>
                <div class="form-group">
                    <label>Password</label>
                    <input type="password" id="loginPass">
                </div>
                <button onclick="login()">Login</button>
                <p style="color: #666; font-size: 12px; margin-top: 15px;">
                    Default: admin / changeme
                </p>
            </div>
        </div>
        {% endif %}
    </div>
    
    <script>
        {% if logged_in %}
        // Update volume display
        document.getElementById('volumeLimit').addEventListener('input', function(e) {
            document.getElementById('volumeValue').textContent = e.target.value + '%';
        });
        
        // Save settings functions
        function saveSpotifyConfig() {
            fetch('/api/spotify/config', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    client_id: document.getElementById('clientId').value,
                    client_secret: document.getElementById('clientSecret').value
                })
            }).then(r => r.json()).then(data => {
                alert(data.message || 'Configuration saved');
            });
        }
        
        function saveAdminSettings() {
            fetch('/api/admin/settings', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    admin_user: document.getElementById('adminUser').value,
                    admin_pass: document.getElementById('adminPass').value,
                    device_locked: document.getElementById('deviceLock').checked,
                    volume_limit: parseInt(document.getElementById('volumeLimit').value),
                    time_restrictions: {
                        enabled: document.getElementById('timeRestrictions').checked,
                        start_time: document.getElementById('startTime').value,
                        end_time: document.getElementById('endTime').value
                    }
                })
            }).then(r => r.json()).then(data => {
                alert(data.message || 'Settings saved');
                if (data.success) location.reload();
            });
        }
        
        function controlPlayer(action) {
            fetch('/api/player/' + action, {method: 'POST'})
                .then(r => r.json())
                .then(data => {
                    alert(data.message || 'Command sent');
                });
        }
        
        function logout() {
            fetch('/api/logout', {method: 'POST'})
                .then(() => location.reload());
        }
        
        // Auto-save toggles
        document.getElementById('deviceLock').addEventListener('change', saveAdminSettings);
        document.getElementById('timeRestrictions').addEventListener('change', saveAdminSettings);
        
        {% else %}
        function login() {
            fetch('/api/login', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({
                    username: document.getElementById('loginUser').value,
                    password: document.getElementById('loginPass').value
                })
            }).then(r => {
                if (r.ok) {
                    location.reload();
                } else {
                    alert('Invalid credentials');
                }
            });
        }
        
        document.getElementById('loginPass').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') login();
        });
        {% endif %}
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    """Main admin panel page"""
    config = load_config()
    spotify_config = load_spotify_config()
    
    # Check if player is running
    player_status = False
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        if 'spotify_player.py' in ' '.join(proc.info.get('cmdline', [])):
            player_status = True
            break
    
    # Get system stats
    cpu_usage = psutil.cpu_percent(interval=1)
    memory_usage = psutil.virtual_memory().percent
    disk_usage = psutil.disk_usage('/').percent
    uptime_seconds = time.time() - psutil.boot_time()
    uptime = f"{int(uptime_seconds // 3600)}h {int((uptime_seconds % 3600) // 60)}m"
    
    return render_template_string(ADMIN_TEMPLATE,
                                 logged_in='logged_in' in session,
                                 config=config,
                                 spotify_config=spotify_config,
                                 player_status=player_status,
                                 cpu_usage=cpu_usage,
                                 memory_usage=memory_usage,
                                 disk_usage=disk_usage,
                                 uptime=uptime)

@app.route('/api/login', methods=['POST'])
def login():
    """Login endpoint"""
    data = request.json
    config = load_config()
    
    if (data['username'] == config['admin_user'] and 
        check_password_hash(config['admin_pass'], data['password'])):
        session['logged_in'] = True
        return jsonify({'success': True})
    
    return jsonify({'error': 'Invalid credentials'}), 401

@app.route('/api/logout', methods=['POST'])
def logout():
    """Logout endpoint"""
    session.pop('logged_in', None)
    return jsonify({'success': True})

@app.route('/api/admin/settings', methods=['POST'])
def update_admin_settings():
    """Update admin settings"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    config = load_config()
    
    # Update settings
    config['admin_user'] = data.get('admin_user', config['admin_user'])
    if data.get('admin_pass'):
        config['admin_pass'] = generate_password_hash(data['admin_pass'])
    config['device_locked'] = data.get('device_locked', config['device_locked'])
    config['volume_limit'] = data.get('volume_limit', config['volume_limit'])
    config['time_restrictions'] = data.get('time_restrictions', config['time_restrictions'])
    
    save_config(config)
    return jsonify({'success': True, 'message': 'Settings updated'})

@app.route('/api/spotify/config', methods=['POST'])
def update_spotify_config():
    """Update Spotify configuration"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    config = {
        'client_id': data.get('client_id', ''),
        'client_secret': data.get('client_secret', ''),
        'redirect_uri': 'http://localhost:8888/callback'
    }
    
    save_spotify_config(config)
    return jsonify({'success': True, 'message': 'Spotify configuration saved'})

@app.route('/api/player/<action>', methods=['POST'])
def control_player(action):
    """Control the player"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        if action == 'restart':
            subprocess.run(['systemctl', 'restart', 'spotify-player'], check=False)
            return jsonify({'success': True, 'message': 'Player restarting'})
        elif action == 'stop':
            subprocess.run(['systemctl', 'stop', 'spotify-player'], check=False)
            return jsonify({'success': True, 'message': 'Player stopped'})
        elif action in ['play', 'pause', 'next']:
            # These would need to communicate with the player via IPC
            # For now, just acknowledge
            return jsonify({'success': True, 'message': f'Command {action} sent'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    
    return jsonify({'error': 'Unknown action'}), 400

import time

if __name__ == '__main__':
    os.makedirs(CONFIG_DIR, exist_ok=True)
    app.run(host='0.0.0.0', port=5001, debug=False)