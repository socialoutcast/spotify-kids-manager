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
            // Convert newlines to <br> for multi-line messages
            const formattedMessage = message.replace(/\n/g, '<br>');
            alertDiv.innerHTML = `<div class="alert ${type}">${formattedMessage}</div>`;
            // Keep error messages visible longer
            const timeout = type === 'error' ? 10000 : 5000;
            setTimeout(() => alertDiv.innerHTML = '', timeout);
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
            const checkbox = e.target;
            checkbox.disabled = true; // Disable during operation
            
            try {
                const response = await fetch('/api/device/lock', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({locked: e.target.checked})
                });
                
                if (response.ok) {
                    const result = await response.json();
                    showAlert(result.message || `Device ${e.target.checked ? 'locked' : 'unlocked'}`);
                } else {
                    showAlert('Failed to change device lock state', 'error');
                    checkbox.checked = !checkbox.checked; // Revert on error
                }
            } catch (err) {
                showAlert('Error communicating with device', 'error');
                checkbox.checked = !checkbox.checked;
            } finally {
                checkbox.disabled = false;
            }
        });
        
        // Spotify access toggle
        document.getElementById('spotifyAccess')?.addEventListener('change', async (e) => {
            const checkbox = e.target;
            checkbox.disabled = true; // Disable during operation
            
            try {
                const response = await fetch('/api/spotify/access', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({enabled: e.target.checked})
                });
                
                if (response.ok) {
                    const result = await response.json();
                    showAlert(result.message || `Spotify ${e.target.checked ? 'enabled' : 'disabled'}`);
                } else {
                    showAlert('Failed to change Spotify access', 'error');
                    checkbox.checked = !checkbox.checked; // Revert on error
                }
            } catch (err) {
                showAlert('Error communicating with service', 'error');
                checkbox.checked = !checkbox.checked;
            } finally {
                checkbox.disabled = false;
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
            
            // Show loading state
            const submitBtn = e.target.querySelector('button[type="submit"]');
            const originalText = submitBtn.textContent;
            submitBtn.textContent = 'Testing credentials...';
            submitBtn.disabled = true;
            
            try {
                const response = await fetch('/api/spotify/config', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({username, password, target_user})
                });
                
                const result = await response.json();
                
                if (response.ok) {
                    // Success message
                    let message = `✅ Spotify configured successfully! Using ${result.backend}`;
                    if (result.warning) {
                        message += `\n⚠️ ${result.warning}`;
                    }
                    showAlert(message);
                    loadSpotifyConfig();
                    document.getElementById('spotifyPassword').value = '';
                } else {
                    // Error with details
                    let errorMsg = result.error || 'Failed to configure Spotify';
                    if (result.details) {
                        errorMsg += '\n\n' + result.details;
                    }
                    showAlert(errorMsg, 'error');
                }
            } catch (err) {
                showAlert('Network error: Could not connect to server', 'error');
            } finally {
                submitBtn.textContent = originalText;
                submitBtn.disabled = false;
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
        
        # Lock the screen by:
        # 1. Kill any running browser/GUI
        subprocess.run(['pkill', '-f', 'chromium'], capture_output=True)
        subprocess.run(['pkill', '-f', 'spotify_server.py'], capture_output=True)
        
        # 2. Disable touchscreen input - find the actual touchscreen device
        # Get list of input devices and find touchscreen
        xinput_result = subprocess.run(['xinput', 'list'], capture_output=True, text=True)
        touchscreen_id = None
        if xinput_result.returncode == 0:
            for line in xinput_result.stdout.splitlines():
                if 'touchscreen' in line.lower() or 'touch' in line.lower():
                    # Extract device ID
                    import re
                    match = re.search(r'id=(\d+)', line)
                    if match:
                        touchscreen_id = match.group(1)
                        break
        
        if touchscreen_id:
            subprocess.run(['xinput', 'disable', touchscreen_id], capture_output=True)
        
        # 3. Black out the screen with a lock message
        lock_display_cmd = '''
DISPLAY=:0 xset dpms force off
'''
        subprocess.run(lock_display_cmd, shell=True, capture_output=True)
        
        message = "Device locked - touchscreen disabled"
    else:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
        
        # Unlock the screen by:
        # 1. Re-enable touchscreen - find the actual touchscreen device
        xinput_result = subprocess.run(['xinput', 'list'], capture_output=True, text=True)
        touchscreen_id = None
        if xinput_result.returncode == 0:
            for line in xinput_result.stdout.splitlines():
                if 'touchscreen' in line.lower() or 'touch' in line.lower():
                    import re
                    match = re.search(r'id=(\d+)', line)
                    if match:
                        touchscreen_id = match.group(1)
                        break
        
        if touchscreen_id:
            subprocess.run(['xinput', 'enable', touchscreen_id], capture_output=True)
        
        # 2. Wake the display
        subprocess.run(['DISPLAY=:0 xset dpms force on'], shell=True, capture_output=True)
        
        # 3. Restart the Spotify web player
        subprocess.Popen(['/opt/spotify-terminal/scripts/start-web-player.sh'], 
                        stdout=subprocess.DEVNULL, 
                        stderr=subprocess.DEVNULL)
        
        message = "Device unlocked - restarting Spotify player"
    
    return jsonify({"success": True, "message": message})

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
    
    if data['enabled']:
        # Enable Spotify - Launch the web player
        # 1. Kill any existing desktop sessions to clean up
        subprocess.run(['pkill', '-f', 'lxsession'], capture_output=True)
        subprocess.run(['pkill', '-f', 'pcmanfm'], capture_output=True)
        
        # 2. Start the Spotify web player in kiosk mode
        subprocess.Popen(['/opt/spotify-terminal/scripts/start-web-player.sh'], 
                        stdout=subprocess.DEVNULL, 
                        stderr=subprocess.DEVNULL)
        
        message = "Spotify enabled - launching player"
    else:
        # Disable Spotify - Close web app and show desktop
        # 1. Kill the web player and browser
        subprocess.run(['pkill', '-f', 'chromium'], capture_output=True)
        subprocess.run(['pkill', '-f', 'spotify_server.py'], capture_output=True)
        subprocess.run(['pkill', '-f', 'ncspot'], capture_output=True)
        subprocess.run(['pkill', 'raspotify'], capture_output=True)
        subprocess.run(['pkill', 'spotifyd'], capture_output=True)
        
        # 2. Start desktop environment for the spotify-kids user
        desktop_cmd = '''
su - spotify-kids -c "DISPLAY=:0 startlxde" &
'''
        subprocess.run(desktop_cmd, shell=True, capture_output=True)
        
        message = "Spotify disabled - desktop available"
    
    return jsonify({"success": True, "message": message})

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

def test_spotify_auth(username, password, backend):
    """Test Spotify authentication with the given credentials"""
    import tempfile
    import time
    from datetime import datetime
    
    # Log the authentication attempt
    log_dir = "/opt/spotify-terminal/data"
    os.makedirs(log_dir, exist_ok=True)
    log_file = f"{log_dir}/spotify-auth.log"
    
    with open(log_file, 'a') as f:
        f.write(f"\n[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Testing auth for user: {username}, backend: {backend}\n")
    
    if backend == "raspotify":
        # Test with librespot (raspotify's backend)
        test_cmd = [
            'timeout', '10',
            'librespot',
            '--username', username,
            '--password', password,
            '--backend', 'alsa',
            '--name', 'AuthTest',
            '--disable-audio-cache',
            '--onevent', 'echo'
        ]
        
        result = subprocess.run(test_cmd, capture_output=True, text=True)
        
        with open(log_file, 'a') as f:
            f.write(f"Raspotify test result: {result.returncode}\n")
            f.write(f"Stdout: {result.stdout[:500]}\n")
            f.write(f"Stderr: {result.stderr[:500]}\n")
        
        # Check for specific error messages
        if "Bad credentials" in result.stderr or "Authentication failed" in result.stderr:
            return {
                'success': False,
                'error': 'Invalid Spotify credentials',
                'details': 'Username or password is incorrect. Make sure to use your Spotify username (not email) and correct password.'
            }
        elif "Premium account is required" in result.stderr:
            return {
                'success': False,
                'error': 'Spotify Premium required',
                'details': 'This account does not have Spotify Premium. A Premium subscription is required.'
            }
        elif result.returncode == 124:  # Timeout
            # Timeout might mean it was trying to connect, which is actually good
            return {'success': True}
        elif result.returncode == 0 or "authenticated as" in result.stderr.lower():
            return {'success': True}
        else:
            return {
                'success': False,
                'error': 'Authentication test failed',
                'details': f'Unable to verify credentials. Error: {result.stderr[:200] if result.stderr else "Unknown error"}'
            }
            
    elif backend == "spotifyd":
        # Create a temporary config file for spotifyd test
        with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
            f.write(f'''[global]
username = {username}
password = {password}
backend = alsa
device_name = AuthTest
''')
            temp_config = f.name
        
        try:
            test_cmd = [
                'timeout', '10',
                '/usr/local/bin/spotifyd',
                '--config-path', temp_config,
                '--no-daemon'
            ]
            
            result = subprocess.run(test_cmd, capture_output=True, text=True)
            
            with open(log_file, 'a') as f:
                f.write(f"Spotifyd test result: {result.returncode}\n")
                f.write(f"Stdout: {result.stdout[:500]}\n")
                f.write(f"Stderr: {result.stderr[:500]}\n")
            
            if "Bad credentials" in result.stderr or "Authentication failed" in result.stderr:
                return {
                    'success': False,
                    'error': 'Invalid Spotify credentials',
                    'details': 'Username or password is incorrect.'
                }
            elif "Premium" in result.stderr:
                return {
                    'success': False,
                    'error': 'Spotify Premium required',
                    'details': 'A Premium subscription is required.'
                }
            elif result.returncode == 124:  # Timeout means it was running
                return {'success': True}
            else:
                return {'success': True}
        finally:
            os.unlink(temp_config)
    
    else:  # ncspot or unknown
        # For ncspot, we can't easily test without interactive mode
        # Just do basic validation
        if '@' in username:
            return {
                'success': False,
                'error': 'Invalid username format',
                'details': 'Please use your Spotify username, not your email address. You can find your username in Spotify account settings.'
            }
        
        # Basic check that credentials aren't empty
        if len(password) < 4:
            return {
                'success': False,
                'error': 'Password too short',
                'details': 'Please enter your Spotify password.'
            }
        
        with open(log_file, 'a') as f:
            f.write(f"Ncspot backend - basic validation passed\n")
        
        return {
            'success': True,
            'warning': 'Credentials saved but could not be fully verified with ncspot. They will be tested on first login.'
        }

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
    
    # Test authentication with Spotify before saving
    auth_test_result = test_spotify_auth(username, password, backend)
    if not auth_test_result['success']:
        return jsonify({
            "error": auth_test_result['error'],
            "details": auth_test_result.get('details', '')
        }), 401
    
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
    
    response_data = {
        "success": True, 
        "message": f"Spotify configured for {target_user} with username {username}", 
        "backend": backend, 
        "user": target_user
    }
    
    # Add warning if present from auth test
    if auth_test_result.get('warning'):
        response_data['warning'] = auth_test_result['warning']
    
    return jsonify(response_data)

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
    
    # Run the Flask app on port 5001 (will be proxied through nginx on 8080)
    app.run(host='0.0.0.0', port=5001, debug=False)
