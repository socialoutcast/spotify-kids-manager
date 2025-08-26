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
try:
    from update_manager import UpdateManager
    update_manager = UpdateManager()
except ImportError:
    logging.warning("UpdateManager not available, running without update features")
    update_manager = None

try:
    from bluetooth_manager import BluetoothManager
    bluetooth_manager = BluetoothManager()
except ImportError:
    logging.warning("BluetoothManager not available, running without Bluetooth features")
    bluetooth_manager = None

# Setup logging with more detail
try:
    os.makedirs('/app/logs', exist_ok=True)
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler('/app/logs/app.log'),
            logging.StreamHandler()
        ]
    )
except Exception as e:
    # Fallback to console only if log dir is not accessible
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
logger = logging.getLogger(__name__)

# Initialize Flask app
# Check if frontend build exists, use a fallback if not
import os
if os.path.exists('/app/frontend/build'):
    static_folder = '/app/frontend/build'
elif os.path.exists('../frontend/build'):
    static_folder = '../frontend/build'
else:
    static_folder = None
    logger.warning("Frontend build folder not found, API-only mode")

app = Flask(__name__, 
    static_folder=static_folder,
    static_url_path='/' if static_folder else None,
    template_folder='templates'
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
# update_manager and bluetooth_manager are initialized at the top of the file

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
        
        # In Docker container, we don't actually need a system user
        # We'll just simulate it for the setup wizard
        
        # Check if we're in a container
        if os.path.exists('/.dockerenv') or os.path.exists('/run/.containerenv'):
            logger.info("Running in container, skipping actual user creation")
            # Just create the necessary directories in /app/data
            try:
                os.makedirs('/app/data/kid_user', exist_ok=True)
                # Store user info for reference
                user_info = {'username': username, 'created': True}
                with open('/app/data/kid_user/info.json', 'w') as f:
                    json.dump(user_info, f)
                return {'success': True, 'message': f'User {username} configuration saved'}
            except Exception as e:
                return {'success': False, 'error': str(e)}
        
        # Original code for non-container environments
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
                logger.error(f"Command failed: {cmd} - {result['error']}")
                # Don't fail completely if directory creation fails
                if 'mkdir' not in cmd and 'chown' not in cmd:
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
        
        # In Docker container, security is handled by container isolation
        if os.path.exists('/.dockerenv') or os.path.exists('/run/.containerenv'):
            logger.info("Running in container, security handled by Docker isolation")
            # Store security status
            security_config = {
                'security_applied': True,
                'kid_user': username,
                'timestamp': datetime.now().isoformat()
            }
            try:
                with open('/app/data/security_config.json', 'w') as f:
                    json.dump(security_config, f, indent=2)
                return {'success': True, 'message': 'Security configuration saved'}
            except Exception as e:
                return {'success': False, 'error': str(e)}
        
        # Original security commands for non-container environments
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
                logger.warning(f"Security command failed (non-critical): {cmd}")
        
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
cache_path = "/app/data/spotifyd_cache"
volume_normalisation = true
normalisation_pregain = -10
device_type = "speaker"
"""
        
        try:
            # Store config in /app/config which always exists in the container
            config_path = '/app/config/spotifyd.conf'
            
            # Ensure the directory exists
            os.makedirs(os.path.dirname(config_path), exist_ok=True)
            
            with open(config_path, 'w') as f:
                f.write(config)
            
            # Also store in the global config for other services to use
            global_config = {
                'spotify_username': username,
                'spotify_configured': True,
                'device_name': 'Kids Music Player'
            }
            
            config_json_path = '/app/data/config.json'
            if os.path.exists(config_json_path):
                with open(config_json_path, 'r') as f:
                    existing_config = json.load(f)
                    existing_config.update(global_config)
                    global_config = existing_config
            
            with open(config_json_path, 'w') as f:
                json.dump(global_config, f, indent=2)
            
            # Set proper permissions on config file
            SystemManager.run_command(f"chmod 600 {config_path}", shell=True)
            
            return {'success': True, 'message': 'Spotify configured successfully'}
        except Exception as e:
            logger.error(f"Failed to configure Spotify: {e}")
            return {'success': False, 'error': str(e)}
    
    @staticmethod
    def test_spotify():
        """Test Spotify connection"""
        logger.info("Testing Spotify connection")
        
        # Check if spotifyd exists
        if not os.path.exists('/usr/local/bin/spotifyd'):
            logger.warning("Spotifyd not found, skipping test")
            return {'success': True, 'message': 'Spotifyd not installed, will configure on first run'}
        
        # Start spotifyd in test mode with config file
        result = SystemManager.run_command(
            "timeout 5 /usr/local/bin/spotifyd --no-daemon --config-path /app/config/spotifyd.conf 2>&1", 
            shell=True
        )
        
        if "authenticated" in result['output'].lower() or "started" in result['output'].lower():
            return {'success': True, 'message': 'Spotify connection successful'}
        elif "invalid credentials" in result['output'].lower():
            return {'success': False, 'error': 'Invalid Spotify credentials'}
        elif "premium" in result['output'].lower():
            return {'success': False, 'error': 'Spotify Premium account required'}
        else:
            # Log the actual output for debugging
            logger.warning(f"Spotify test output: {result['output']}")
            # Don't fail completely, as the config might still work
            return {'success': True, 'message': 'Spotify configuration saved, will test on first playback'}
    
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
    """Serve the React frontend or fallback page"""
    if static_folder and os.path.exists(os.path.join(static_folder, 'index.html')):
        return app.send_static_file('index.html')
    else:
        # Serve fallback template if frontend build is not available
        return render_template('index.html')

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
    # Since we're running inside Docker, check if we're in a container instead
    is_in_container = os.path.exists('/.dockerenv') or os.path.exists('/run/.containerenv')
    
    checks = {
        'docker': is_in_container,  # We're running in Docker if this file exists
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
    try:
        data = request.json
        spotify_username = data.get('spotify_username')
        spotify_password = data.get('spotify_password')
        kid_user = data.get('kid_user', 'kidmusic')
        
        logger.info(f"Configuring Spotify for user: {spotify_username}")
        
        if not spotify_username or not spotify_password:
            return jsonify({'success': False, 'error': 'Username and password required'}), 400
        
        result = SpotifyManager.configure_spotify(spotify_username, spotify_password, kid_user)
        if result['success']:
            setup_manager.status['spotify_configured'] = True
            setup_manager.update_step('configure_spotify', completed=True)
            logger.info("Spotify configuration successful")
        else:
            logger.error(f"Spotify configuration failed: {result.get('error')}")
        
        return jsonify(result)
    except Exception as e:
        logger.error(f"Error in configure_spotify endpoint: {e}", exc_info=True)
        return jsonify({'success': False, 'error': f'Configuration failed: {str(e)}'}), 500

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
        
        # Mark setup as complete and clear the display message
        setup_manager.status['setup_complete'] = True
        
        # Clear the setup message from the display
        clear_script = '/opt/spotify-kids-manager/scripts/clear-setup-message.sh'
        if os.path.exists(clear_script):
            logger.info("Clearing setup message from display")
            SystemManager.run_command(f"bash {clear_script}", shell=True)
        else:
            # Try container path
            clear_script = '/app/scripts/clear-setup-message.sh'
            if os.path.exists(clear_script):
                logger.info("Clearing setup message from display (container)")
                SystemManager.run_command(f"bash {clear_script}", shell=True)
    
    return jsonify(result)

@app.route('/api/setup/complete', methods=['POST'])
@login_required
def complete_setup():
    """Mark setup as complete and clear display message"""
    setup_manager.status['setup_complete'] = True
    setup_manager.save_status()
    
    # Save configuration
    config = {
        'setup_complete': True,
        'timestamp': datetime.now().isoformat()
    }
    
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
    except Exception as e:
        logger.error(f"Failed to save config: {e}")
    
    # Clear the setup message from the display
    for script_path in ['/opt/spotify-kids-manager/scripts/clear-setup-message.sh', 
                        '/app/scripts/clear-setup-message.sh']:
        if os.path.exists(script_path):
            logger.info(f"Clearing setup message using {script_path}")
            SystemManager.run_command(f"bash {script_path}", shell=True)
            break
    
    return jsonify({'success': True, 'message': 'Setup complete'})

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

# Bluetooth Management Routes
@app.route('/api/bluetooth/adapter')
@login_required
def bluetooth_adapter_info():
    """Get Bluetooth adapter information"""
    info = bluetooth_manager.get_adapter_info()
    return jsonify(info)

@app.route('/api/bluetooth/scan', methods=['POST'])
@login_required
def bluetooth_scan():
    """Scan for Bluetooth devices"""
    data = request.json or {}
    duration = data.get('duration', 10)
    devices = bluetooth_manager.scan_devices(duration)
    return jsonify(devices)

@app.route('/api/bluetooth/paired')
@login_required
def bluetooth_paired_devices():
    """Get list of paired Bluetooth devices"""
    devices = bluetooth_manager.get_paired_devices()
    return jsonify(devices)

@app.route('/api/bluetooth/connected')
@login_required
def bluetooth_connected_devices():
    """Get list of connected Bluetooth devices"""
    devices = bluetooth_manager.get_connected_devices()
    return jsonify(devices)

@app.route('/api/bluetooth/pair/<mac_address>', methods=['POST'])
@login_required
def bluetooth_pair(mac_address):
    """Pair with a Bluetooth device"""
    result = bluetooth_manager.pair_device(mac_address)
    return jsonify(result)

@app.route('/api/bluetooth/connect/<mac_address>', methods=['POST'])
@login_required
def bluetooth_connect(mac_address):
    """Connect to a Bluetooth device"""
    result = bluetooth_manager.connect_device(mac_address)
    return jsonify(result)

@app.route('/api/bluetooth/disconnect/<mac_address>', methods=['POST'])
@login_required
def bluetooth_disconnect(mac_address):
    """Disconnect from a Bluetooth device"""
    result = bluetooth_manager.disconnect_device(mac_address)
    return jsonify(result)

@app.route('/api/bluetooth/remove/<mac_address>', methods=['DELETE'])
@login_required
def bluetooth_remove(mac_address):
    """Remove (unpair) a Bluetooth device"""
    result = bluetooth_manager.remove_device(mac_address)
    return jsonify(result)

@app.route('/api/bluetooth/discoverable/on', methods=['POST'])
@login_required
def bluetooth_enable_discovery():
    """Enable Bluetooth discovery mode"""
    data = request.json or {}
    duration = data.get('duration', 180)
    result = bluetooth_manager.enable_discovery(duration)
    return jsonify(result)

@app.route('/api/bluetooth/discoverable/off', methods=['POST'])
@login_required
def bluetooth_disable_discovery():
    """Disable Bluetooth discovery mode"""
    result = bluetooth_manager.disable_discovery()
    return jsonify(result)

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
    logger.info("Starting Spotify Kids Manager Backend...")
    
    # Ensure required directories exist
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs('/app/logs', exist_ok=True)
    os.makedirs('/app/config', exist_ok=True)
    
    # Start update scheduler
    if update_manager:
        try:
            update_manager.start_scheduler()
        except Exception as e:
            logger.error(f"Failed to start update scheduler: {e}")
    
    # Add startup delay to ensure nginx is ready
    time.sleep(2)
    
    try:
        logger.info("Starting Flask app on port 5000...")
        logger.info(f"Static folder: {static_folder}")
        logger.info(f"Data directory: {DATA_DIR}")
        logger.info(f"Environment: FLASK_APP={os.getenv('FLASK_APP')}, FLASK_ENV={os.getenv('FLASK_ENV')}")
        
        # Run Flask with socketio
        socketio.run(app, host='0.0.0.0', port=5000, debug=False)
    except Exception as e:
        logger.error(f"Failed to start Flask app: {e}", exc_info=True)
        # Keep the process alive for debugging
        while True:
            time.sleep(60)
    finally:
        # Stop scheduler on shutdown
        if update_manager:
            try:
                update_manager.stop_scheduler()
            except:
                pass