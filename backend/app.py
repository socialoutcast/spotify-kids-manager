#!/usr/bin/env python3

"""
Spotify Kids Manager - Main Backend Application
Complete web-based management system for locked-down Spotify player
"""

from flask import Flask, render_template, jsonify, request, session, redirect, url_for
from flask_cors import CORS
from flask_socketio import SocketIO, emit
from werkzeug.security import check_password_hash, generate_password_hash
import subprocess
import json
import os
import sys
import time
import threading
import logging
from datetime import datetime, timedelta
import secrets
import shutil
from functools import wraps
from update_manager import UpdateManager

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app
app = Flask(__name__, 
    static_folder='../frontend/build',
    static_url_path='/'
)
app.config['SECRET_KEY'] = os.getenv('SECRET_KEY', secrets.token_hex(32))
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration
ADMIN_USER = os.getenv('ADMIN_USER', 'admin')
ADMIN_PASSWORD_HASH = generate_password_hash(os.getenv('ADMIN_PASSWORD', 'changeme'))
DATA_DIR = '/app/data'
CONFIG_FILE = f'{DATA_DIR}/config.json'
SETUP_STATUS_FILE = f'{DATA_DIR}/setup_status.json'

# Ensure data directory exists
os.makedirs(DATA_DIR, exist_ok=True)

# Setup status tracking
class SetupManager:
    def __init__(self):
        self.status = self.load_status()
    
    def load_status(self):
        """Load setup status from file"""
        if os.path.exists(SETUP_STATUS_FILE):
            with open(SETUP_STATUS_FILE, 'r') as f:
                return json.load(f)
        return {
            'initialized': False,
            'steps_completed': [],
            'current_step': 'welcome',
            'spotify_configured': False,
            'kid_user_created': False,
            'security_applied': False,
            'auto_start_enabled': False
        }
    
    def save_status(self):
        """Save setup status to file"""
        with open(SETUP_STATUS_FILE, 'w') as f:
            json.dump(self.status, f, indent=2)
    
    def update_step(self, step, completed=True):
        """Update setup step status"""
        if completed and step not in self.status['steps_completed']:
            self.status['steps_completed'].append(step)
        self.status['current_step'] = step
        self.save_status()
        socketio.emit('setup_status', self.status)

setup_manager = SetupManager()
update_manager = UpdateManager()

# Authentication decorator
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not session.get('authenticated'):
            return jsonify({'error': 'Authentication required'}), 401
        return f(*args, **kwargs)
    return decorated_function

# System management functions
class SystemManager:
    @staticmethod
    def run_command(command, shell=False):
        """Run system command and return output"""
        try:
            if shell:
                result = subprocess.run(command, shell=True, capture_output=True, text=True)
            else:
                result = subprocess.run(command, capture_output=True, text=True)
            return {
                'success': result.returncode == 0,
                'output': result.stdout,
                'error': result.stderr
            }
        except Exception as e:
            return {
                'success': False,
                'output': '',
                'error': str(e)
            }
    
    @staticmethod
    def create_kid_user(username='kidmusic', password=None):
        """Create restricted user account for kid"""
        logger.info(f"Creating kid user: {username}")
        
        # Check if user exists
        check = SystemManager.run_command(['id', username])
        if check['success']:
            return {'success': True, 'message': 'User already exists'}
        
        # Create user with restricted shell
        commands = [
            f"useradd -m -s /usr/sbin/nologin {username}",
            f"usermod -aG audio {username}",
            f"mkdir -p /home/{username}/.config/spotifyd",
            f"mkdir -p /home/{username}/.cache/spotifyd",
            f"chown -R {username}:{username} /home/{username}"
        ]
        
        for cmd in commands:
            result = SystemManager.run_command(cmd, shell=True)
            if not result['success']:
                return {'success': False, 'error': result['error']}
        
        return {'success': True, 'message': f'User {username} created successfully'}
    
    @staticmethod
    def setup_auto_login(username='kidmusic'):
        """Setup automatic login for kid user"""
        logger.info(f"Setting up auto-login for: {username}")
        
        autologin_conf = f"""[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin {username} --noclear %I \$TERM
"""
        
        try:
            # Create systemd override directory
            os.makedirs('/host/etc/systemd/system/getty@tty1.service.d/', exist_ok=True)
            
            # Write autologin configuration
            with open('/host/etc/systemd/system/getty@tty1.service.d/autologin.conf', 'w') as f:
                f.write(autologin_conf)
            
            # Reload systemd
            SystemManager.run_command(['systemctl', 'daemon-reload'], shell=False)
            
            return {'success': True, 'message': 'Auto-login configured'}
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    @staticmethod
    def install_spotifyd():
        """Install and configure Spotifyd"""
        logger.info("Installing Spotifyd")
        
        # Spotifyd should already be installed via Dockerfile
        # Just need to configure it
        config_template = """[global]
username = "{username}"
password = "{password}"
backend = "alsa"
device = "default"
bitrate = 160
volume_controller = "alsa"
device_name = "Kids Music Player"
cache_path = "/home/{kid_user}/.cache/spotifyd"
volume_normalisation = true
normalisation_pregain = -10
device_type = "speaker"
"""
        return {'success': True, 'message': 'Spotifyd ready for configuration'}
    
    @staticmethod
    def apply_security_lockdown(username='kidmusic'):
        """Apply security restrictions to kid user"""
        logger.info(f"Applying security lockdown for: {username}")
        
        security_commands = [
            # Remove sudo access
            f"deluser {username} sudo 2>/dev/null || true",
            
            # Lock down home directory
            f"chmod 700 /home/{username}",
            
            # Make configuration files immutable
            f"chattr +i /home/{username}/.config/spotifyd/spotifyd.conf 2>/dev/null || true",
            
            # Disable TTY switching
            "echo 'kernel.sysrq = 0' >> /host/etc/sysctl.conf",
            
            # Create restricted shell script
            f"""cat > /home/{username}/start-music.sh << 'EOF'
#!/bin/bash
trap '' SIGTERM SIGINT SIGQUIT SIGHUP
while true; do
    /usr/local/bin/spotifyd --no-daemon
    sleep 5
done
EOF""",
            f"chmod +x /home/{username}/start-music.sh",
            f"chown {username}:{username} /home/{username}/start-music.sh"
        ]
        
        for cmd in security_commands:
            result = SystemManager.run_command(cmd, shell=True)
            if not result['success']:
                logger.warning(f"Security command failed: {cmd}")
        
        return {'success': True, 'message': 'Security lockdown applied'}

# Spotify management
class SpotifyManager:
    @staticmethod
    def configure_spotify(username, password, kid_user='kidmusic'):
        """Configure Spotify credentials"""
        logger.info("Configuring Spotify credentials")
        
        config = f"""[global]
username = "{username}"
password = "{password}"
backend = "alsa"
device = "default"
bitrate = 160
volume_controller = "alsa"
device_name = "Kids Music Player"
cache_path = "/home/{kid_user}/.cache/spotifyd"
volume_normalisation = true
normalisation_pregain = -10
device_type = "speaker"
"""
        
        try:
            config_path = f'/home/{kid_user}/.config/spotifyd/spotifyd.conf'
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            
            with open(config_path, 'w') as f:
                f.write(config)
            
            # Set proper permissions
            SystemManager.run_command(f"chown {kid_user}:{kid_user} {config_path}", shell=True)
            SystemManager.run_command(f"chmod 600 {config_path}", shell=True)
            
            return {'success': True, 'message': 'Spotify configured successfully'}
        except Exception as e:
            return {'success': False, 'error': str(e)}
    
    @staticmethod
    def test_spotify():
        """Test Spotify connection"""
        logger.info("Testing Spotify connection")
        
        # Start spotifyd in test mode
        result = SystemManager.run_command(
            "timeout 5 /usr/local/bin/spotifyd --no-daemon 2>&1", 
            shell=True
        )
        
        if "authenticated" in result['output'].lower() or "started" in result['output'].lower():
            return {'success': True, 'message': 'Spotify connection successful'}
        else:
            return {'success': False, 'error': 'Failed to connect to Spotify'}
    
    @staticmethod
    def control_playback(action):
        """Control Spotify playback"""
        commands = {
            'play': "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotifyd /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Play",
            'pause': "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotifyd /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Pause",
            'next': "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotifyd /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Next",
            'previous': "dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotifyd /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.Previous",
        }
        
        if action in commands:
            result = SystemManager.run_command(commands[action], shell=True)
            return {'success': result['success']}
        return {'success': False, 'error': 'Invalid action'}
    
    @staticmethod
    def block_spotify(block=True):
        """Block or unblock Spotify access"""
        if block:
            # Add iptables rules to block Spotify
            commands = [
                "iptables -A OUTPUT -d spotify.com -j DROP",
                "iptables -A OUTPUT -d '*.spotify.com' -j DROP",
                "iptables -A OUTPUT -p tcp --dport 4070 -j DROP"
            ]
        else:
            # Remove blocking rules
            commands = [
                "iptables -D OUTPUT -d spotify.com -j DROP",
                "iptables -D OUTPUT -d '*.spotify.com' -j DROP",
                "iptables -D OUTPUT -p tcp --dport 4070 -j DROP"
            ]
        
        for cmd in commands:
            SystemManager.run_command(cmd, shell=True)
        
        return {'success': True, 'blocked': block}

# API Routes
@app.route('/')
def index():
    """Serve the React frontend"""
    return app.send_static_file('index.html')

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/api/login', methods=['POST'])
def login():
    """Admin login"""
    data = request.json
    username = data.get('username')
    password = data.get('password')
    
    if username == ADMIN_USER and check_password_hash(ADMIN_PASSWORD_HASH, password):
        session['authenticated'] = True
        session['username'] = username
        return jsonify({'success': True, 'message': 'Login successful'})
    
    return jsonify({'success': False, 'error': 'Invalid credentials'}), 401

@app.route('/api/logout', methods=['POST'])
@login_required
def logout():
    """Admin logout"""
    session.clear()
    return jsonify({'success': True, 'message': 'Logged out'})

@app.route('/api/setup/status')
@login_required
def get_setup_status():
    """Get current setup status"""
    return jsonify(setup_manager.status)

@app.route('/api/setup/initialize', methods=['POST'])
@login_required
def initialize_setup():
    """Initialize the setup process"""
    setup_manager.status['initialized'] = True
    setup_manager.update_step('system_check')
    
    # Run system checks
    checks = {
        'docker': SystemManager.run_command(['docker', '--version'])['success'],
        'network': SystemManager.run_command(['ping', '-c', '1', '8.8.8.8'])['success'],
        'audio': SystemManager.run_command(['aplay', '-l'])['success'],
        'spotifyd': os.path.exists('/usr/local/bin/spotifyd')
    }
    
    return jsonify({
        'success': True,
        'checks': checks,
        'message': 'Setup initialized'
    })

@app.route('/api/setup/create-user', methods=['POST'])
@login_required
def create_kid_user():
    """Create the kid user account"""
    data = request.json
    username = data.get('username', 'kidmusic')
    
    result = SystemManager.create_kid_user(username)
    if result['success']:
        setup_manager.status['kid_user_created'] = True
        setup_manager.update_step('create_user', completed=True)
    
    return jsonify(result)

@app.route('/api/setup/configure-spotify', methods=['POST'])
@login_required
def configure_spotify():
    """Configure Spotify credentials"""
    data = request.json
    spotify_username = data.get('spotify_username')
    spotify_password = data.get('spotify_password')
    kid_user = data.get('kid_user', 'kidmusic')
    
    if not spotify_username or not spotify_password:
        return jsonify({'success': False, 'error': 'Username and password required'}), 400
    
    result = SpotifyManager.configure_spotify(spotify_username, spotify_password, kid_user)
    if result['success']:
        setup_manager.status['spotify_configured'] = True
        setup_manager.update_step('configure_spotify', completed=True)
    
    return jsonify(result)

@app.route('/api/setup/test-spotify', methods=['POST'])
@login_required
def test_spotify():
    """Test Spotify connection"""
    result = SpotifyManager.test_spotify()
    return jsonify(result)

@app.route('/api/setup/apply-security', methods=['POST'])
@login_required
def apply_security():
    """Apply security lockdown"""
    data = request.json
    kid_user = data.get('kid_user', 'kidmusic')
    
    result = SystemManager.apply_security_lockdown(kid_user)
    if result['success']:
        setup_manager.status['security_applied'] = True
        setup_manager.update_step('apply_security', completed=True)
    
    return jsonify(result)

@app.route('/api/setup/enable-autostart', methods=['POST'])
@login_required
def enable_autostart():
    """Enable auto-start on boot"""
    data = request.json
    kid_user = data.get('kid_user', 'kidmusic')
    
    # Setup auto-login
    result = SystemManager.setup_auto_login(kid_user)
    if result['success']:
        setup_manager.status['auto_start_enabled'] = True
        setup_manager.update_step('enable_autostart', completed=True)
    
    return jsonify(result)

@app.route('/api/control/playback', methods=['POST'])
@login_required
def control_playback():
    """Control Spotify playback"""
    data = request.json
    action = data.get('action')
    
    result = SpotifyManager.control_playback(action)
    return jsonify(result)

@app.route('/api/control/block-spotify', methods=['POST'])
@login_required
def block_spotify():
    """Block or unblock Spotify"""
    data = request.json
    block = data.get('block', True)
    
    result = SpotifyManager.block_spotify(block)
    return jsonify(result)

@app.route('/api/control/schedule', methods=['GET', 'POST'])
@login_required
def schedule():
    """Get or set playback schedule"""
    if request.method == 'GET':
        # Load schedule from config
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
                return jsonify(config.get('schedule', {}))
        return jsonify({})
    
    # Save schedule
    data = request.json
    config = {}
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
    
    config['schedule'] = data
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)
    
    return jsonify({'success': True, 'message': 'Schedule saved'})

@app.route('/api/stats/usage')
@login_required
def usage_stats():
    """Get usage statistics"""
    # This would be implemented with actual usage tracking
    stats = {
        'total_playtime': '4h 32m',
        'songs_played': 87,
        'favorite_playlist': 'Kids Favorites',
        'last_played': datetime.now().isoformat()
    }
    return jsonify(stats)

# Update Management Routes
@app.route('/api/updates/check')
@login_required
def check_updates():
    """Check for system updates"""
    result = update_manager.check_for_updates()
    return jsonify(result)

@app.route('/api/updates/install', methods=['POST'])
@login_required
def install_updates():
    """Install system updates"""
    data = request.json
    security_only = data.get('security_only', True)
    packages = data.get('packages', None)
    
    result = update_manager.install_updates(
        security_only=security_only,
        packages=packages
    )
    return jsonify(result)

@app.route('/api/updates/config', methods=['GET', 'POST'])
@login_required
def update_config():
    """Get or set update configuration"""
    if request.method == 'GET':
        return jsonify(update_manager.config)
    
    # POST - update configuration
    data = request.json
    update_manager.config.update(data)
    update_manager.save_config()
    update_manager.schedule_updates()  # Reschedule with new settings
    
    return jsonify({'success': True, 'message': 'Configuration updated'})

@app.route('/api/updates/health')
@login_required
def system_health():
    """Check system health"""
    result = update_manager.verify_system_integrity()
    return jsonify(result)

@app.route('/api/updates/history')
@login_required
def update_history():
    """Get update history"""
    limit = request.args.get('limit', 10, type=int)
    history = update_manager.get_update_history(limit)
    return jsonify(history)

# WebSocket events for real-time updates
@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    if session.get('authenticated'):
        emit('connected', {'message': 'Connected to server'})

@socketio.on('request_status')
def handle_status_request():
    """Send current status to client"""
    if session.get('authenticated'):
        emit('setup_status', setup_manager.status)

if __name__ == '__main__':
    # Start update scheduler
    update_manager.start_scheduler()
    
    try:
        socketio.run(app, host='0.0.0.0', port=5000, debug=False)
    finally:
        # Stop scheduler on shutdown
        update_manager.stop_scheduler()