#!/usr/bin/env python3

from flask import Flask, request, jsonify, render_template_string, session, redirect, url_for
from flask_cors import CORS
from flask_socketio import SocketIO
from werkzeug.security import check_password_hash, generate_password_hash
import os
import json
import subprocess
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

# Routes
@app.route('/')
def index():
    config = load_config()
    return jsonify({
        "status": "Admin panel running",
        "device_locked": config.get('device_locked', False),
        "spotify_enabled": config.get('spotify_enabled', True),
        "logged_in": 'logged_in' in session
    })

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

@app.route('/api/system/info')
@login_required
def system_info():
    # Get basic system information
    try:
        uptime = subprocess.run(['uptime', '-p'], capture_output=True, text=True).stdout.strip()
    except:
        uptime = "Unknown"
    
    return jsonify({
        'version': '1.0.0',
        'uptime': uptime,
        'status': 'running'
    })

if __name__ == '__main__':
    # Use fallback directories if /opt is not writable
    if not os.access('/opt', os.W_OK):
        base_dir = os.path.expanduser('~/.spotify-terminal')
        CONFIG_FILE = os.path.join(base_dir, 'config/admin.json')
        LOCK_FILE = os.path.join(base_dir, 'data/device.lock')
        CLIENT_CONFIG = os.path.join(base_dir, 'config/client.conf')
    
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    os.makedirs(os.path.dirname(LOCK_FILE), exist_ok=True)
    os.makedirs(os.path.dirname(CLIENT_CONFIG), exist_ok=True)
    
    app.run(host='0.0.0.0', port=5001, debug=True)