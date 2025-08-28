#!/usr/bin/env python3
"""
Spotify Web Player Server
Handles OAuth, serves the web interface, and bridges to raspotify/spotifyd
"""

from flask import Flask, request, jsonify, session, redirect, render_template, send_file
import spotipy
from spotipy.oauth2 import SpotifyOAuth
import os
import json
import subprocess
import time
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = os.urandom(24)

# Load Spotify OAuth Configuration from env file if it exists
env_file = '/opt/spotify-terminal/config/spotify.env'
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            if '=' in line:
                key, value = line.strip().split('=', 1)
                os.environ[key] = value

# Spotify OAuth Configuration
SPOTIFY_CLIENT_ID = os.getenv('SPOTIFY_CLIENT_ID', '')
SPOTIFY_CLIENT_SECRET = os.getenv('SPOTIFY_CLIENT_SECRET', '')
SPOTIFY_REDIRECT_URI = os.getenv('SPOTIFY_REDIRECT_URI', 'http://localhost:8888/callback')
SCOPE = '''
    user-read-playback-state
    user-modify-playback-state
    user-read-currently-playing
    playlist-read-private
    playlist-read-collaborative
    user-library-read
    user-library-modify
    user-read-recently-played
    streaming
    user-read-email
    user-read-private
'''

# Configuration file paths
CONFIG_FILE = '/opt/spotify-terminal/config/spotify.json'
LOCK_FILE = '/opt/spotify-terminal/data/device.lock'

def load_config():
    """Load Spotify configuration"""
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {}

def save_config(config):
    """Save Spotify configuration"""
    os.makedirs(os.path.dirname(CONFIG_FILE), exist_ok=True)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def get_spotify_client():
    """Get authenticated Spotify client"""
    config = load_config()
    
    # Check for saved credentials
    if 'username' in config and 'password' in config:
        # Use username/password for raspotify/spotifyd
        configure_backend(config['username'], config['password'])
    
    # Check for OAuth token
    if 'token_info' in session:
        token_info = session['token_info']
        
        # Check if token needs refresh
        if is_token_expired(token_info):
            sp_oauth = create_spotify_oauth()
            token_info = sp_oauth.refresh_access_token(token_info['refresh_token'])
            session['token_info'] = token_info
        
        return spotipy.Spotify(auth=token_info['access_token'])
    
    return None

def is_token_expired(token_info):
    """Check if token is expired"""
    now = int(time.time())
    return token_info['expires_at'] - now < 60

def create_spotify_oauth():
    """Create SpotifyOAuth object"""
    return SpotifyOAuth(
        client_id=SPOTIFY_CLIENT_ID,
        client_secret=SPOTIFY_CLIENT_SECRET,
        redirect_uri=SPOTIFY_REDIRECT_URI,
        scope=SCOPE,
        cache_path=None  # Don't cache to file
    )

def configure_backend(username, password):
    """Configure raspotify or spotifyd with credentials"""
    # Check which backend is available
    if os.path.exists('/etc/default/raspotify'):
        # Configure raspotify
        config_content = f'''# Raspotify configuration
OPTIONS="--username '{username}' --password '{password}' --backend alsa --device-name '{os.uname().nodename}' --bitrate 320"
BACKEND="alsa"
VOLUME_NORMALISATION="true"
NORMALISATION_PREGAIN="-10"
'''
        try:
            with open('/etc/default/raspotify', 'w') as f:
                f.write(config_content)
            subprocess.run(['sudo', 'systemctl', 'restart', 'raspotify'], check=True)
            return True
        except:
            pass
    
    elif os.path.exists('/usr/local/bin/spotifyd'):
        # Configure spotifyd
        config_dir = os.path.expanduser('~/.config/spotifyd')
        os.makedirs(config_dir, exist_ok=True)
        
        config_content = f'''[global]
username = {username}
password = {password}
backend = alsa
device_name = {os.uname().nodename}
bitrate = 320
cache_path = /tmp/spotifyd_cache
max_cache_size = 10000000000
volume_normalisation = true
normalisation_pregain = -10
'''
        try:
            with open(f'{config_dir}/spotifyd.conf', 'w') as f:
                f.write(config_content)
            
            # Restart spotifyd if running
            subprocess.run(['pkill', 'spotifyd'], capture_output=True)
            subprocess.Popen(['/usr/local/bin/spotifyd', '--no-daemon'], 
                           stdout=subprocess.DEVNULL, 
                           stderr=subprocess.DEVNULL)
            return True
        except:
            pass
    
    return False

@app.route('/')
def index():
    """Serve the main player interface"""
    return send_file('player.html')

@app.route('/api/player.js')
def serve_js():
    """Serve the player JavaScript"""
    return send_file('player.js', mimetype='application/javascript')

@app.route('/admin')
def admin():
    """Redirect to admin configuration"""
    return redirect('http://localhost:5001')

@app.route('/api/spotify/token')
def get_token():
    """Get current access token"""
    sp = get_spotify_client()
    
    if sp:
        token_info = session.get('token_info', {})
        return jsonify({
            'access_token': token_info.get('access_token'),
            'expires_in': token_info.get('expires_in', 3600),
            'username': session.get('username', 'User')
        })
    
    # Check for saved credentials
    config = load_config()
    if 'username' in config:
        return jsonify({
            'access_token': None,
            'username': config['username'],
            'needs_oauth': True
        })
    
    return jsonify({'error': 'Not authenticated'}), 401

@app.route('/api/spotify/refresh', methods=['POST'])
def refresh_token():
    """Refresh access token"""
    if 'token_info' in session:
        sp_oauth = create_spotify_oauth()
        token_info = sp_oauth.refresh_access_token(session['token_info']['refresh_token'])
        session['token_info'] = token_info
        
        return jsonify({
            'access_token': token_info['access_token'],
            'expires_in': token_info['expires_in']
        })
    
    return jsonify({'error': 'No refresh token'}), 401

@app.route('/auth')
def auth():
    """Start OAuth flow"""
    sp_oauth = create_spotify_oauth()
    auth_url = sp_oauth.get_authorize_url()
    return redirect(auth_url)

@app.route('/callback')
def callback():
    """OAuth callback"""
    sp_oauth = create_spotify_oauth()
    code = request.args.get('code')
    
    if code:
        token_info = sp_oauth.get_access_token(code)
        session['token_info'] = token_info
        
        # Get user info
        sp = spotipy.Spotify(auth=token_info['access_token'])
        user_info = sp.current_user()
        session['username'] = user_info['display_name'] or user_info['id']
        
        # Save to config
        config = load_config()
        config['oauth_configured'] = True
        save_config(config)
        
        return redirect('/')
    
    return jsonify({'error': 'Authorization failed'}), 401

@app.route('/api/spotify/configure', methods=['POST'])
def configure_spotify():
    """Configure Spotify credentials (username/password)"""
    data = request.json
    username = data.get('username')
    password = data.get('password')
    
    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400
    
    # Configure backend
    if configure_backend(username, password):
        # Save configuration
        config = load_config()
        config['username'] = username
        config['configured'] = True
        save_config(config)
        
        session['username'] = username
        
        return jsonify({'success': True})
    
    return jsonify({'error': 'Configuration failed'}), 500

@app.route('/api/device/lock', methods=['POST'])
def device_lock():
    """Lock/unlock device"""
    data = request.json
    locked = data.get('locked', False)
    
    if locked:
        open(LOCK_FILE, 'a').close()
    else:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    
    return jsonify({'success': True})

@app.route('/api/device/locked')
def is_locked():
    """Check if device is locked"""
    return jsonify({'locked': os.path.exists(LOCK_FILE)})

# Spotify API proxy endpoints - work with both OAuth and backend auth
@app.route('/api/proxy/player/devices')
def get_devices():
    """Get available Spotify devices"""
    sp = get_spotify_client()
    if sp:
        try:
            devices = sp.devices()
            return jsonify(devices)
        except Exception as e:
            pass
    
    # Fallback for backend auth - check if raspotify/spotifyd is running
    devices = {'devices': []}
    if subprocess.run(['pgrep', '-f', 'raspotify'], capture_output=True).returncode == 0:
        devices['devices'].append({
            'id': 'raspotify-local',
            'is_active': True,
            'name': os.uname().nodename,
            'type': 'Computer',
            'volume_percent': 100
        })
    elif subprocess.run(['pgrep', '-f', 'spotifyd'], capture_output=True).returncode == 0:
        devices['devices'].append({
            'id': 'spotifyd-local',
            'is_active': True,
            'name': os.uname().nodename,
            'type': 'Computer',
            'volume_percent': 100
        })
    return jsonify(devices)

@app.route('/api/proxy/player/recently-played')
def get_recent():
    """Get recently played tracks"""
    sp = get_spotify_client()
    if sp:
        try:
            return jsonify(sp.current_user_recently_played(limit=20))
        except:
            pass
    # Return empty for backend auth
    return jsonify({'items': []})

@app.route('/api/proxy/playlists')
def get_playlists():
    """Get user's playlists"""
    sp = get_spotify_client()
    if sp:
        try:
            return jsonify(sp.current_user_playlists(limit=50))
        except:
            pass
    return jsonify({'items': []})

@app.route('/api/proxy/playlist/<playlist_id>')
def get_playlist(playlist_id):
    """Get playlist details"""
    sp = get_spotify_client()
    if sp:
        try:
            return jsonify(sp.playlist(playlist_id))
        except:
            pass
    return jsonify({'error': 'Not available'}), 503

@app.route('/api/proxy/search')
def search():
    """Search Spotify"""
    query = request.args.get('q', '')
    sp = get_spotify_client()
    if sp:
        try:
            results = sp.search(q=query, type='track,album,artist', limit=20)
            return jsonify(results)
        except:
            pass
    return jsonify({'tracks': {'items': []}, 'albums': {'items': []}, 'artists': {'items': []}})

@app.route('/api/proxy/player/play', methods=['PUT'])
def play():
    """Play a track/playlist/album"""
    sp = get_spotify_client()
    data = request.json or {}
    
    if sp:
        try:
            device_id = data.get('device_id')
            uris = data.get('uris')
            context_uri = data.get('context_uri')
            
            if context_uri:
                sp.start_playback(device_id=device_id, context_uri=context_uri)
            elif uris:
                sp.start_playback(device_id=device_id, uris=uris)
            else:
                sp.start_playback(device_id=device_id)
            return jsonify({'success': True})
        except Exception as e:
            return jsonify({'error': str(e)}), 500
    
    # Backend control for raspotify/spotifyd
    if data.get('uris'):
        # Try to play via Spotify Connect using backend
        uri = data.get('uris')[0] if isinstance(data.get('uris'), list) else data.get('context_uri')
        if uri:
            # Send play command to backend
            subprocess.run(['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
                          '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.OpenUri',
                          f'string:{uri}'], capture_output=True)
    return jsonify({'success': True})

@app.route('/api/proxy/player/pause', methods=['PUT'])
def pause():
    """Pause playback"""
    sp = get_spotify_client()
    if sp:
        try:
            sp.pause_playback()
            return jsonify({'success': True})
        except:
            pass
    
    # Backend control
    subprocess.run(['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
                   '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.Pause'], capture_output=True)
    return jsonify({'success': True})

@app.route('/api/proxy/player/resume', methods=['PUT'])  
def resume():
    """Resume playback"""
    sp = get_spotify_client()
    if sp:
        try:
            sp.start_playback()
            return jsonify({'success': True})
        except:
            pass
    
    # Backend control
    subprocess.run(['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
                   '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.Play'], capture_output=True)
    return jsonify({'success': True})

@app.route('/api/proxy/player/next', methods=['POST'])
def next_track():
    """Skip to next track"""
    sp = get_spotify_client()
    if sp:
        try:
            sp.next_track()
            return jsonify({'success': True})
        except:
            pass
    
    # Backend control
    subprocess.run(['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
                   '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.Next'], capture_output=True)
    return jsonify({'success': True})

@app.route('/api/proxy/player/previous', methods=['POST'])
def previous_track():
    """Previous track"""
    sp = get_spotify_client()
    if sp:
        try:
            sp.previous_track()
            return jsonify({'success': True})
        except:
            pass
    
    # Backend control
    subprocess.run(['dbus-send', '--print-reply', '--dest=org.mpris.MediaPlayer2.spotify',
                   '/org/mpris/MediaPlayer2', 'org.mpris.MediaPlayer2.Player.Previous'], capture_output=True)
    return jsonify({'success': True})

@app.route('/api/proxy/player/currently-playing')
def currently_playing():
    """Get currently playing track"""
    sp = get_spotify_client()
    if sp:
        try:
            return jsonify(sp.current_playing())
        except:
            pass
    
    # Try to get from backend via MPRIS
    return jsonify(None), 204

@app.route('/api/proxy/player/shuffle', methods=['PUT'])
def set_shuffle():
    """Set shuffle state"""
    state = request.args.get('state', 'false') == 'true'
    sp = get_spotify_client()
    if sp:
        try:
            sp.shuffle(state)
        except:
            pass
    return jsonify({'success': True})

@app.route('/api/proxy/player/repeat', methods=['PUT'])
def set_repeat():
    """Set repeat state"""
    state = request.args.get('state', 'off')
    sp = get_spotify_client()
    if sp:
        try:
            sp.repeat(state)
        except:
            pass
    return jsonify({'success': True})

@app.route('/api/proxy/tracks/contains')
def check_saved_tracks():
    """Check if tracks are saved"""
    ids = request.args.get('ids', '')
    sp = get_spotify_client()
    if sp:
        try:
            return jsonify(sp.current_user_saved_tracks_contains(tracks=[ids]))
        except:
            pass
    return jsonify([False])

@app.route('/api/proxy/tracks', methods=['GET', 'PUT', 'DELETE'])
def handle_tracks():
    """Get saved tracks or save/remove tracks"""
    if request.method == 'GET':
        # Get saved tracks
        sp = get_spotify_client()
        if sp:
            try:
                limit = request.args.get('limit', 50, type=int)
                return jsonify(sp.current_user_saved_tracks(limit=limit))
            except:
                pass
        return jsonify({'items': []})
    else:
        # Save or remove tracks
        ids = request.args.get('ids', '')
        sp = get_spotify_client()
        if sp:
            try:
                if request.method == 'PUT':
                    sp.current_user_saved_tracks_add(tracks=[ids])
                else:
                    sp.current_user_saved_tracks_delete(tracks=[ids])
                return jsonify({'success': True})
            except:
                pass
        return jsonify({'success': False})

@app.route('/api/proxy/player/seek', methods=['PUT'])
def seek():
    """Seek to position"""
    position_ms = request.args.get('position_ms', 0, type=int)
    sp = get_spotify_client()
    if sp:
        try:
            sp.seek_track(position_ms)
            return jsonify({'success': True})
        except:
            pass
    return jsonify({'success': True})

@app.route('/api/proxy/player/volume', methods=['PUT'])
def set_volume():
    """Set volume"""
    volume_percent = request.args.get('volume_percent', 50, type=int)
    sp = get_spotify_client()
    if sp:
        try:
            sp.volume(volume_percent)
            return jsonify({'success': True})
        except:
            pass
    
    # Try system volume control for backend
    subprocess.run(['amixer', 'set', 'Master', f'{volume_percent}%'], capture_output=True)
    return jsonify({'success': True})

def setup_kiosk_browser():
    """Launch browser in kiosk mode for touchscreen"""
    # Kill any existing browser
    subprocess.run(['pkill', '-f', 'chromium'], capture_output=True)
    time.sleep(1)
    
    # Launch Chromium in kiosk mode
    cmd = [
        'chromium-browser',
        '--kiosk',
        '--noerrdialogs',
        '--disable-infobars',
        '--no-first-run',
        '--disable-features=TranslateUI',
        '--overscroll-history-navigation=disabled',
        '--disable-pinch',
        '--enable-touch-events',
        '--touch-events=enabled',
        '--disable-dev-tools',
        f'http://localhost:8080'
    ]
    
    # Set display if running with X
    env = os.environ.copy()
    env['DISPLAY'] = ':0'
    
    subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

if __name__ == '__main__':
    # Ensure directories exist
    os.makedirs('/opt/spotify-terminal/config', exist_ok=True)
    os.makedirs('/opt/spotify-terminal/data', exist_ok=True)
    
    # Check if running on touchscreen
    if os.path.exists('/dev/input/touchscreen') or 'DISPLAY' in os.environ:
        # Launch kiosk browser after a short delay
        import threading
        threading.Timer(3, setup_kiosk_browser).start()
    
    # Run Flask server on non-standard port
    app.run(host='0.0.0.0', port=8888, debug=False)