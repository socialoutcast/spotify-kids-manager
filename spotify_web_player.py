#!/usr/bin/env python3

from flask import Flask, render_template_string, jsonify, request, session, send_from_directory
from flask_cors import CORS
import spotipy
from spotipy.oauth2 import SpotifyOAuth
import os
import json
import time
import threading
import logging
from datetime import datetime, timedelta
import base64
import requests

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
            scope='user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read user-library-modify streaming user-read-recently-played user-top-read',
            cache_path=cache_file,
            open_browser=False
        )
        
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
                            'is_playing': playback.get('is_playing', False),
                            'device': playback.get('device'),
                            'item': playback.get('item'),
                            'progress_ms': playback.get('progress_ms', 0),
                            'shuffle_state': playback.get('shuffle_state', False),
                            'repeat_state': playback.get('repeat_state', 'off'),
                            'context': playback.get('context'),
                            'smart_shuffle': playback.get('smart_shuffle', False) if 'smart_shuffle' in playback else False
                        }
                    else:
                        current_playback = {'is_playing': False}
        except Exception as e:
            logger.error(f"Error updating playback state: {e}")
        
        time.sleep(1)

# HTML Template for the player
PLAYER_TEMPLATE = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Spotify Player</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            -webkit-user-select: none;
            -moz-user-select: none;
            -ms-user-select: none;
            user-select: none;
            -webkit-touch-callout: none;
            cursor: none !important;
        }
        
        :root {
            --spotify-green: #1DB954;
            --spotify-black: #191414;
            --spotify-dark: #121212;
            --spotify-gray: #181818;
            --spotify-light-gray: #282828;
            --spotify-text: #FFFFFF;
            --spotify-subtext: #B3B3B3;
            --sidebar-width: 350px;
        }
        
        body {
            font-family: 'Circular', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: var(--spotify-dark);
            color: var(--spotify-text);
            height: 100vh;
            display: flex;
            overflow: hidden;
            cursor: none !important;
        }
        
        /* Hide all cursors */
        * {
            cursor: none !important;
        }
        
        /* Sidebar */
        .sidebar {
            width: var(--sidebar-width);
            background: #000000;
            display: flex;
            flex-direction: column;
            border-right: 1px solid #282828;
        }
        
        .sidebar-header {
            padding: 24px;
            border-bottom: 1px solid #282828;
        }
        
        .logo {
            font-size: 28px;
            font-weight: bold;
            color: var(--spotify-green);
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .nav-section {
            padding: 8px 12px;
        }
        
        .nav-item {
            display: flex;
            align-items: center;
            gap: 16px;
            padding: 12px 12px;
            border-radius: 6px;
            color: var(--spotify-subtext);
            transition: all 0.3s;
            font-size: 14px;
            font-weight: 500;
            cursor: none;
        }
        
        .nav-item:hover {
            color: var(--spotify-text);
            background: var(--spotify-light-gray);
        }
        
        .nav-item.active {
            color: var(--spotify-text);
            background: var(--spotify-light-gray);
        }
        
        .nav-icon {
            width: 24px;
            height: 24px;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        /* Search Section */
        .search-container {
            padding: 12px;
            border-bottom: 1px solid #282828;
        }
        
        .search-box {
            position: relative;
        }
        
        .search-input {
            width: 100%;
            padding: 12px 12px 12px 40px;
            background: var(--spotify-light-gray);
            border: none;
            border-radius: 500px;
            color: var(--spotify-text);
            font-size: 14px;
            outline: none;
        }
        
        .search-input::placeholder {
            color: var(--spotify-subtext);
        }
        
        .search-icon {
            position: absolute;
            left: 12px;
            top: 50%;
            transform: translateY(-50%);
            color: var(--spotify-subtext);
        }
        
        /* Playlists */
        .playlists-container {
            flex: 1;
            overflow-y: auto;
            padding: 12px;
        }
        
        .playlist-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 8px;
            border-radius: 6px;
            transition: background 0.3s;
            cursor: none;
        }
        
        .playlist-item:hover {
            background: var(--spotify-light-gray);
        }
        
        .playlist-item.active {
            background: var(--spotify-light-gray);
        }
        
        .playlist-cover {
            width: 48px;
            height: 48px;
            border-radius: 4px;
            background: var(--spotify-light-gray);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 20px;
            overflow: hidden;
        }
        
        .playlist-cover img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        
        .playlist-info {
            flex: 1;
            min-width: 0;
        }
        
        .playlist-name {
            font-size: 14px;
            font-weight: 500;
            color: var(--spotify-text);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .playlist-details {
            font-size: 12px;
            color: var(--spotify-subtext);
            margin-top: 2px;
        }
        
        /* Main Content */
        .main-content {
            flex: 1;
            display: flex;
            flex-direction: column;
            background: linear-gradient(to bottom, #1e3264 0%, var(--spotify-dark) 50%);
        }
        
        /* Now Playing */
        .now-playing {
            flex: 1;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            padding: 40px;
        }
        
        .album-art-container {
            width: 400px;
            height: 400px;
            margin-bottom: 40px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
            border-radius: 8px;
            overflow: hidden;
            background: var(--spotify-gray);
        }
        
        .album-art {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        
        .track-info {
            text-align: center;
            margin-bottom: 40px;
            max-width: 600px;
        }
        
        .track-name {
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 8px;
            color: var(--spotify-text);
        }
        
        .track-artist {
            font-size: 18px;
            color: var(--spotify-subtext);
        }
        
        /* Player Bar */
        .player-bar {
            background: var(--spotify-gray);
            border-top: 1px solid #282828;
            padding: 16px;
            display: flex;
            align-items: center;
            gap: 16px;
        }
        
        .player-left {
            width: 30%;
            display: flex;
            align-items: center;
            gap: 16px;
        }
        
        .player-center {
            flex: 1;
            max-width: 722px;
        }
        
        .player-right {
            width: 30%;
            display: flex;
            justify-content: flex-end;
            align-items: center;
            gap: 16px;
        }
        
        .mini-album-art {
            width: 56px;
            height: 56px;
            border-radius: 4px;
            background: var(--spotify-light-gray);
            overflow: hidden;
        }
        
        .mini-album-art img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        
        .mini-track-info {
            flex: 1;
            min-width: 0;
        }
        
        .mini-track-name {
            font-size: 14px;
            color: var(--spotify-text);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .mini-track-artist {
            font-size: 11px;
            color: var(--spotify-subtext);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        /* Like Button */
        .like-button {
            background: none;
            border: none;
            color: var(--spotify-subtext);
            font-size: 18px;
            padding: 8px;
            transition: color 0.3s;
            cursor: none;
        }
        
        .like-button.active {
            color: var(--spotify-green);
        }
        
        .like-button:hover {
            color: var(--spotify-text);
        }
        
        /* Player Controls */
        .player-controls {
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 16px;
            margin-bottom: 8px;
        }
        
        .control-button {
            background: none;
            border: none;
            color: var(--spotify-subtext);
            font-size: 20px;
            padding: 8px;
            transition: all 0.3s;
            cursor: none;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .control-button:hover {
            color: var(--spotify-text);
            transform: scale(1.06);
        }
        
        .control-button.active {
            color: var(--spotify-green);
        }
        
        .control-button.play-pause {
            width: 40px;
            height: 40px;
            background: var(--spotify-text);
            color: var(--spotify-black);
            border-radius: 50%;
            font-size: 16px;
        }
        
        .control-button.play-pause:hover {
            transform: scale(1.08);
        }
        
        /* Shuffle Buttons */
        .shuffle-container {
            position: relative;
        }
        
        .shuffle-menu {
            position: absolute;
            bottom: 100%;
            left: 50%;
            transform: translateX(-50%);
            background: var(--spotify-light-gray);
            border-radius: 8px;
            padding: 4px;
            margin-bottom: 8px;
            display: none;
            min-width: 180px;
            box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
        }
        
        .shuffle-menu.show {
            display: block;
        }
        
        .shuffle-option {
            padding: 12px 16px;
            border-radius: 4px;
            color: var(--spotify-subtext);
            font-size: 14px;
            transition: all 0.2s;
            cursor: none;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        
        .shuffle-option:hover {
            background: #3e3e3e;
            color: var(--spotify-text);
        }
        
        .shuffle-option.active {
            color: var(--spotify-green);
        }
        
        /* Progress Bar */
        .progress-container {
            display: flex;
            align-items: center;
            gap: 12px;
        }
        
        .time-label {
            font-size: 11px;
            color: var(--spotify-subtext);
            min-width: 40px;
            text-align: center;
        }
        
        .progress-bar {
            flex: 1;
            height: 4px;
            background: #535353;
            border-radius: 2px;
            position: relative;
            cursor: none;
        }
        
        .progress-bar:hover .progress-fill {
            background: var(--spotify-green);
        }
        
        .progress-bar:hover .progress-handle {
            opacity: 1;
        }
        
        .progress-fill {
            height: 100%;
            background: var(--spotify-text);
            border-radius: 2px;
            position: relative;
            transition: background 0.3s;
        }
        
        .progress-handle {
            width: 12px;
            height: 12px;
            background: var(--spotify-text);
            border-radius: 50%;
            position: absolute;
            right: -6px;
            top: -4px;
            opacity: 0;
            transition: opacity 0.3s;
        }
        
        /* Volume Control */
        .volume-control {
            display: flex;
            align-items: center;
            gap: 8px;
            min-width: 125px;
        }
        
        .volume-icon {
            color: var(--spotify-subtext);
            font-size: 20px;
        }
        
        .volume-slider {
            flex: 1;
            height: 4px;
            background: #535353;
            border-radius: 2px;
            position: relative;
            cursor: none;
        }
        
        .volume-fill {
            height: 100%;
            background: var(--spotify-text);
            border-radius: 2px;
            transition: background 0.3s;
        }
        
        .volume-slider:hover .volume-fill {
            background: var(--spotify-green);
        }
        
        /* Search Results */
        .search-results {
            position: absolute;
            top: 100%;
            left: 0;
            right: 0;
            background: var(--spotify-gray);
            border-radius: 8px;
            margin-top: 8px;
            max-height: 400px;
            overflow-y: auto;
            box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
            z-index: 1000;
            display: none;
        }
        
        .search-results.show {
            display: block;
        }
        
        .search-result-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px;
            transition: background 0.2s;
            cursor: none;
        }
        
        .search-result-item:hover {
            background: var(--spotify-light-gray);
        }
        
        .search-result-cover {
            width: 40px;
            height: 40px;
            border-radius: 4px;
            background: var(--spotify-light-gray);
            overflow: hidden;
        }
        
        .search-result-cover img {
            width: 100%;
            height: 100%;
            object-fit: cover;
        }
        
        .search-result-info {
            flex: 1;
            min-width: 0;
        }
        
        .search-result-name {
            font-size: 14px;
            color: var(--spotify-text);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .search-result-artist {
            font-size: 12px;
            color: var(--spotify-subtext);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }
        
        .search-result-type {
            font-size: 11px;
            color: var(--spotify-subtext);
            text-transform: uppercase;
            padding: 2px 8px;
            background: var(--spotify-light-gray);
            border-radius: 12px;
        }
        
        /* Loading Spinner */
        .loading {
            display: inline-block;
            width: 20px;
            height: 20px;
            border: 3px solid var(--spotify-subtext);
            border-radius: 50%;
            border-top-color: var(--spotify-green);
            animation: spin 1s ease-in-out infinite;
        }
        
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        
        /* Scrollbar Styling */
        ::-webkit-scrollbar {
            width: 12px;
        }
        
        ::-webkit-scrollbar-track {
            background: transparent;
        }
        
        ::-webkit-scrollbar-thumb {
            background: #535353;
            border-radius: 6px;
        }
        
        ::-webkit-scrollbar-thumb:hover {
            background: #b3b3b3;
        }
        
        /* Touch optimizations */
        button, .nav-item, .playlist-item, .search-result-item {
            -webkit-tap-highlight-color: transparent;
            touch-action: manipulation;
        }
        
        /* Responsive */
        @media (max-width: 1024px) {
            .sidebar {
                width: 280px;
            }
            
            .album-art-container {
                width: 300px;
                height: 300px;
            }
            
            .track-name {
                font-size: 24px;
            }
        }
    </style>
</head>
<body>
    <!-- Sidebar -->
    <div class="sidebar">
        <div class="sidebar-header">
            <div class="logo">
                <svg width="32" height="32" viewBox="0 0 32 32" fill="currentColor">
                    <path d="M16 0C7.16 0 0 7.16 0 16s7.16 16 16 16 16-7.16 16-16S24.84 0 16 0zm7.36 23.14c-.28.44-.88.58-1.32.3-3.62-2.2-8.18-2.7-13.54-1.48-.52.12-1.02-.2-1.14-.72-.12-.52.2-1.02.72-1.14 5.88-1.34 10.92-.76 14.98 1.72.44.28.58.88.3 1.32zm1.88-4.18c-.36.56-1.12.74-1.68.38-4.14-2.54-10.44-3.28-15.34-1.8-.64.2-1.32-.18-1.52-.82-.2-.64.18-1.32.82-1.52 5.6-1.7 12.54-.88 17.34 2.06.56.36.74 1.12.38 1.7zm.16-4.36c-4.98-2.96-13.18-3.22-17.94-1.78-.76.22-1.58-.22-1.8-.98-.22-.76.22-1.58.98-1.8 5.46-1.66 14.54-1.34 20.28 2.06.68.42.92 1.32.5 2-.42.7-1.32.92-2.02.5z"/>
                </svg>
                <span>Spotify</span>
            </div>
        </div>
        
        <div class="nav-section">
            <div class="nav-item active" onclick="showHome()">
                <div class="nav-icon">🏠</div>
                <span>Home</span>
            </div>
            <div class="nav-item" onclick="loadDJ()">
                <div class="nav-icon">🎧</div>
                <span>DJ</span>
            </div>
            <div class="nav-item" onclick="loadLikedSongs()">
                <div class="nav-icon">❤️</div>
                <span>Liked Songs</span>
            </div>
        </div>
        
        <div class="search-container">
            <div class="search-box">
                <div class="search-icon">🔍</div>
                <input type="text" class="search-input" id="searchInput" placeholder="Search for songs, artists, or albums">
                <div class="search-results" id="searchResults"></div>
            </div>
        </div>
        
        <div class="playlists-container" id="playlistsContainer">
            <div style="text-align: center; padding: 20px;">
                <div class="loading"></div>
            </div>
        </div>
    </div>
    
    <!-- Main Content -->
    <div class="main-content">
        <div class="now-playing">
            <div class="album-art-container">
                <img class="album-art" id="albumArt" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 400 400'%3E%3Crect fill='%23282828' width='400' height='400'/%3E%3Ctext x='50%25' y='50%25' text-anchor='middle' dy='.3em' fill='%23b3b3b3' font-size='100'%3E🎵%3C/text%3E%3C/svg%3E" alt="Album Art">
            </div>
            <div class="track-info">
                <div class="track-name" id="trackName">No track playing</div>
                <div class="track-artist" id="trackArtist">Start playing something</div>
            </div>
        </div>
        
        <!-- Player Bar -->
        <div class="player-bar">
            <div class="player-left">
                <div class="mini-album-art">
                    <img id="miniAlbumArt" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 56 56'%3E%3Crect fill='%23282828' width='56' height='56'/%3E%3C/svg%3E" alt="">
                </div>
                <div class="mini-track-info">
                    <div class="mini-track-name" id="miniTrackName">-</div>
                    <div class="mini-track-artist" id="miniTrackArtist">-</div>
                </div>
                <button class="like-button" id="likeButton" onclick="toggleLike()">
                    <span id="likeIcon">🤍</span>
                </button>
            </div>
            
            <div class="player-center">
                <div class="player-controls">
                    <div class="shuffle-container">
                        <button class="control-button" id="shuffleButton" onclick="toggleShuffleMenu()">
                            <span id="shuffleIcon">🔀</span>
                        </button>
                        <div class="shuffle-menu" id="shuffleMenu">
                            <div class="shuffle-option" onclick="setShuffle('off')">
                                <span>✖️</span> Off
                            </div>
                            <div class="shuffle-option" onclick="setShuffle('on')">
                                <span>🔀</span> Shuffle
                            </div>
                            <div class="shuffle-option" onclick="setShuffle('smart')">
                                <span>✨</span> Smart Shuffle
                            </div>
                        </div>
                    </div>
                    <button class="control-button" onclick="previousTrack()">⏮️</button>
                    <button class="control-button play-pause" id="playPauseButton" onclick="togglePlayback()">
                        <span id="playPauseIcon">▶️</span>
                    </button>
                    <button class="control-button" onclick="nextTrack()">⏭️</button>
                    <button class="control-button" id="repeatButton" onclick="toggleRepeat()">
                        <span id="repeatIcon">🔁</span>
                    </button>
                </div>
                <div class="progress-container">
                    <span class="time-label" id="currentTime">0:00</span>
                    <div class="progress-bar" id="progressBar" onclick="seekTo(event)">
                        <div class="progress-fill" id="progressFill" style="width: 0%">
                            <div class="progress-handle"></div>
                        </div>
                    </div>
                    <span class="time-label" id="totalTime">0:00</span>
                </div>
            </div>
            
            <div class="player-right">
                <div class="volume-control">
                    <span class="volume-icon">🔊</span>
                    <div class="volume-slider" id="volumeSlider" onclick="setVolume(event)">
                        <div class="volume-fill" id="volumeFill" style="width: 50%"></div>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script>
        let currentTrack = null;
        let isPlaying = false;
        let isLiked = false;
        let shuffleState = 'off';
        let repeatState = 'off';
        let searchTimeout = null;
        let currentPlaylistUri = null;
        
        // Format time from milliseconds to mm:ss
        function formatTime(ms) {
            const seconds = Math.floor(ms / 1000);
            const minutes = Math.floor(seconds / 60);
            const remainingSeconds = seconds % 60;
            return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
        }
        
        // Initialize player
        async function init() {
            await loadPlaylists();
            setInterval(updatePlaybackState, 1000);
            
            // Setup search
            document.getElementById('searchInput').addEventListener('input', handleSearch);
            
            // Hide search results when clicking outside
            document.addEventListener('click', (e) => {
                if (!e.target.closest('.search-container')) {
                    document.getElementById('searchResults').classList.remove('show');
                }
            });
        }
        
        // Load playlists
        async function loadPlaylists() {
            try {
                const response = await fetch('/api/playlists');
                const data = await response.json();
                
                if (data.success) {
                    displayPlaylists(data.playlists);
                }
            } catch (error) {
                console.error('Error loading playlists:', error);
            }
        }
        
        // Display playlists
        function displayPlaylists(playlists) {
            const container = document.getElementById('playlistsContainer');
            container.innerHTML = '';
            
            playlists.forEach(playlist => {
                const item = document.createElement('div');
                item.className = 'playlist-item';
                item.onclick = () => playPlaylist(playlist.uri);
                
                const coverUrl = playlist.images && playlist.images.length > 0 
                    ? playlist.images[0].url 
                    : '';
                
                item.innerHTML = `
                    <div class="playlist-cover">
                        ${coverUrl ? `<img src="${coverUrl}" alt="">` : '📁'}
                    </div>
                    <div class="playlist-info">
                        <div class="playlist-name">${playlist.name}</div>
                        <div class="playlist-details">${playlist.tracks.total} tracks</div>
                    </div>
                `;
                
                container.appendChild(item);
            });
        }
        
        // Play playlist
        async function playPlaylist(uri) {
            currentPlaylistUri = uri;
            try {
                const response = await fetch('/api/play', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({context_uri: uri})
                });
                
                const data = await response.json();
                if (!data.success && data.error) {
                    console.error('Error playing playlist:', data.error);
                }
            } catch (error) {
                console.error('Error playing playlist:', error);
            }
        }
        
        // Load DJ
        async function loadDJ() {
            // Spotify's DJ feature - use recommendations endpoint
            try {
                const response = await fetch('/api/dj');
                const data = await response.json();
                if (data.success) {
                    playPlaylist(data.uri);
                }
            } catch (error) {
                console.error('Error loading DJ:', error);
            }
        }
        
        // Load liked songs
        async function loadLikedSongs() {
            try {
                const response = await fetch('/api/liked-songs');
                const data = await response.json();
                if (data.success) {
                    playPlaylist('spotify:collection:tracks');
                }
            } catch (error) {
                console.error('Error loading liked songs:', error);
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
                        currentTrack = data.item;
                        updateNowPlaying(data.item);
                        updateProgress(data.progress_ms, data.item.duration_ms);
                        checkIfLiked(data.item.id);
                    }
                    
                    // Update shuffle and repeat states
                    shuffleState = data.smart_shuffle ? 'smart' : (data.shuffle_state ? 'on' : 'off');
                    repeatState = data.repeat_state || 'off';
                    updateShuffleButton();
                    updateRepeatButton();
                    
                    // Update volume
                    if (data.device && data.device.volume_percent !== undefined) {
                        updateVolume(data.device.volume_percent);
                    }
                }
            } catch (error) {
                console.error('Error updating playback:', error);
            }
        }
        
        // Update now playing display
        function updateNowPlaying(track) {
            if (!track) return;
            
            const trackName = track.name || 'Unknown Track';
            const artistName = track.artists ? track.artists.map(a => a.name).join(', ') : 'Unknown Artist';
            const albumArt = track.album && track.album.images && track.album.images.length > 0 
                ? track.album.images[0].url 
                : 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400"%3E%3Crect fill="%23282828" width="400" height="400"/%3E%3C/svg%3E';
            
            document.getElementById('trackName').textContent = trackName;
            document.getElementById('trackArtist').textContent = artistName;
            document.getElementById('albumArt').src = albumArt;
            
            document.getElementById('miniTrackName').textContent = trackName;
            document.getElementById('miniTrackArtist').textContent = artistName;
            document.getElementById('miniAlbumArt').src = albumArt;
        }
        
        // Update progress bar
        function updateProgress(progress, duration) {
            if (duration > 0) {
                const percent = (progress / duration) * 100;
                document.getElementById('progressFill').style.width = percent + '%';
                document.getElementById('currentTime').textContent = formatTime(progress);
                document.getElementById('totalTime').textContent = formatTime(duration);
            }
        }
        
        // Update volume display
        function updateVolume(volume) {
            document.getElementById('volumeFill').style.width = volume + '%';
        }
        
        // Check if track is liked
        async function checkIfLiked(trackId) {
            if (!trackId) return;
            
            try {
                const response = await fetch(`/api/track-liked/${trackId}`);
                const data = await response.json();
                isLiked = data.liked;
                updateLikeButton();
            } catch (error) {
                console.error('Error checking liked status:', error);
            }
        }
        
        // Update buttons
        function updatePlayButton() {
            document.getElementById('playPauseIcon').textContent = isPlaying ? '⏸️' : '▶️';
        }
        
        function updateLikeButton() {
            const likeButton = document.getElementById('likeButton');
            const likeIcon = document.getElementById('likeIcon');
            likeIcon.textContent = isLiked ? '❤️' : '🤍';
            likeButton.classList.toggle('active', isLiked);
        }
        
        function updateShuffleButton() {
            const shuffleButton = document.getElementById('shuffleButton');
            const shuffleIcon = document.getElementById('shuffleIcon');
            
            shuffleButton.classList.toggle('active', shuffleState !== 'off');
            if (shuffleState === 'smart') {
                shuffleIcon.textContent = '✨';
            } else {
                shuffleIcon.textContent = '🔀';
            }
            
            // Update menu
            document.querySelectorAll('.shuffle-option').forEach(option => {
                option.classList.remove('active');
            });
            
            const activeOption = document.querySelector(`.shuffle-option[onclick*="${shuffleState}"]`);
            if (activeOption) {
                activeOption.classList.add('active');
            }
        }
        
        function updateRepeatButton() {
            const repeatButton = document.getElementById('repeatButton');
            const repeatIcon = document.getElementById('repeatIcon');
            
            repeatButton.classList.toggle('active', repeatState !== 'off');
            if (repeatState === 'track') {
                repeatIcon.textContent = '🔂';
            } else {
                repeatIcon.textContent = '🔁';
            }
        }
        
        // Playback controls
        async function togglePlayback() {
            try {
                const endpoint = isPlaying ? '/api/pause' : '/api/play';
                await fetch(endpoint, {method: 'POST'});
            } catch (error) {
                console.error('Error toggling playback:', error);
            }
        }
        
        async function nextTrack() {
            try {
                await fetch('/api/next', {method: 'POST'});
            } catch (error) {
                console.error('Error skipping track:', error);
            }
        }
        
        async function previousTrack() {
            try {
                await fetch('/api/previous', {method: 'POST'});
            } catch (error) {
                console.error('Error going to previous track:', error);
            }
        }
        
        // Toggle like
        async function toggleLike() {
            if (!currentTrack || !currentTrack.id) return;
            
            try {
                const endpoint = isLiked ? '/api/unlike-track' : '/api/like-track';
                await fetch(endpoint, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({track_id: currentTrack.id})
                });
                
                isLiked = !isLiked;
                updateLikeButton();
            } catch (error) {
                console.error('Error toggling like:', error);
            }
        }
        
        // Shuffle controls
        function toggleShuffleMenu() {
            const menu = document.getElementById('shuffleMenu');
            menu.classList.toggle('show');
        }
        
        async function setShuffle(state) {
            const menu = document.getElementById('shuffleMenu');
            menu.classList.remove('show');
            
            try {
                await fetch('/api/shuffle', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({state: state})
                });
                
                shuffleState = state;
                updateShuffleButton();
            } catch (error) {
                console.error('Error setting shuffle:', error);
            }
        }
        
        // Repeat control
        async function toggleRepeat() {
            const states = ['off', 'context', 'track'];
            const currentIndex = states.indexOf(repeatState);
            const newState = states[(currentIndex + 1) % states.length];
            
            try {
                await fetch('/api/repeat', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({state: newState})
                });
                
                repeatState = newState;
                updateRepeatButton();
            } catch (error) {
                console.error('Error setting repeat:', error);
            }
        }
        
        // Volume control
        async function setVolume(event) {
            const slider = document.getElementById('volumeSlider');
            const rect = slider.getBoundingClientRect();
            const percent = ((event.clientX - rect.left) / rect.width) * 100;
            const volume = Math.max(0, Math.min(100, Math.round(percent)));
            
            try {
                await fetch('/api/volume', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({volume: volume})
                });
                
                updateVolume(volume);
            } catch (error) {
                console.error('Error setting volume:', error);
            }
        }
        
        // Progress bar seek
        async function seekTo(event) {
            if (!currentTrack) return;
            
            const bar = document.getElementById('progressBar');
            const rect = bar.getBoundingClientRect();
            const percent = ((event.clientX - rect.left) / rect.width) * 100;
            const position = Math.round((percent / 100) * currentTrack.duration_ms);
            
            try {
                await fetch('/api/seek', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({position_ms: position})
                });
            } catch (error) {
                console.error('Error seeking:', error);
            }
        }
        
        // Search functionality
        function handleSearch(event) {
            const query = event.target.value.trim();
            
            if (searchTimeout) {
                clearTimeout(searchTimeout);
            }
            
            if (query.length < 2) {
                document.getElementById('searchResults').classList.remove('show');
                return;
            }
            
            searchTimeout = setTimeout(() => {
                performSearch(query);
            }, 300);
        }
        
        async function performSearch(query) {
            try {
                const response = await fetch('/api/search', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({query: query})
                });
                
                const data = await response.json();
                if (data.success) {
                    displaySearchResults(data.results);
                }
            } catch (error) {
                console.error('Error searching:', error);
            }
        }
        
        function displaySearchResults(results) {
            const container = document.getElementById('searchResults');
            container.innerHTML = '';
            
            if (!results || results.length === 0) {
                container.classList.remove('show');
                return;
            }
            
            results.forEach(item => {
                const resultDiv = document.createElement('div');
                resultDiv.className = 'search-result-item';
                resultDiv.onclick = () => playSearchResult(item);
                
                const coverUrl = item.image || '';
                
                resultDiv.innerHTML = `
                    <div class="search-result-cover">
                        ${coverUrl ? `<img src="${coverUrl}" alt="">` : '🎵'}
                    </div>
                    <div class="search-result-info">
                        <div class="search-result-name">${item.name}</div>
                        <div class="search-result-artist">${item.artist || ''}</div>
                    </div>
                    <div class="search-result-type">${item.type}</div>
                `;
                
                container.appendChild(resultDiv);
            });
            
            container.classList.add('show');
        }
        
        async function playSearchResult(item) {
            document.getElementById('searchResults').classList.remove('show');
            document.getElementById('searchInput').value = '';
            
            try {
                if (item.type === 'track') {
                    await fetch('/api/play-track', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({uri: item.uri})
                    });
                } else if (item.type === 'album' || item.type === 'playlist') {
                    await fetch('/api/play', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({context_uri: item.uri})
                    });
                } else if (item.type === 'artist') {
                    await fetch('/api/play-artist', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({uri: item.uri})
                    });
                }
            } catch (error) {
                console.error('Error playing search result:', error);
            }
        }
        
        function showHome() {
            // Reset to main view
            loadPlaylists();
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

# API Endpoints

@app.route('/api/playlists')
def get_playlists():
    """Get user's playlists"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        playlists = spotify_client.current_user_playlists(limit=50)
        return jsonify({'success': True, 'playlists': playlists['items']})
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
        
        devices = spotify_client.devices()
        if not devices['devices']:
            return jsonify({'success': False, 'error': 'No active Spotify device found'})
        
        if 'context_uri' in data:
            spotify_client.start_playback(context_uri=data['context_uri'])
        else:
            spotify_client.start_playback()
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error starting playback: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/play-track', methods=['POST'])
def play_track():
    """Play a specific track"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        uri = data.get('uri')
        
        spotify_client.start_playback(uris=[uri])
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error playing track: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/play-artist', methods=['POST'])
def play_artist():
    """Play artist's top tracks"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        artist_uri = data.get('uri')
        artist_id = artist_uri.split(':')[-1]
        
        # Get artist's top tracks
        top_tracks = spotify_client.artist_top_tracks(artist_id)
        track_uris = [track['uri'] for track in top_tracks['tracks'][:20]]
        
        if track_uris:
            spotify_client.start_playback(uris=track_uris)
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error playing artist: {e}")
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

@app.route('/api/shuffle', methods=['POST'])
def set_shuffle():
    """Set shuffle state"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        state = data.get('state', 'off')
        
        if state == 'smart':
            # Smart shuffle is a Spotify feature that adds recommendations
            spotify_client.shuffle(True)
            # Note: Smart shuffle API may not be directly available
        elif state == 'on':
            spotify_client.shuffle(True)
        else:
            spotify_client.shuffle(False)
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error setting shuffle: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/repeat', methods=['POST'])
def set_repeat():
    """Set repeat state"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        state = data.get('state', 'off')  # off, context, track
        
        spotify_client.repeat(state)
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error setting repeat: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/volume', methods=['POST'])
def set_volume():
    """Set playback volume"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        volume = data.get('volume', 50)
        
        parental_config = load_parental_config()
        volume_limit = parental_config.get('volume_limit', 85)
        volume = min(volume, volume_limit)
        
        spotify_client.volume(volume)
        return jsonify({'success': True, 'volume': volume})
    except Exception as e:
        logger.error(f"Error setting volume: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/seek', methods=['POST'])
def seek():
    """Seek to position in track"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        position_ms = data.get('position_ms', 0)
        
        spotify_client.seek_track(position_ms)
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error seeking: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/track-liked/<track_id>')
def check_track_liked(track_id):
    """Check if track is liked"""
    try:
        if not spotify_client:
            return jsonify({'liked': False})
        
        result = spotify_client.current_user_saved_tracks_contains([track_id])
        return jsonify({'liked': result[0] if result else False})
    except Exception as e:
        logger.error(f"Error checking liked status: {e}")
        return jsonify({'liked': False})

@app.route('/api/like-track', methods=['POST'])
def like_track():
    """Add track to liked songs"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        track_id = data.get('track_id')
        
        spotify_client.current_user_saved_tracks_add([track_id])
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error liking track: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/unlike-track', methods=['POST'])
def unlike_track():
    """Remove track from liked songs"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        track_id = data.get('track_id')
        
        spotify_client.current_user_saved_tracks_delete([track_id])
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error unliking track: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/liked-songs')
def get_liked_songs():
    """Get liked songs playlist"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        # Liked songs has a special URI
        return jsonify({'success': True, 'uri': 'spotify:collection:tracks'})
    except Exception as e:
        logger.error(f"Error getting liked songs: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/dj')
def get_dj():
    """Get DJ/recommendations"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        # Get user's top tracks for seed
        top_tracks = spotify_client.current_user_top_tracks(limit=5)
        seed_tracks = [track['id'] for track in top_tracks['items']]
        
        # Get recommendations
        recommendations = spotify_client.recommendations(seed_tracks=seed_tracks[:5], limit=50)
        
        # Create a custom "playlist" from recommendations
        track_uris = [track['uri'] for track in recommendations['tracks']]
        
        if track_uris:
            spotify_client.start_playback(uris=track_uris)
        
        return jsonify({'success': True})
    except Exception as e:
        logger.error(f"Error getting DJ: {e}")
        return jsonify({'success': False, 'error': str(e)})

@app.route('/api/search', methods=['POST'])
def search():
    """Search Spotify"""
    try:
        if not spotify_client:
            return jsonify({'success': False, 'error': 'Spotify not connected'})
        
        data = request.json
        query = data.get('query', '')
        
        if not query:
            return jsonify({'success': True, 'results': []})
        
        # Search for tracks, albums, artists, and playlists
        results = spotify_client.search(q=query, types=['track', 'album', 'artist', 'playlist'], limit=10)
        
        formatted_results = []
        
        # Format tracks
        for track in results.get('tracks', {}).get('items', []):
            formatted_results.append({
                'type': 'track',
                'id': track['id'],
                'uri': track['uri'],
                'name': track['name'],
                'artist': ', '.join([a['name'] for a in track['artists']]),
                'image': track['album']['images'][0]['url'] if track['album']['images'] else None
            })
        
        # Format albums
        for album in results.get('albums', {}).get('items', []):
            formatted_results.append({
                'type': 'album',
                'id': album['id'],
                'uri': album['uri'],
                'name': album['name'],
                'artist': ', '.join([a['name'] for a in album['artists']]),
                'image': album['images'][0]['url'] if album['images'] else None
            })
        
        # Format artists
        for artist in results.get('artists', {}).get('items', []):
            formatted_results.append({
                'type': 'artist',
                'id': artist['id'],
                'uri': artist['uri'],
                'name': artist['name'],
                'artist': f"{artist['followers']['total']:,} followers" if 'followers' in artist else '',
                'image': artist['images'][0]['url'] if artist['images'] else None
            })
        
        # Format playlists
        for playlist in results.get('playlists', {}).get('items', []):
            formatted_results.append({
                'type': 'playlist',
                'id': playlist['id'],
                'uri': playlist['uri'],
                'name': playlist['name'],
                'artist': f"by {playlist['owner']['display_name']}",
                'image': playlist['images'][0]['url'] if playlist['images'] else None
            })
        
        return jsonify({'success': True, 'results': formatted_results[:20]})
    except Exception as e:
        logger.error(f"Error searching: {e}")
        return jsonify({'success': False, 'error': str(e)})

if __name__ == '__main__':
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    
    if init_spotify_client():
        update_thread = threading.Thread(target=update_playback_state, daemon=True)
        update_thread.start()
        
        app.run(host='0.0.0.0', port=5000, debug=False)
    else:
        logger.error("Failed to initialize Spotify client. Please authenticate through admin panel first.")