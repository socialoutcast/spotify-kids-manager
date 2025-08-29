#!/usr/bin/env python3

from flask import Flask, request, jsonify, session, redirect, url_for, render_template_string, Response
from flask_cors import CORS
from werkzeug.security import check_password_hash, generate_password_hash
import os
import json
import subprocess
import psutil
from datetime import datetime
import threading
import queue

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
            
            <!-- System Updates -->
            <div class="card">
                <h2>🔄 System Updates</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    Keep your system up to date with the latest security patches and improvements.
                </p>
                <button onclick="checkUpdates()">Check for Updates</button>
                <button onclick="runUpdate()" style="margin-left: 10px;">Update System</button>
                <div id="updateStatus" style="margin-top: 15px; display: none;">
                    <div style="padding: 10px; background: #f3f4f6; border-radius: 5px;">
                        <div id="updateMessage" style="font-size: 12px; color: #666;"></div>
                    </div>
                </div>
            </div>
            
            <!-- System Logs -->
            <div class="card" style="grid-column: span 2;">
                <h2>📋 System Logs & Diagnostics</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    View system logs and debug information for troubleshooting.
                </p>
                <div style="display: flex; gap: 10px; margin-bottom: 15px; flex-wrap: wrap;">
                    <button onclick="loadLog('player')">Player Logs</button>
                    <button onclick="loadLog('admin')">Admin Panel Logs</button>
                    <button onclick="loadLog('nginx')">Nginx Logs</button>
                    <button onclick="loadLog('system')">System Boot Logs</button>
                    <button onclick="loadLog('auth')">Auth Logs</button>
                    <button onclick="loadLog('all')">All Recent Logs</button>
                    <button onclick="clearLogs()" class="danger">Clear Old Logs</button>
                </div>
                <div style="display: flex; gap: 10px; margin-bottom: 10px;">
                    <label style="display: flex; align-items: center;">
                        <input type="checkbox" id="autoRefresh" checked style="margin-right: 5px;">
                        Auto-refresh (5s)
                    </label>
                    <label style="display: flex; align-items: center;">
                        Lines: <input type="number" id="logLines" value="100" min="10" max="1000" style="width: 80px; margin-left: 5px;">
                    </label>
                    <button onclick="downloadLogs()">Download All Logs</button>
                </div>
                <div id="logOutput" style="background: #1e1e1e; color: #00ff00; font-family: 'Courier New', monospace; font-size: 11px; padding: 15px; border-radius: 5px; height: 400px; overflow-y: auto; white-space: pre-wrap; word-wrap: break-word;">
                    Select a log type to view...
                </div>
            </div>
            
            <!-- Bluetooth Devices -->
            <div class="card">
                <h2>🎧 Bluetooth Devices</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    Manage Bluetooth speakers and headphones for audio output.
                </p>
                <div id="bluetoothStatus" style="margin-bottom: 15px;">
                    <span class="status {{ 'online' if bluetooth_enabled else 'offline' }}" style="font-size: 12px;">
                        Bluetooth: {{ 'Enabled' if bluetooth_enabled else 'Disabled' }}
                    </span>
                </div>
                <div id="pairedDevices" style="margin-bottom: 15px;">
                    <label style="font-size: 14px; margin-bottom: 10px; display: block;">Paired Devices:</label>
                    <div id="pairedList" style="max-height: 150px; overflow-y: auto; border: 1px solid #ddd; border-radius: 5px; padding: 10px;">
                        {% for device in paired_devices %}
                        <div class="device-item" style="padding: 8px; background: #f3f4f6; border-radius: 3px; margin-bottom: 5px; display: flex; justify-content: space-between; align-items: center;">
                            <span>{{ device.name }} ({{ device.address }})</span>
                            <div>
                                {% if device.connected %}
                                <button onclick="disconnectBluetooth('{{ device.address }}')" style="font-size: 12px; padding: 5px 10px;">Disconnect</button>
                                {% else %}
                                <button onclick="connectBluetooth('{{ device.address }}')" style="font-size: 12px; padding: 5px 10px;">Connect</button>
                                {% endif %}
                                <button onclick="removeBluetooth('{{ device.address }}')" class="danger" style="font-size: 12px; padding: 5px 10px; margin-left: 5px;">Remove</button>
                            </div>
                        </div>
                        {% else %}
                        <p style="color: #999; font-size: 12px;">No paired devices</p>
                        {% endfor %}
                    </div>
                </div>
                <button onclick="scanBluetooth()">Scan for Devices</button>
                <button onclick="toggleBluetooth()" style="margin-left: 10px;">{{ 'Disable' if bluetooth_enabled else 'Enable' }} Bluetooth</button>
                <div id="scanResults" style="margin-top: 15px; display: none;">
                    <label style="font-size: 14px; margin-bottom: 10px; display: block;">Available Devices:</label>
                    <div id="scanList" style="max-height: 150px; overflow-y: auto; border: 1px solid #ddd; border-radius: 5px; padding: 10px;">
                        <p style="color: #999; font-size: 12px;">Scanning...</p>
                    </div>
                </div>
            </div>
        </div>
        
        <!-- Update Progress Modal -->
        <div id="updateModal" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000;">
            <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; border-radius: 10px; padding: 30px; width: 600px; max-height: 80vh; overflow-y: auto;">
                <h2 style="margin-bottom: 20px;">System Update Progress</h2>
                <div id="updateOutput" style="background: #1e1e1e; color: #00ff00; font-family: 'Courier New', monospace; font-size: 12px; padding: 15px; border-radius: 5px; height: 300px; overflow-y: auto; white-space: pre-wrap;"></div>
                <div style="margin-top: 20px; text-align: right;">
                    <button id="closeUpdateModal" onclick="closeUpdateModal()" style="display: none;">Close</button>
                </div>
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
        
        // System update functions
        function checkUpdates() {
            document.getElementById('updateStatus').style.display = 'block';
            document.getElementById('updateMessage').textContent = 'Checking for updates...';
            
            fetch('/api/system/check-updates')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('updateMessage').innerHTML = data.message;
                })
                .catch(err => {
                    document.getElementById('updateMessage').textContent = 'Error checking updates: ' + err;
                });
        }
        
        function runUpdate() {
            if (!confirm('This will update the system packages. The process may take several minutes. Continue?')) {
                return;
            }
            
            // Show modal
            document.getElementById('updateModal').style.display = 'block';
            document.getElementById('updateOutput').textContent = 'Starting system update...\n';
            document.getElementById('closeUpdateModal').style.display = 'none';
            
            // Start SSE connection for live updates
            const eventSource = new EventSource('/api/system/update-stream');
            
            eventSource.onmessage = function(event) {
                const output = document.getElementById('updateOutput');
                output.textContent += event.data + '\n';
                output.scrollTop = output.scrollHeight;
            };
            
            eventSource.onerror = function(error) {
                eventSource.close();
                const output = document.getElementById('updateOutput');
                output.textContent += '\n=== Update Complete ===\n';
                document.getElementById('closeUpdateModal').style.display = 'inline-block';
            };
        }
        
        function closeUpdateModal() {
            document.getElementById('updateModal').style.display = 'none';
            // Refresh page to show any changes
            location.reload();
        }
        
        // Bluetooth functions
        function scanBluetooth() {
            document.getElementById('scanResults').style.display = 'block';
            document.getElementById('scanList').innerHTML = '<p style="color: #999; font-size: 12px;">Scanning for devices...</p>';
            
            fetch('/api/bluetooth/scan')
                .then(r => r.json())
                .then(data => {
                    let html = '';
                    if (data.devices && data.devices.length > 0) {
                        data.devices.forEach(device => {
                            html += `
                                <div style="padding: 8px; background: #f3f4f6; border-radius: 3px; margin-bottom: 5px; display: flex; justify-content: space-between; align-items: center;">
                                    <span>${device.name || 'Unknown'} (${device.address})</span>
                                    <button onclick="pairBluetooth('${device.address}')" style="font-size: 12px; padding: 5px 10px;">Pair</button>
                                </div>
                            `;
                        });
                    } else {
                        html = '<p style="color: #999; font-size: 12px;">No devices found</p>';
                    }
                    document.getElementById('scanList').innerHTML = html;
                })
                .catch(err => {
                    document.getElementById('scanList').innerHTML = '<p style="color: red; font-size: 12px;">Error: ' + err + '</p>';
                });
        }
        
        function pairBluetooth(address) {
            if (!confirm('Pair with device ' + address + '?')) return;
            
            fetch('/api/bluetooth/pair', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({address: address})
            })
            .then(r => r.json())
            .then(data => {
                alert(data.message || 'Pairing initiated');
                if (data.success) {
                    location.reload();
                }
            })
            .catch(err => alert('Error: ' + err));
        }
        
        function connectBluetooth(address) {
            fetch('/api/bluetooth/connect', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({address: address})
            })
            .then(r => r.json())
            .then(data => {
                alert(data.message || 'Connection initiated');
                if (data.success) {
                    location.reload();
                }
            })
            .catch(err => alert('Error: ' + err));
        }
        
        function disconnectBluetooth(address) {
            fetch('/api/bluetooth/disconnect', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({address: address})
            })
            .then(r => r.json())
            .then(data => {
                alert(data.message || 'Disconnected');
                if (data.success) {
                    location.reload();
                }
            })
            .catch(err => alert('Error: ' + err));
        }
        
        function removeBluetooth(address) {
            if (!confirm('Remove device ' + address + '?')) return;
            
            fetch('/api/bluetooth/remove', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({address: address})
            })
            .then(r => r.json())
            .then(data => {
                alert(data.message || 'Device removed');
                if (data.success) {
                    location.reload();
                }
            })
            .catch(err => alert('Error: ' + err));
        }
        
        function toggleBluetooth() {
            fetch('/api/bluetooth/toggle', {method: 'POST'})
                .then(r => r.json())
                .then(data => {
                    alert(data.message || 'Bluetooth toggled');
                    location.reload();
                })
                .catch(err => alert('Error: ' + err));
        }
        
        // Logs functions
        let currentLogType = null;
        let logRefreshInterval = null;
        
        function loadLog(type) {
            currentLogType = type;
            const lines = document.getElementById('logLines').value;
            const output = document.getElementById('logOutput');
            output.textContent = 'Loading logs...';
            
            fetch(`/api/logs/${type}?lines=${lines}`)
                .then(r => r.text())
                .then(data => {
                    output.textContent = data || 'No logs available';
                    output.scrollTop = output.scrollHeight;
                })
                .catch(err => {
                    output.textContent = 'Error loading logs: ' + err;
                });
        }
        
        function clearLogs() {
            if (!confirm('Clear old log files? This will free up disk space.')) return;
            
            fetch('/api/logs/clear', {method: 'POST'})
                .then(r => r.json())
                .then(data => {
                    alert(data.message || 'Logs cleared');
                    if (currentLogType) loadLog(currentLogType);
                })
                .catch(err => alert('Error: ' + err));
        }
        
        function downloadLogs() {
            window.location.href = '/api/logs/download';
        }
        
        // Auto-refresh logs
        document.getElementById('autoRefresh').addEventListener('change', function(e) {
            if (e.target.checked && currentLogType) {
                logRefreshInterval = setInterval(() => {
                    if (currentLogType) loadLog(currentLogType);
                }, 5000);
            } else {
                clearInterval(logRefreshInterval);
                logRefreshInterval = null;
            }
        });
        
        // Load player logs by default
        window.addEventListener('load', () => {
            loadLog('player');
            if (document.getElementById('autoRefresh').checked) {
                logRefreshInterval = setInterval(() => {
                    if (currentLogType) loadLog(currentLogType);
                }, 5000);
            }
        });
        
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

def get_bluetooth_status():
    """Get Bluetooth status and paired devices"""
    try:
        # Check if Bluetooth is enabled
        result = subprocess.run(['sudo', 'systemctl', 'is-active', 'bluetooth'], 
                              capture_output=True, text=True)
        bluetooth_enabled = result.stdout.strip() == 'active'
        
        # Get paired devices
        paired_devices = []
        result = subprocess.run(['sudo', 'bluetoothctl', 'paired-devices'], 
                              capture_output=True, text=True, timeout=5)
        
        for line in result.stdout.split('\n'):
            if 'Device' in line:
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    address = parts[1]
                    name = parts[2] if len(parts) > 2 else 'Unknown'
                    
                    # Check if connected
                    info_result = subprocess.run(['sudo', 'bluetoothctl', 'info', address],
                                               capture_output=True, text=True, timeout=5)
                    connected = 'Connected: yes' in info_result.stdout
                    
                    paired_devices.append({
                        'address': address,
                        'name': name,
                        'connected': connected
                    })
        
        return bluetooth_enabled, paired_devices
    except:
        return False, []

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
    
    # Get Bluetooth status
    bluetooth_enabled, paired_devices = get_bluetooth_status()
    
    return render_template_string(ADMIN_TEMPLATE,
                                 logged_in='logged_in' in session,
                                 config=config,
                                 spotify_config=spotify_config,
                                 player_status=player_status,
                                 cpu_usage=cpu_usage,
                                 memory_usage=memory_usage,
                                 disk_usage=disk_usage,
                                 uptime=uptime,
                                 bluetooth_enabled=bluetooth_enabled,
                                 paired_devices=paired_devices)

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

@app.route('/api/system/check-updates')
def check_updates():
    """Check for available system updates"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Update package list
        subprocess.run(['sudo', 'apt-get', 'update'], capture_output=True, text=True, check=False)
        
        # Check for upgradable packages
        result = subprocess.run(['apt', 'list', '--upgradable'], 
                              capture_output=True, text=True, check=False)
        
        lines = result.stdout.strip().split('\n')
        upgradable = [line for line in lines if '/' in line and not line.startswith('Listing')]
        
        if upgradable:
            message = f"<strong>{len(upgradable)} updates available:</strong><br>"
            for pkg in upgradable[:10]:  # Show first 10
                pkg_name = pkg.split('/')[0]
                message += f"• {pkg_name}<br>"
            if len(upgradable) > 10:
                message += f"<em>...and {len(upgradable) - 10} more</em>"
        else:
            message = "System is up to date!"
        
        return jsonify({'success': True, 'message': message, 'count': len(upgradable)})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/update-stream')
def update_stream():
    """Stream system update progress"""
    if 'logged_in' not in session:
        return Response("Error: Not authenticated", status=401)
    
    def generate():
        # Create a queue for output
        output_queue = queue.Queue()
        
        def run_update():
            try:
                # Run apt update
                yield "data: Running apt update...\n\n"
                proc = subprocess.Popen(['sudo', 'apt-get', 'update', '-y'],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, bufsize=1)
                for line in proc.stdout:
                    yield f"data: {line.strip()}\n\n"
                proc.wait()
                
                # Run apt upgrade with auto-yes
                yield "data: \n\n"
                yield "data: Running system upgrade (this may take a while)...\n\n"
                proc = subprocess.Popen(['sudo', 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 
                                       'upgrade', '-y', '--force-yes', '-o', 
                                       'Dpkg::Options::=--force-confdef', '-o',
                                       'Dpkg::Options::=--force-confold'],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, bufsize=1, env={**os.environ, 'DEBIAN_FRONTEND': 'noninteractive'})
                
                for line in proc.stdout:
                    cleaned_line = line.strip()
                    if cleaned_line:
                        yield f"data: {cleaned_line}\n\n"
                
                proc.wait()
                
                # Clean up
                yield "data: \n\n"
                yield "data: Cleaning up...\n\n"
                subprocess.run(['sudo', 'apt-get', 'autoremove', '-y'], 
                             capture_output=True, check=False)
                subprocess.run(['sudo', 'apt-get', 'autoclean', '-y'], 
                             capture_output=True, check=False)
                
                yield "data: \n\n"
                yield "data: ✓ Update completed successfully!\n\n"
                
            except Exception as e:
                yield f"data: Error: {str(e)}\n\n"
        
        # Return the generator
        return run_update()
    
    return Response(generate(), mimetype='text/event-stream',
                   headers={'Cache-Control': 'no-cache',
                           'X-Accel-Buffering': 'no'})

@app.route('/api/bluetooth/scan')
def bluetooth_scan():
    """Scan for Bluetooth devices"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Enable scanning
        subprocess.run(['sudo', 'bluetoothctl', 'scan', 'on'], 
                      capture_output=True, timeout=1)
        
        # Wait for devices to be discovered
        time.sleep(10)
        
        # Get devices
        result = subprocess.run(['sudo', 'bluetoothctl', 'devices'], 
                              capture_output=True, text=True, timeout=5)
        
        # Stop scanning
        subprocess.run(['sudo', 'bluetoothctl', 'scan', 'off'], 
                      capture_output=True, timeout=1)
        
        devices = []
        paired_addresses = set()
        
        # Get already paired devices to exclude them
        paired_result = subprocess.run(['sudo', 'bluetoothctl', 'paired-devices'],
                                      capture_output=True, text=True, timeout=5)
        for line in paired_result.stdout.split('\n'):
            if 'Device' in line:
                parts = line.split(' ', 2)
                if len(parts) >= 2:
                    paired_addresses.add(parts[1])
        
        # Parse discovered devices
        for line in result.stdout.split('\n'):
            if 'Device' in line:
                parts = line.split(' ', 2)
                if len(parts) >= 3:
                    address = parts[1]
                    if address not in paired_addresses:
                        name = parts[2] if len(parts) > 2 else 'Unknown'
                        devices.append({'address': address, 'name': name})
        
        return jsonify({'success': True, 'devices': devices})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/pair', methods=['POST'])
def bluetooth_pair():
    """Pair with a Bluetooth device"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    address = data.get('address')
    
    if not address:
        return jsonify({'error': 'No address provided'}), 400
    
    try:
        # Trust the device
        subprocess.run(['sudo', 'bluetoothctl', 'trust', address], 
                      capture_output=True, check=False)
        
        # Pair with the device
        result = subprocess.run(['sudo', 'bluetoothctl', 'pair', address],
                              capture_output=True, text=True, timeout=30)
        
        if 'successful' in result.stdout.lower():
            # Connect to the device
            subprocess.run(['sudo', 'bluetoothctl', 'connect', address],
                         capture_output=True, timeout=10)
            return jsonify({'success': True, 'message': 'Device paired and connected'})
        else:
            return jsonify({'success': False, 'message': 'Pairing failed: ' + result.stdout})
    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Pairing timeout'}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/connect', methods=['POST'])
def bluetooth_connect():
    """Connect to a paired Bluetooth device"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    address = data.get('address')
    
    if not address:
        return jsonify({'error': 'No address provided'}), 400
    
    try:
        result = subprocess.run(['sudo', 'bluetoothctl', 'connect', address],
                              capture_output=True, text=True, timeout=10)
        
        if 'successful' in result.stdout.lower():
            return jsonify({'success': True, 'message': 'Device connected'})
        else:
            return jsonify({'success': False, 'message': 'Connection failed'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/disconnect', methods=['POST'])
def bluetooth_disconnect():
    """Disconnect from a Bluetooth device"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    address = data.get('address')
    
    if not address:
        return jsonify({'error': 'No address provided'}), 400
    
    try:
        subprocess.run(['sudo', 'bluetoothctl', 'disconnect', address],
                      capture_output=True, timeout=5)
        return jsonify({'success': True, 'message': 'Device disconnected'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/remove', methods=['POST'])
def bluetooth_remove():
    """Remove a paired Bluetooth device"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    address = data.get('address')
    
    if not address:
        return jsonify({'error': 'No address provided'}), 400
    
    try:
        # Disconnect first if connected
        subprocess.run(['sudo', 'bluetoothctl', 'disconnect', address],
                      capture_output=True, timeout=5)
        
        # Remove the device
        subprocess.run(['sudo', 'bluetoothctl', 'remove', address],
                      capture_output=True, timeout=5)
        
        return jsonify({'success': True, 'message': 'Device removed'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/toggle', methods=['POST'])
def bluetooth_toggle():
    """Enable or disable Bluetooth"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Check current status
        result = subprocess.run(['sudo', 'systemctl', 'is-active', 'bluetooth'],
                              capture_output=True, text=True)
        is_active = result.stdout.strip() == 'active'
        
        if is_active:
            # Disable Bluetooth
            subprocess.run(['sudo', 'systemctl', 'stop', 'bluetooth'], check=False)
            subprocess.run(['sudo', 'rfkill', 'block', 'bluetooth'], check=False)
            return jsonify({'success': True, 'message': 'Bluetooth disabled'})
        else:
            # Enable Bluetooth
            subprocess.run(['sudo', 'rfkill', 'unblock', 'bluetooth'], check=False)
            subprocess.run(['sudo', 'systemctl', 'start', 'bluetooth'], check=False)
            time.sleep(2)
            # Set up audio sink
            subprocess.run(['sudo', 'bluetoothctl', 'power', 'on'], check=False)
            subprocess.run(['sudo', 'bluetoothctl', 'agent', 'on'], check=False)
            subprocess.run(['sudo', 'bluetoothctl', 'default-agent'], check=False)
            return jsonify({'success': True, 'message': 'Bluetooth enabled'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/logs/<log_type>')
def get_logs(log_type):
    """Get system logs"""
    if 'logged_in' not in session:
        return 'Not authenticated', 401
    
    lines = request.args.get('lines', '100')
    
    try:
        if log_type == 'player':
            # Get player service logs
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-player', '-n', lines, '--no-pager'],
                                  capture_output=True, text=True)
            return result.stdout or "No player logs available"
            
        elif log_type == 'admin':
            # Get admin panel logs
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-admin', '-n', lines, '--no-pager'],
                                  capture_output=True, text=True)
            return result.stdout or "No admin panel logs available"
            
        elif log_type == 'nginx':
            # Get nginx error logs
            result = subprocess.run(['sudo', 'tail', '-n', lines, '/var/log/nginx/error.log'],
                                  capture_output=True, text=True)
            return result.stdout or "No nginx logs available"
            
        elif log_type == 'system':
            # Get boot logs
            result = subprocess.run(['sudo', 'journalctl', '-b', '-n', lines, '--no-pager'],
                                  capture_output=True, text=True)
            return result.stdout or "No system logs available"
            
        elif log_type == 'auth':
            # Get authentication logs
            result = subprocess.run(['sudo', 'tail', '-n', lines, '/var/log/auth.log'],
                                  capture_output=True, text=True)
            return result.stdout or "No auth logs available"
            
        elif log_type == 'all':
            # Get all recent logs
            logs = []
            logs.append("=== PLAYER LOGS ===")
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-player', '-n', '50', '--no-pager'],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No player logs")
            
            logs.append("\n=== ADMIN PANEL LOGS ===")
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-admin', '-n', '50', '--no-pager'],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No admin logs")
            
            logs.append("\n=== RECENT SYSTEM LOGS ===")
            result = subprocess.run(['sudo', 'journalctl', '-n', '50', '--no-pager'],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No system logs")
            
            return '\n'.join(logs)
            
        else:
            return "Invalid log type", 400
            
    except Exception as e:
        return f"Error reading logs: {str(e)}", 500

@app.route('/api/logs/clear', methods=['POST'])
def clear_logs():
    """Clear old log files"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Rotate logs
        subprocess.run(['sudo', 'journalctl', '--rotate'], check=False)
        subprocess.run(['sudo', 'journalctl', '--vacuum-time=1d'], check=False)
        
        # Clear nginx logs
        subprocess.run(['sudo', 'truncate', '-s', '0', '/var/log/nginx/error.log'], check=False)
        subprocess.run(['sudo', 'truncate', '-s', '0', '/var/log/nginx/access.log'], check=False)
        
        return jsonify({'success': True, 'message': 'Old logs cleared'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/logs/download')
def download_logs():
    """Download all logs as a text file"""
    if 'logged_in' not in session:
        return 'Not authenticated', 401
    
    try:
        from datetime import datetime
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        logs = []
        logs.append(f"Spotify Kids Manager - System Logs Export\n")
        logs.append(f"Generated: {datetime.now()}\n")
        logs.append("="*60 + "\n\n")
        
        # Collect all logs
        logs.append("PLAYER SERVICE LOGS\n" + "="*40 + "\n")
        result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-player', '-n', '500', '--no-pager'],
                              capture_output=True, text=True)
        logs.append(result.stdout or "No logs available")
        
        logs.append("\n\nADMIN PANEL LOGS\n" + "="*40 + "\n")
        result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-admin', '-n', '500', '--no-pager'],
                              capture_output=True, text=True)
        logs.append(result.stdout or "No logs available")
        
        logs.append("\n\nSYSTEM BOOT LOGS\n" + "="*40 + "\n")
        result = subprocess.run(['sudo', 'journalctl', '-b', '-n', '500', '--no-pager'],
                              capture_output=True, text=True)
        logs.append(result.stdout or "No logs available")
        
        # Create response
        response = Response('\n'.join(logs), mimetype='text/plain')
        response.headers['Content-Disposition'] = f'attachment; filename=spotify_logs_{timestamp}.txt'
        return response
        
    except Exception as e:
        return f"Error generating log file: {str(e)}", 500

import time

if __name__ == '__main__':
    os.makedirs(CONFIG_DIR, exist_ok=True)
    app.run(host='0.0.0.0', port=5001, debug=False)