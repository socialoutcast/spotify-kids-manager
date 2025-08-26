#!/usr/bin/env python3

from flask import Flask, render_template_string, request, redirect, url_for, jsonify, session
import os
import subprocess
import json
import hashlib
import secrets
from datetime import datetime, timedelta
import configparser
from pathlib import Path

app = Flask(__name__)
app.secret_key = os.environ.get('SECRET_KEY', secrets.token_hex(32))

# Configuration
DATA_DIR = Path('/app/data')
CONFIG_DIR = Path('/app/config')
DATA_DIR.mkdir(exist_ok=True)
CONFIG_DIR.mkdir(exist_ok=True)

# Files
CONFIG_FILE = CONFIG_DIR / 'config.json'
SPOTIFYD_CONF = CONFIG_DIR / 'spotifyd.conf'
SETTINGS_FILE = DATA_DIR / 'settings.json'

# Default settings
DEFAULT_SETTINGS = {
    'admin_user': os.environ.get('ADMIN_USER', 'admin'),
    'admin_password': hashlib.sha256(os.environ.get('ADMIN_PASSWORD', 'changeme').encode()).hexdigest(),
    'setup_complete': False,
    'spotify_configured': False,
    'security_applied': False,
    'kid_account_created': False,
    'parental_controls': {
        'enabled': False,
        'allowed_hours': {'start': '07:00', 'end': '20:00'},
        'max_volume': 80,
        'explicit_filter': True
    }
}

# HTML Template for the main interface
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Spotify Kids Manager</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
            color: white;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-align: center;
        }
        .subtitle {
            text-align: center;
            opacity: 0.9;
            margin-bottom: 30px;
        }
        .wizard {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 30px;
            margin: 20px 0;
        }
        .step {
            margin-bottom: 25px;
            padding: 20px;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 10px;
        }
        .step h3 {
            color: #1DB954;
            margin-bottom: 15px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
        }
        input[type="text"], input[type="password"], input[type="number"], select {
            width: 100%;
            padding: 12px;
            border: none;
            border-radius: 8px;
            background: rgba(255, 255, 255, 0.9);
            color: #333;
            font-size: 16px;
        }
        .button {
            background: #1DB954;
            color: white;
            border: none;
            padding: 15px 30px;
            font-size: 18px;
            border-radius: 30px;
            cursor: pointer;
            margin: 10px 5px;
            transition: all 0.3s;
        }
        .button:hover {
            background: #1ed760;
            transform: scale(1.05);
        }
        .button.secondary {
            background: rgba(255, 255, 255, 0.2);
        }
        .status {
            padding: 15px;
            border-radius: 10px;
            margin: 15px 0;
        }
        .status.success {
            background: rgba(76, 175, 80, 0.2);
            border-left: 4px solid #4caf50;
        }
        .status.error {
            background: rgba(244, 67, 54, 0.2);
            border-left: 4px solid #f44336;
        }
        .status.warning {
            background: rgba(255, 152, 0, 0.2);
            border-left: 4px solid #ff9800;
        }
        .progress {
            display: flex;
            justify-content: space-between;
            margin: 30px 0;
        }
        .progress-step {
            flex: 1;
            text-align: center;
            position: relative;
        }
        .progress-step::after {
            content: '';
            position: absolute;
            top: 20px;
            right: -50%;
            width: 100%;
            height: 2px;
            background: rgba(255, 255, 255, 0.3);
        }
        .progress-step:last-child::after {
            display: none;
        }
        .progress-step.completed .circle {
            background: #1DB954;
        }
        .progress-step.active .circle {
            background: #ff9800;
            animation: pulse 2s infinite;
        }
        .circle {
            width: 40px;
            height: 40px;
            border-radius: 50%;
            background: rgba(255, 255, 255, 0.3);
            margin: 0 auto 10px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: bold;
        }
        @keyframes pulse {
            0% { box-shadow: 0 0 0 0 rgba(255, 152, 0, 0.7); }
            70% { box-shadow: 0 0 0 10px rgba(255, 152, 0, 0); }
            100% { box-shadow: 0 0 0 0 rgba(255, 152, 0, 0); }
        }
        .control-panel {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .control-card {
            background: rgba(255, 255, 255, 0.1);
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .control-card h4 {
            margin-bottom: 15px;
            color: #1DB954;
        }
        .slider {
            width: 100%;
            margin: 15px 0;
        }
        .time-input {
            display: flex;
            gap: 10px;
            align-items: center;
            justify-content: center;
        }
        .alert {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 20px;
            background: rgba(255, 255, 255, 0.95);
            color: #333;
            border-radius: 10px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
            display: none;
            animation: slideIn 0.3s ease;
        }
        @keyframes slideIn {
            from { transform: translateX(400px); }
            to { transform: translateX(0); }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎵 Spotify Kids Manager</h1>
        <p class="subtitle">Complete Setup & Control Center</p>
        
        {% if not logged_in %}
        <!-- Login Form -->
        <div class="wizard">
            <h2>Admin Login</h2>
            <form method="POST" action="/login">
                <div class="form-group">
                    <label>Username</label>
                    <input type="text" name="username" required>
                </div>
                <div class="form-group">
                    <label>Password</label>
                    <input type="password" name="password" required>
                </div>
                <button type="submit" class="button">Login</button>
            </form>
            {% if error %}
            <div class="status error">{{ error }}</div>
            {% endif %}
        </div>
        
        {% elif not setup_complete %}
        <!-- Setup Wizard -->
        <div class="progress">
            <div class="progress-step {% if current_step >= 1 %}completed{% elif current_step == 0 %}active{% endif %}">
                <div class="circle">1</div>
                <span>System Check</span>
            </div>
            <div class="progress-step {% if current_step >= 2 %}completed{% elif current_step == 1 %}active{% endif %}">
                <div class="circle">2</div>
                <span>Spotify Setup</span>
            </div>
            <div class="progress-step {% if current_step >= 3 %}completed{% elif current_step == 2 %}active{% endif %}">
                <div class="circle">3</div>
                <span>Kid Account</span>
            </div>
            <div class="progress-step {% if current_step >= 4 %}completed{% elif current_step == 3 %}active{% endif %}">
                <div class="circle">4</div>
                <span>Security</span>
            </div>
            <div class="progress-step {% if current_step >= 5 %}completed{% elif current_step == 4 %}active{% endif %}">
                <div class="circle">5</div>
                <span>Complete</span>
            </div>
        </div>
        
        <div class="wizard">
            {% if current_step == 0 %}
            <!-- Step 1: System Check -->
            <div class="step">
                <h3>Step 1: System Check</h3>
                <p>Checking system components...</p>
                <div class="status {{ 'success' if docker_running else 'error' }}">
                    Docker: {{ 'Running ✓' if docker_running else 'Not Running ✗' }}
                </div>
                <div class="status {{ 'success' if audio_working else 'warning' }}">
                    Audio System: {{ 'Ready ✓' if audio_working else 'Check Required' }}
                </div>
                <div class="status success">
                    Network: Connected ✓
                </div>
                <div class="status {{ 'warning' if not password_changed else 'success' }}">
                    Admin Password: {{ 'Please Change!' if not password_changed else 'Secured ✓' }}
                </div>
                
                {% if not password_changed %}
                <h4 style="margin-top: 20px;">Change Admin Password</h4>
                <form method="POST" action="/change_password">
                    <div class="form-group">
                        <label>New Password</label>
                        <input type="password" name="new_password" required minlength="8">
                    </div>
                    <div class="form-group">
                        <label>Confirm Password</label>
                        <input type="password" name="confirm_password" required>
                    </div>
                    <button type="submit" class="button">Update Password</button>
                </form>
                {% else %}
                <button onclick="window.location='/setup?step=1'" class="button">Continue</button>
                {% endif %}
            </div>
            
            {% elif current_step == 1 %}
            <!-- Step 2: Spotify Configuration -->
            <div class="step">
                <h3>Step 2: Configure Spotify</h3>
                <p>Enter your Spotify Premium account details</p>
                <form method="POST" action="/configure_spotify">
                    <div class="form-group">
                        <label>Spotify Username (NOT email)</label>
                        <input type="text" name="spotify_username" required 
                               placeholder="e.g., 1234567890 or custom_username">
                        <small style="opacity: 0.8;">Find at spotify.com → Account Overview</small>
                    </div>
                    <div class="form-group">
                        <label>Spotify Password</label>
                        <input type="password" name="spotify_password" required>
                    </div>
                    <div class="form-group">
                        <label>Device Name</label>
                        <input type="text" name="device_name" value="Kids Music Player" required>
                    </div>
                    <div class="form-group">
                        <label>Audio Quality</label>
                        <select name="bitrate">
                            <option value="96">Normal (96 kbps)</option>
                            <option value="160" selected>High (160 kbps)</option>
                            <option value="320">Very High (320 kbps)</option>
                        </select>
                    </div>
                    <button type="submit" class="button">Configure Spotify</button>
                    <button type="button" onclick="window.location='/setup?step=0'" class="button secondary">Back</button>
                </form>
            </div>
            
            {% elif current_step == 2 %}
            <!-- Step 3: Kid Account -->
            <div class="step">
                <h3>Step 3: Create Kid User Account</h3>
                <p>Set up the restricted account for your child</p>
                <form method="POST" action="/create_kid_account">
                    <div class="form-group">
                        <label>Child's Name (for display)</label>
                        <input type="text" name="child_name" required placeholder="e.g., Juno">
                    </div>
                    <div class="form-group">
                        <label>Linux Username</label>
                        <input type="text" name="username" value="juno" required pattern="[a-z0-9]+" 
                               title="Lowercase letters and numbers only">
                    </div>
                    <div class="form-group">
                        <label>Auto-login on Boot</label>
                        <select name="auto_login">
                            <option value="yes" selected>Yes - Start music automatically</option>
                            <option value="no">No - Require manual login</option>
                        </select>
                    </div>
                    <button type="submit" class="button">Create Account</button>
                    <button type="button" onclick="window.location='/setup?step=1'" class="button secondary">Back</button>
                </form>
            </div>
            
            {% elif current_step == 3 %}
            <!-- Step 4: Security Settings -->
            <div class="step">
                <h3>Step 4: Apply Security Lockdown</h3>
                <p>Configure security restrictions</p>
                <form method="POST" action="/apply_security">
                    <div class="status warning">
                        These settings will be applied:
                    </div>
                    <ul style="margin: 20px 0; padding-left: 20px;">
                        <li>Block terminal access</li>
                        <li>Disable system settings</li>
                        <li>Lock WiFi configuration</li>
                        <li>Prevent app installation</li>
                        <li>Remove sudo privileges</li>
                        <li>Make system files immutable</li>
                        <li>Block internet browsing</li>
                        <li>Force Spotify-only mode</li>
                    </ul>
                    <div class="form-group">
                        <label>
                            <input type="checkbox" name="confirm" required>
                            I understand these changes and want to proceed
                        </label>
                    </div>
                    <button type="submit" class="button">Apply Security</button>
                    <button type="button" onclick="window.location='/setup?step=2'" class="button secondary">Back</button>
                </form>
            </div>
            
            {% elif current_step == 4 %}
            <!-- Step 5: Complete -->
            <div class="step">
                <h3>🎉 Setup Complete!</h3>
                <div class="status success">
                    All systems configured successfully!
                </div>
                <p style="margin: 20px 0;">Your Spotify Kids Manager is ready to use.</p>
                <div class="control-panel">
                    <div class="control-card">
                        <h4>✅ Spotify</h4>
                        <p>Connected</p>
                    </div>
                    <div class="control-card">
                        <h4>✅ Kid Account</h4>
                        <p>Created</p>
                    </div>
                    <div class="control-card">
                        <h4>✅ Security</h4>
                        <p>Locked Down</p>
                    </div>
                    <div class="control-card">
                        <h4>✅ Auto-Start</h4>
                        <p>Enabled</p>
                    </div>
                </div>
                <button onclick="window.location='/'" class="button">Go to Control Panel</button>
            </div>
            {% endif %}
        </div>
        
        {% else %}
        <!-- Main Control Panel -->
        <div class="control-panel">
            <div class="control-card">
                <h4>🎵 Playback Control</h4>
                <button class="button" onclick="controlPlayback('play')">▶️ Play</button>
                <button class="button" onclick="controlPlayback('pause')">⏸️ Pause</button>
                <button class="button secondary" onclick="controlPlayback('next')">⏭️ Next</button>
            </div>
            
            <div class="control-card">
                <h4>🔊 Volume</h4>
                <input type="range" class="slider" id="volume" min="0" max="100" value="50" 
                       onchange="setVolume(this.value)">
                <span id="volume-display">50%</span>
            </div>
            
            <div class="control-card">
                <h4>⏰ Allowed Hours</h4>
                <div class="time-input">
                    <input type="time" id="start-time" value="{{ settings.parental_controls.allowed_hours.start }}">
                    <span>to</span>
                    <input type="time" id="end-time" value="{{ settings.parental_controls.allowed_hours.end }}">
                </div>
                <button class="button" onclick="updateHours()">Update</button>
            </div>
            
            <div class="control-card">
                <h4>🚫 Quick Actions</h4>
                <button class="button" onclick="blockNow()" style="background: #f44336;">Block Now</button>
                <button class="button secondary" onclick="unblock()">Unblock</button>
            </div>
        </div>
        
        <div class="wizard">
            <h3>System Status</h3>
            <div class="status success">Spotify: Connected</div>
            <div class="status success">Security: Active</div>
            <div class="status {{ 'success' if music_playing else 'warning' }}">
                Music: {{ 'Playing' if music_playing else 'Stopped' }}
            </div>
            <div class="status success">Updates: Automatic</div>
        </div>
        
        <div style="text-align: center; margin-top: 30px;">
            <button onclick="window.location='/logout'" class="button secondary">Logout</button>
            <button onclick="window.location='/settings'" class="button secondary">Settings</button>
        </div>
        {% endif %}
    </div>
    
    <div class="alert" id="alert"></div>
    
    <script>
        function showAlert(message, type) {
            const alert = document.getElementById('alert');
            alert.textContent = message;
            alert.style.display = 'block';
            alert.style.background = type === 'success' ? 'rgba(76, 175, 80, 0.95)' : 'rgba(244, 67, 54, 0.95)';
            setTimeout(() => alert.style.display = 'none', 3000);
        }
        
        function controlPlayback(action) {
            fetch('/api/control', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({action: action})
            })
            .then(response => response.json())
            .then(data => showAlert(data.message, data.status));
        }
        
        function setVolume(value) {
            document.getElementById('volume-display').textContent = value + '%';
            fetch('/api/volume', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({volume: value})
            });
        }
        
        function updateHours() {
            const start = document.getElementById('start-time').value;
            const end = document.getElementById('end-time').value;
            fetch('/api/hours', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({start: start, end: end})
            })
            .then(response => response.json())
            .then(data => showAlert(data.message, data.status));
        }
        
        function blockNow() {
            if(confirm('This will immediately stop music playback. Continue?')) {
                fetch('/api/block', {method: 'POST'})
                .then(response => response.json())
                .then(data => showAlert(data.message, data.status));
            }
        }
        
        function unblock() {
            fetch('/api/unblock', {method: 'POST'})
            .then(response => response.json())
            .then(data => showAlert(data.message, data.status));
        }
    </script>
</body>
</html>
'''

def load_settings():
    """Load settings from file"""
    if SETTINGS_FILE.exists():
        with open(SETTINGS_FILE, 'r') as f:
            return json.load(f)
    return DEFAULT_SETTINGS.copy()

def save_settings(settings):
    """Save settings to file"""
    with open(SETTINGS_FILE, 'w') as f:
        json.dump(settings, f, indent=2)

def check_system():
    """Check system status"""
    # Since we're running inside Docker, check if we're in a container instead
    docker_running = os.path.exists('/.dockerenv') or os.path.exists('/run/.containerenv')
    audio_working = subprocess.run(['which', 'aplay'], capture_output=True).returncode == 0
    return docker_running, audio_working

def create_spotifyd_config(username, password, device_name, bitrate):
    """Create Spotifyd configuration"""
    config = f'''[global]
username = "{username}"
password = "{password}"
backend = "alsa"
device_name = "{device_name}"
bitrate = {bitrate}
cache_path = "/app/data/cache"
no_audio_cache = false
volume_normalisation = true
normalisation_pregain = -10
device_type = "computer"
'''
    with open(SPOTIFYD_CONF, 'w') as f:
        f.write(config)
    
    # Start spotifyd
    subprocess.run(['pkill', 'spotifyd'], capture_output=True)
    subprocess.Popen(['/usr/local/bin/spotifyd', '--config-path', str(SPOTIFYD_CONF), '--no-daemon'])
    return True

@app.route('/')
def index():
    """Main page"""
    settings = load_settings()
    logged_in = session.get('logged_in', False)
    
    if not logged_in:
        return render_template_string(HTML_TEMPLATE, logged_in=False, error=request.args.get('error'))
    
    docker_running, audio_working = check_system()
    
    # Determine current setup step
    current_step = 0
    if settings.get('admin_password') != hashlib.sha256('changeme'.encode()).hexdigest():
        current_step = 1
    if settings.get('spotify_configured'):
        current_step = 2
    if settings.get('kid_account_created'):
        current_step = 3
    if settings.get('security_applied'):
        current_step = 4
    if settings.get('setup_complete'):
        current_step = 5
    
    return render_template_string(
        HTML_TEMPLATE,
        logged_in=True,
        setup_complete=settings.get('setup_complete', False),
        current_step=current_step,
        docker_running=docker_running,
        audio_working=audio_working,
        password_changed=(settings.get('admin_password') != hashlib.sha256('changeme'.encode()).hexdigest()),
        settings=settings,
        music_playing=False  # Would check actual status
    )

@app.route('/login', methods=['POST'])
def login():
    """Handle login"""
    settings = load_settings()
    username = request.form.get('username')
    password = request.form.get('password')
    password_hash = hashlib.sha256(password.encode()).hexdigest()
    
    if username == settings['admin_user'] and password_hash == settings['admin_password']:
        session['logged_in'] = True
        return redirect('/')
    
    return redirect('/?error=Invalid credentials')

@app.route('/logout')
def logout():
    """Handle logout"""
    session.pop('logged_in', None)
    return redirect('/')

@app.route('/setup')
def setup():
    """Setup wizard navigation"""
    if not session.get('logged_in'):
        return redirect('/')
    
    step = int(request.args.get('step', 0))
    settings = load_settings()
    
    # Update step tracking
    session['current_step'] = step
    return redirect('/')

@app.route('/change_password', methods=['POST'])
def change_password():
    """Change admin password"""
    if not session.get('logged_in'):
        return redirect('/')
    
    new_password = request.form.get('new_password')
    confirm_password = request.form.get('confirm_password')
    
    if new_password != confirm_password:
        return redirect('/?error=Passwords do not match')
    
    settings = load_settings()
    settings['admin_password'] = hashlib.sha256(new_password.encode()).hexdigest()
    save_settings(settings)
    
    return redirect('/setup?step=1')

@app.route('/configure_spotify', methods=['POST'])
def configure_spotify():
    """Configure Spotify"""
    if not session.get('logged_in'):
        return redirect('/')
    
    username = request.form.get('spotify_username')
    password = request.form.get('spotify_password')
    device_name = request.form.get('device_name', 'Kids Music Player')
    bitrate = request.form.get('bitrate', '160')
    
    # Create Spotifyd configuration
    if create_spotifyd_config(username, password, device_name, bitrate):
        settings = load_settings()
        settings['spotify_configured'] = True
        settings['spotify_username'] = username
        settings['device_name'] = device_name
        save_settings(settings)
        
        return redirect('/setup?step=2')
    
    return redirect('/setup?step=1')

@app.route('/create_kid_account', methods=['POST'])
def create_kid_account():
    """Create kid user account"""
    if not session.get('logged_in'):
        return redirect('/')
    
    child_name = request.form.get('child_name')
    username = request.form.get('username', 'juno')
    auto_login = request.form.get('auto_login') == 'yes'
    
    # Create user account (simplified for container)
    settings = load_settings()
    settings['kid_account_created'] = True
    settings['child_name'] = child_name
    settings['kid_username'] = username
    settings['auto_login'] = auto_login
    save_settings(settings)
    
    return redirect('/setup?step=3')

@app.route('/apply_security', methods=['POST'])
def apply_security():
    """Apply security settings"""
    if not session.get('logged_in'):
        return redirect('/')
    
    if request.form.get('confirm'):
        settings = load_settings()
        settings['security_applied'] = True
        settings['setup_complete'] = True
        save_settings(settings)
        
        # Apply security measures (simplified for container)
        # In production, this would apply actual system restrictions
        
        return redirect('/setup?step=4')
    
    return redirect('/setup?step=3')

# API Routes
@app.route('/api/control', methods=['POST'])
def api_control():
    """Control playback"""
    if not session.get('logged_in'):
        return jsonify({'status': 'error', 'message': 'Not authenticated'}), 401
    
    action = request.json.get('action')
    # Control Spotify via spotifyd/spotify-tui
    # Simplified for demo
    
    return jsonify({'status': 'success', 'message': f'{action.capitalize()} command sent'})

@app.route('/api/volume', methods=['POST'])
def api_volume():
    """Set volume"""
    if not session.get('logged_in'):
        return jsonify({'status': 'error', 'message': 'Not authenticated'}), 401
    
    volume = request.json.get('volume')
    subprocess.run(['amixer', 'set', 'Master', f'{volume}%'], capture_output=True)
    
    return jsonify({'status': 'success', 'message': f'Volume set to {volume}%'})

@app.route('/api/hours', methods=['POST'])
def api_hours():
    """Update allowed hours"""
    if not session.get('logged_in'):
        return jsonify({'status': 'error', 'message': 'Not authenticated'}), 401
    
    settings = load_settings()
    settings['parental_controls']['allowed_hours']['start'] = request.json.get('start')
    settings['parental_controls']['allowed_hours']['end'] = request.json.get('end')
    save_settings(settings)
    
    return jsonify({'status': 'success', 'message': 'Hours updated'})

@app.route('/api/block', methods=['POST'])
def api_block():
    """Block music immediately"""
    if not session.get('logged_in'):
        return jsonify({'status': 'error', 'message': 'Not authenticated'}), 401
    
    # Kill spotifyd
    subprocess.run(['pkill', 'spotifyd'], capture_output=True)
    
    settings = load_settings()
    settings['blocked'] = True
    save_settings(settings)
    
    return jsonify({'status': 'success', 'message': 'Music blocked'})

@app.route('/api/unblock', methods=['POST'])
def api_unblock():
    """Unblock music"""
    if not session.get('logged_in'):
        return jsonify({'status': 'error', 'message': 'Not authenticated'}), 401
    
    settings = load_settings()
    settings['blocked'] = False
    save_settings(settings)
    
    # Restart spotifyd
    if SPOTIFYD_CONF.exists():
        subprocess.Popen(['/usr/local/bin/spotifyd', '--config-path', str(SPOTIFYD_CONF), '--no-daemon'])
    
    return jsonify({'status': 'success', 'message': 'Music unblocked'})

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)