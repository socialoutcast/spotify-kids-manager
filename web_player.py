#!/usr/bin/env python3

from flask import Flask, render_template_string, jsonify, request, session
from flask_cors import CORS
import spotipy
from spotipy.oauth2 import SpotifyOAuth
import os
import json
import time
import threading
import logging
from datetime import datetime, timedelta

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
CORS(app)

# Configuration
CONFIG_DIR = os.environ.get('SPOTIFY_CONFIG_DIR', '/opt/spotify-kids/config')
CACHE_DIR = os.path.join(CONFIG_DIR, 'cache')
SPOTIFY_CONFIG_FILE = os.path.join(CONFIG_DIR, 'spotify_config.json')
PARENTAL_CONFIG_FILE = os.path.join(CONFIG_DIR, 'parental_controls.json')

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global Spotify client
spotify_client = None
current_playback = {}
playback_lock = threading.Lock()

def load_spotify_config():
    """Load Spotify configuration"""
    if os.path.exists(SPOTIFY_CONFIG_FILE):
        with open(SPOTIFY_CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {}

def load_parental_config():
    """Load parental control configuration"""
    if os.path.exists(PARENTAL_CONFIG_FILE):
        with open(PARENTAL_CONFIG_FILE, 'r') as f:
            return json.load(f)
    return {
        'volume_limit': 85,
        'allowed_playlists': [],
        'blocked_content': [],
        'explicit_filter': True
    }

def init_spotify_client():
    """Initialize Spotify client with stored credentials"""
    global spotify_client
    
    try:
        spotify_config = load_spotify_config()
        if not spotify_config.get('client_id') or not spotify_config.get('client_secret'):
            logger.error("Spotify credentials not configured")
            return False
        
        cache_file = os.path.join(CACHE_DIR, 'token.cache')
        
        auth_manager = SpotifyOAuth(
            client_id=spotify_config['client_id'],
            client_secret=spotify_config['client_secret'],
            redirect_uri='https://192.168.1.164/callback',
            scope='user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read streaming',
            cache_path=cache_file,
            open_browser=False
        )
        
        # Check if we have valid token
        token_info = auth_manager.get_cached_token()
        if not token_info:
            logger.error("No valid token found. Please authenticate through admin panel first.")
            return False
        
        spotify_client = spotipy.Spotify(auth_manager=auth_manager)
        logger.info("Spotify client initialized successfully")
        return True
        
    except Exception as e:
        logger.error(f"Failed to initialize Spotify client: {e}")
        return False

def update_playback_state():
    """Background thread to update current playback state"""
    global current_playback
    
    while True:
        try:
            if spotify_client:
                with playback_lock:
                    playback = spotify_client.current_playback()
                    if playback:
                        current_playback = {
                            'is_playing': playback['is_playing'],
                            'device': playback['device'],
                            'item': {
                                'name': playback['item']['name'] if playback['item'] else None,
                                'artists': [{'name': a['name']} for a in playback['item']['artists']] if playback['item'] else [],
                                'album': {
                                    'name': playback['item']['album']['name'] if playback['item'] else None,
                                    'images': playback['item']['album']['images'] if playback['item'] else []
                                },
                                'duration_ms': playback['item']['duration_ms'] if playback['item'] else 0,
                                'uri': playback['item']['uri'] if playback['item'] else None
                            } if playback['item'] else None,
                            'progress_ms': playback['progress_ms'],
                            'volume': playback['device']['volume_percent'] if playback['device'] else 50
                        }
                    else:
                        current_playback = {'is_playing': False}
        except Exception as e:
            logger.error(f"Error updating playback state: {e}")
        
        time.sleep(1)  # Update every second

# HTML Template for the player
PLAYER_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Spotify Kids Player</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        .header {
            padding: 20px;
            background: rgba(0, 0, 0, 0.3);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .main-content {
            flex: 1;
            display: flex;
            padding: 20px;
            gap: 20px;
            overflow: hidden;
        }
        
        .sidebar {
            width: 300px;
            background: rgba(0, 0, 0, 0.2);
            border-radius: 10px;
            padding: 20px;
            overflow-y: auto;
        }
        
        .playlist-item {
            padding: 10px;
            margin: 5px 0;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 5px;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .playlist-item:hover {
            background: rgba(255, 255, 255, 0.2);
        }
        
        .now-playing {
            flex: 1;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
        }
        
        .album-art {
            width: 300px;
            height: 300px;
            background: rgba(0, 0, 0, 0.3);
            border-radius: 10px;
            margin-bottom: 30px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .album-art img {
            width: 100%;
            height: 100%;
            object-fit: cover;
            border-radius: 10px;
        }
        
        .track-info {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .track-name {
            font-size: 28px;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .artist-name {
            font-size: 20px;
            opacity: 0.8;
        }
        
        .player-controls {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            background: rgba(0, 0, 0, 0.8);
            padding: 20px;
            backdrop-filter: blur(10px);
        }
        
        .progress-bar {
            width: 100%;
            height: 4px;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 2px;
            margin-bottom: 20px;
            cursor: pointer;
        }
        
        .progress {
            height: 100%;
            background: #1db954;
            border-radius: 2px;
            transition: width 0.1s;
        }
        
        .control-buttons {
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .control-btn {
            background: none;
            border: none;
            color: white;
            cursor: pointer;
            transition: transform 0.2s;
            font-size: 24px;
        }
        
        .control-btn:hover {
            transform: scale(1.1);
        }
        
        .play-btn {
            width: 60px;
            height: 60px;
            background: #1db954;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 30px;
        }
        
        .volume-control {
            display: flex;
            align-items: center;
            gap: 10px;
            max-width: 200px;
            margin: 0 auto;
        }
        
        .volume-slider {
            flex: 1;
            height: 4px;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 2px;
            position: relative;
            cursor: pointer;
        }
        
        .volume-level {
            height: 100%;
            background: white;
            border-radius: 2px;
        }
        
        .search-container {
            margin-bottom: 20px;
        }
        
        .search-input {
            width: 100%;
            padding: 10px;
            background: rgba(255, 255, 255, 0.1);
            border: 1px solid rgba(255, 255, 255, 0.3);
            border-radius: 5px;
            color: white;
            font-size: 14px;
        }
        
        .search-input::placeholder {
            color: rgba(255, 255, 255, 0.6);
        }
        
        .error-message {
            background: rgba(255, 0, 0, 0.3);
            padding: 10px;
            border-radius: 5px;
            margin: 10px 0;
            text-align: center;
        }
        
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid rgba(255, 255, 255, 0.3);
            border-radius: 50%;
            border-top-color: white;
            animation: spin 1s ease-in-out infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🎵 Spotify Kids Player</h1>
        <div id="connection-status">
            <span class="loading"></span> Connecting...
        </div>
    </div>
    
    <div class="main-content">
        <div class="sidebar">
            <div class="search-container">
                <input type="text" class="search-input" id="searchInput" placeholder="Search songs, artists, playlists...">
            </div>
            <h3>Playlists</h3>
            <div id="playlists-container">
                <div class="loading"></div> Loading playlists...
            </div>
        </div>
        
        <div class="now-playing">
            <div class="album-art" id="albumArt">
                <span style="font-size: 48px; opacity: 0.3;">🎵</span>
            </div>
            <div class="track-info">
                <div class="track-name" id="trackName">No track playing</div>
                <div class="artist-name" id="artistName">Select a playlist to start</div>
            </div>
        </div>
    </div>
    
    <div class="player-controls">
        <div class="progress-bar" id="progressBar">
            <div class="progress" id="progress" style="width: 0%"></div>
        </div>
        
        <div class="control-buttons">
            <button class="control-btn" id="prevBtn">⏮️</button>
            <button class="control-btn play-btn" id="playBtn">▶️</button>
            <button class="control-btn" id="nextBtn">⏭️</button>
        </div>
        
        <div class="volume-control">
            <span>🔊</span>
            <div class="volume-slider" id="volumeSlider">
                <div class="volume-level" id="volumeLevel" style="width: 50%"></div>
            </div>
            <span id="volumeText">50%</span>
        </div>
    </div>
    
    <script>
        let isPlaying = false;
        let currentTrack = null;
        let playlists = [];
        let volumeLimit = 85;
        
        // Initialize player
        async function init() {
            await loadPlaylists();
            await updatePlaybackState();
            setInterval(updatePlaybackState, 1000);
        }
        
        // Load playlists
        async function loadPlaylists() {
            try {
                const response = await fetch('/api/playlists');
                const data = await response.json();
                
                if (data.success) {
                    playlists = data.playlists;
                    displayPlaylists(playlists);
                }
            } catch (error) {
                console.error('Error loading playlists:', error);
            }
        }
        
        // Display playlists
        function displayPlaylists(playlists) {
            const container = document.getElementById('playlists-container');
            container.innerHTML = '';
            
            playlists.forEach(playlist => {
                const item = document.createElement('div');
                item.className = 'playlist-item';
                item.innerHTML = `
                    <div>${playlist.name}</div>
                    <small>${playlist.tracks.total} tracks</small>
                `;
                item.onclick = () => playPlaylist(playlist.uri);
                container.appendChild(item);
            });
        }
        
        // Play playlist
        async function playPlaylist(uri) {
            try {
                const response = await fetch('/api/play', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({context_uri: uri})
                });
                
                const data = await response.json();
                if (!data.success) {
                    showError(data.error);
                }
            } catch (error) {
                console.error('Error playing playlist:', error);
            }
        }
        
        // Update playback state
        async function updatePlaybackState() {
            try {
                const response = await fetch('/api/current-playback');
                const data = await response.json();
                
                if (data.is_playing !== undefined) {
                    isPlaying = data.is_playing;
                    updatePlayButton();
                    
                    if (data.item) {
                        updateNowPlaying(data.item);
                        updateProgress(data.progress_ms, data.item.duration_ms);
                    }
                    
                    if (data.volume !== undefined) {
                        updateVolume(data.volume);
                    }
                    
                    document.getElementById('connection-status').innerHTML = '✅ Connected';
                }
            } catch (error) {
                console.error('Error updating playback:', error);
                document.getElementById('connection-status').innerHTML = '❌ Disconnected';
            }
        }
        
        // Update now playing display
        function updateNowPlaying(track) {
            document.getElementById('trackName').textContent = track.name || 'Unknown Track';
            document.getElementById('artistName').textContent = 
                track.artists ? track.artists.map(a => a.name).join(', ') : 'Unknown Artist';
            
            if (track.album && track.album.images && track.album.images.length > 0) {
                document.getElementById('albumArt').innerHTML = 
                    `<img src="${track.album.images[0].url}" alt="Album Art">`;
            }
        }
        
        // Update progress bar
        function updateProgress(progress, duration) {
            if (duration > 0) {
                const percent = (progress / duration) * 100;
                document.getElementById('progress').style.width = percent + '%';
            }
        }
        
        // Update volume display
        function updateVolume(volume) {
            const limitedVolume = Math.min(volume, volumeLimit);
            document.getElementById('volumeLevel').style.width = limitedVolume + '%';
            document.getElementById('volumeText').textContent = limitedVolume + '%';
        }
        
        // Update play button
        function updatePlayButton() {
            document.getElementById('playBtn').textContent = isPlaying ? '⏸️' : '▶️';
        }
        
        // Control handlers
        document.getElementById('playBtn').onclick = async () => {
            try {
                const endpoint = isPlaying ? '/api/pause' : '/api/play';
                const response = await fetch(endpoint, {method: 'POST'});
                const data = await response.json();
                
                if (data.success) {
                    isPlaying = !isPlaying;
                    updatePlayButton();
                }
            } catch (error) {
                console.error('Error toggling playback:', error);
            }
        };
        
        document.getElementById('nextBtn').onclick = async () => {
            try {
                await fetch('/api/next', {method: 'POST'});
            } catch (error) {
                console.error('Error skipping track:', error);
            }
        };
        
        document.getElementById('prevBtn').onclick = async () => {
            try {
                await fetch('/api/previous', {method: 'POST'});
            } catch (error) {
                console.error('Error going to previous track:', error);
            }
        };
        
        // Volume control
        document.getElementById('volumeSlider').onclick = async (e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            const percent = ((e.clientX - rect.left) / rect.width) * 100;
            const volume = Math.min(Math.round(percent), volumeLimit);
            
            try {
                const response = await fetch('/api/volume', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({volume: volume})
                });
                
                if (response.ok) {
                    updateVolume(volume);
                }
            } catch (error) {
                console.error('Error setting volume:', error);
            }
        };
        
        // Progress bar seek
        document.getElementById('progressBar').onclick = async (e) => {
            const rect = e.currentTarget.getBoundingClientRect();
            const percent = ((e.clientX - rect.left) / rect.width) * 100;
            
            // TODO: Implement seek functionality
        };
        
        // Search functionality
        document.getElementById('searchInput').oninput = (e) => {
            const query = e.target.value.toLowerCase();
            if (query) {
                const filtered = playlists.filter(p => 
                    p.name.toLowerCase().includes(query)
                );
                displayPlaylists(filtered);
            } else {
                displayPlaylists(playlists);
            }
        };
        
        // Show error message
        function showError(message) {
            const error = document.createElement('div');
            error.className = 'error-message';
            error.textContent = message;
            document.body.appendChild(error);
            setTimeout(() => error.remove(), 3000);
        }
        
        // Initialize on load
        init();
    </script>
</body>
</html>
'''

@app.route('/')
def index():
    """Serve the player interface"""
    return render_template_string(PLAYER_TEMPLATE)

@app.route('/api/playlists')
def get_playlists():
    """Get user's playlists"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        parental_config = load_parental_config()
        playlists = spotify_client.current_user_playlists(limit=50)
        
        # Filter playlists based on parental controls
        allowed_playlists = parental_config.get('allowed_playlists', [])
        if allowed_playlists:
            filtered = [p for p in playlists['items'] if p['uri'] in allowed_playlists]
        else:
            filtered = playlists['items']
        
        return jsonify({'success': True, 'playlists': filtered})
    except Exception as e:
        logger.error(f"Error getting playlists: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/current-playback')
def get_current_playback():
    """Get current playback state"""
    with playback_lock:
        return jsonify(current_playback)

@app.route('/api/play', methods=['POST'])
def play():
    """Start or resume playback"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json or {}
        
        # Check for active device
        devices = spotify_client.devices()
        if not devices['devices']:
            return jsonify({'success': False, 'error': 'No active Spotify device found'})
        
        if 'context_uri' in data:
            # Play specific playlist/album
            spotify_client.start_playback(context_uri=data['context_uri'])
        else:
            # Resume playback
            spotify_client.start_playback()
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error starting playback: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/pause', methods=['POST'])
def pause():
    """Pause playback"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        spotify_client.pause_playback()
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error pausing playback: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/next', methods=['POST'])
def next_track():
    """Skip to next track"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        spotify_client.next_track()
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error skipping track: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/previous', methods=['POST'])
def previous_track():
    """Go to previous track"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        spotify_client.previous_track()
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error going to previous track: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/volume', methods=['POST'])
def set_volume():
    """Set playback volume"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        volume = data.get('volume', 50)
        
        # Apply parental volume limit
        parental_config = load_parental_config()
        volume_limit = parental_config.get('volume_limit', 85)
        volume = min(volume, volume_limit)
        
        spotify_client.volume(volume)
        return jsonify({'success': True, 'volume': volume})
    except Exception as e:
        logger.error(f"Error setting volume: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    # Ensure directories exist
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    
    # Initialize Spotify client
    if init_spotify_client():
        # Start playback state updater thread
        update_thread = threading.Thread(target=update_playback_state, daemon=True)
        update_thread.start()
        
        # Run the web server
        app.run(host='0.0.0.0', port=5000, debug=False)
    else:
        logger.error("Failed to initialize Spotify client. Please authenticate through admin panel first.")