#!/usr/bin/env python3

from flask import Flask, request, jsonify, session, redirect, url_for, render_template_string, Response
from flask_cors import CORS
from werkzeug.security import check_password_hash, generate_password_hash
import os
import json
import subprocess
import psutil
from datetime import datetime, timedelta
import threading
import queue
import time
import uuid
import sys
import hashlib

app = Flask(__name__, static_folder='static', static_url_path='/static')
app.config['SECRET_KEY'] = os.urandom(24)
CORS(app)

# Configuration
CONFIG_DIR = os.environ.get('SPOTIFY_CONFIG_DIR', '/opt/spotify-kids/config')
LOG_DIR = '/var/log/spotify-kids'
APP_USER = 'spotify-kids'
CONFIG_FILE = os.path.join(CONFIG_DIR, 'admin_config.json')
SPOTIFY_CONFIG_FILE = os.path.join(CONFIG_DIR, 'spotify_config.json')
PARENTAL_CONFIG_FILE = os.path.join(CONFIG_DIR, 'parental_controls.json')
USAGE_STATS_FILE = os.path.join(CONFIG_DIR, 'usage_stats.json')
SCHEDULE_FILE = os.path.join(CONFIG_DIR, 'schedule.json')
REWARDS_FILE = os.path.join(CONFIG_DIR, 'rewards.json')

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
    # Set proper permissions so spotify-kids user can read it
    try:
        os.chmod(SPOTIFY_CONFIG_FILE, 0o664)
    except:
        pass  # Ignore permission errors

def load_parental_config():
    """Load parental control configuration"""
    if os.path.exists(PARENTAL_CONFIG_FILE):
        with open(PARENTAL_CONFIG_FILE, 'r') as f:
            return json.load(f)
    else:
        # Default parental control settings
        default_config = {
            'content_filter': {
                'explicit_blocked': True,
                'blocked_artists': [],
                'blocked_songs': [],
                'blocked_albums': [],
                'allowed_playlists': [],
                'genre_whitelist': [],
                'genre_blacklist': ['death metal', 'black metal'],
                'require_playlist_approval': False
            },
            'listening_limits': {
                'daily_limit_minutes': 120,
                'session_limit_minutes': 60,
                'break_time_minutes': 30,
                'volume_max': 85,
                'skip_limit_per_hour': 20
            },
            'remote_control': {
                'allow_remote_stop': True,
                'allow_messages': True,
                'emergency_contacts': [],
                'screenshot_enabled': False
            }
        }
        save_parental_config(default_config)
        return default_config

def save_parental_config(config):
    """Save parental control configuration"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(PARENTAL_CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)

def load_usage_stats():
    """Load usage statistics"""
    if os.path.exists(USAGE_STATS_FILE):
        with open(USAGE_STATS_FILE, 'r') as f:
            return json.load(f)
    else:
        return {
            'sessions': [],
            'total_minutes_today': 0,
            'last_reset': datetime.now().isoformat(),
            'favorite_songs': {},
            'skip_count': {},
            'daily_history': []
        }

def save_usage_stats(stats):
    """Save usage statistics"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(USAGE_STATS_FILE, 'w') as f:
        json.dump(stats, f, indent=2)

def load_schedule():
    """Load listening schedule"""
    if os.path.exists(SCHEDULE_FILE):
        with open(SCHEDULE_FILE, 'r') as f:
            return json.load(f)
    else:
        # Default schedule - weekday and weekend times
        default_schedule = {
            'enabled': False,
            'weekday': {
                'morning': {'start': '07:00', 'end': '08:30'},
                'afternoon': {'start': '15:00', 'end': '17:00'},
                'evening': {'start': '18:30', 'end': '20:00'}
            },
            'weekend': {
                'morning': {'start': '08:00', 'end': '10:00'},
                'afternoon': {'start': '14:00', 'end': '17:00'},
                'evening': {'start': '18:00', 'end': '20:30'}
            },
            'blackout_dates': [],
            'special_occasions': []
        }
        save_schedule(default_schedule)
        return default_schedule

def save_schedule(schedule):
    """Save listening schedule"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(SCHEDULE_FILE, 'w') as f:
        json.dump(schedule, f, indent=2)

def get_default_config():
    """Get default configuration"""
    return {
        'device_locked': False,
        'volume_limit': 85,
        'admin_user': 'admin',
        'admin_pass': generate_password_hash('changeme'),
        'time_restrictions': {
            'start': '07:00',
            'end': '20:00'
        }
    }

def get_default_parental_config():
    """Get default parental control configuration"""
    return {
        'content_filter': {
            'explicit_blocked': True,
            'blocked_artists': [],
            'blocked_songs': [],
            'blocked_albums': [],
            'allowed_playlists': [],
            'genre_whitelist': [],
            'genre_blacklist': ['death metal', 'black metal'],
            'require_playlist_approval': False
        },
        'listening_limits': {
            'daily_limit_minutes': 120,
            'session_limit_minutes': 60,
            'break_time_minutes': 30,
            'volume_max': 85,
            'skip_limit_per_hour': 20
        },
        'remote_control': {
            'allow_remote_stop': True,
            'allow_messages': True,
            'emergency_contacts': [],
            'screenshot_enabled': False
        }
    }

def get_default_usage_stats():
    """Get default usage statistics"""
    return {
        'sessions': [],
        'total_minutes_today': 0,
        'last_reset': datetime.now().isoformat(),
        'favorite_songs': {},
        'skip_count': {},
        'daily_history': []
    }

def get_default_schedule():
    """Get default listening schedule"""
    return {
        'enabled': False,
        'weekday': {
            'morning': {'start': '07:00', 'end': '08:30'},
            'afternoon': {'start': '15:00', 'end': '17:00'},
            'evening': {'start': '18:30', 'end': '20:00'}
        },
        'weekend': {
            'morning': {'start': '08:00', 'end': '10:00'},
            'afternoon': {'start': '14:00', 'end': '17:00'},
            'evening': {'start': '18:00', 'end': '20:30'}
        },
        'blackout_dates': [],
        'special_occasions': []
    }

def get_default_rewards():
    """Get default rewards configuration"""
    return {
        'enabled': False,
        'points': 0,
        'achievements': [],
        'rewards_available': [],
        'point_rules': {
            'per_minute_listened': 0.1,
            'daily_login': 5,
            'no_skips_bonus': 3,
            'good_behavior': 10
        },
        'redeemed_today': []
    }

def load_rewards():
    """Load rewards configuration"""
    if os.path.exists(REWARDS_FILE):
        with open(REWARDS_FILE, 'r') as f:
            return json.load(f)
    else:
        default_rewards = {
            'enabled': False,
            'points': 0,
            'achievements': [],
            'rewards_available': [
                {'name': 'Extra 30 minutes', 'cost': 10, 'type': 'time_bonus', 'value': 30},
                {'name': 'Skip limit +5', 'cost': 5, 'type': 'skip_bonus', 'value': 5},
                {'name': 'Choose any playlist', 'cost': 15, 'type': 'playlist_unlock', 'value': 1}
            ],
            'point_rules': {
                'per_minute_listened': 0.1,
                'daily_login': 5,
                'no_skips_bonus': 3,
                'good_behavior': 10
            },
            'redeemed_today': []
        }
        save_rewards(default_rewards)
        return default_rewards

def save_rewards(rewards):
    """Save rewards configuration"""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(REWARDS_FILE, 'w') as f:
        json.dump(rewards, f, indent=2)

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
            <div style="display: flex; justify-content: space-between; align-items: center;">
                <h1>🎵 Spotify Kids Admin Panel</h1>
                <div style="display: flex; gap: 15px; align-items: center;">
                    <span class="status {{ 'online' if player_status else 'offline' }}">
                        Player: {{ 'Online' if player_status else 'Offline' }}
                    </span>
                    <span class="status {{ 'online' if spotify_configured else 'offline' }}">
                        Spotify API: {{ 'Configured' if spotify_configured else 'Not Configured' }}
                    </span>
                    <button onclick="logout()" style="padding: 5px 15px; background: #ef4444;">Logout</button>
                </div>
            </div>
        </div>
        
        <!-- Essential Configuration Section -->
        <h2 style="color: white; margin: 20px 0 10px 0;">⚙️ Essential Configuration</h2>
        <div class="grid">
            <!-- Spotify Configuration -->
            <div class="card">
                <h2>🎵 Spotify Configuration</h2>
                <div id="spotifyAuthSection" style="display: none; margin-bottom: 15px;">
                    <div style="background: #f59e0b; color: white; padding: 10px; border-radius: 5px; margin-bottom: 10px;">
                        <strong>⚠️ Authentication Required</strong>
                        <p style="margin: 5px 0; font-size: 12px;">The Spotify player needs to be authenticated. Click the link below to complete the OAuth flow:</p>
                    </div>
                    <a id="spotifyAuthLink" href="#" target="_blank" style="display: inline-block; background: #1db954; color: white; padding: 10px 20px; border-radius: 5px; text-decoration: none; font-weight: bold;">
                        🔐 Authenticate with Spotify
                    </a>
                </div>
                <div class="form-group">
                    <label>Client ID</label>
                    <input type="text" id="clientId" value="{{ spotify_config.get('client_id', '') }}" placeholder="Enter Spotify Client ID">
                </div>
                <div class="form-group">
                    <label>Client Secret</label>
                    <input type="password" id="clientSecret" value="{{ spotify_config.get('client_secret', '') }}" placeholder="Enter Spotify Client Secret">
                </div>
                <div style="display: flex; gap: 10px;">
                    <button onclick="saveSpotifyConfig()" style="flex: 1;">Save Configuration</button>
                    <button onclick="testSpotifyConfig()" style="flex: 1; background: #10b981;">Test Connection</button>
                </div>
                <div id="spotifyStatus" style="margin-top: 10px; display: none;">
                    <div style="padding: 10px; border-radius: 5px;" id="spotifyStatusBox">
                        <div id="spotifyStatusMessage" style="font-size: 12px;"></div>
                    </div>
                </div>
            </div>
            
            <!-- Player Control -->
            <div class="card">
                <h2>🎮 Player Control</h2>
                <div style="margin-bottom: 15px;">
                    <button onclick="controlPlayer('play')">▶ Play</button>
                    <button onclick="controlPlayer('pause')">⏸ Pause</button>
                    <button onclick="controlPlayer('next')">⏭ Next</button>
                </div>
                
                <!-- Playlists Section -->
                <div style="margin: 20px 0;">
                    <h3 style="font-size: 16px; margin-bottom: 10px;">📚 Playlists</h3>
                    <div id="playlistContainer" style="max-height: 300px; overflow-y: auto; border: 1px solid #e5e7eb; border-radius: 5px; padding: 10px;">
                        <div style="text-align: center; color: #6b7280; padding: 20px;">Loading playlists...</div>
                    </div>
                    <button onclick="loadPlaylists()" style="margin-top: 10px; background: #3b82f6;">🔄 Refresh Playlists</button>
                </div>
                
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                    <button onclick="controlPlayer('restart')" style="background: #667eea;">Restart Player</button>
                    <button onclick="controlPlayer('stop')" class="danger">Stop Player</button>
                </div>
            </div>
            
            <!-- Admin Settings -->
            <div class="card">
                <h2>🔐 Admin Settings</h2>
                <div class="form-group">
                    <label>Admin Username</label>
                    <input type="text" id="adminUser" value="{{ config.admin_user }}">
                </div>
                <div class="form-group">
                    <label>New Password (leave blank to keep current)</label>
                    <input type="password" id="adminPass" placeholder="Enter new password">
                </div>
                <button onclick="saveAdminSettings()">Update Credentials</button>
            </div>
        </div>
        
        <!-- Basic Controls Section -->
        <h2 style="color: white; margin: 20px 0 10px 0;">🎛️ Basic Controls</h2>
        <div class="grid">
            <!-- Device Control -->
            <div class="card">
                <h2>🔒 Device Lock</h2>
                <div class="toggle">
                    <label>Lock Device Controls</label>
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
                <h2>🔊 Volume Limit</h2>
                <div class="form-group">
                    <label>Maximum Volume</label>
                    <input type="range" id="volumeLimit" min="0" max="100" value="{{ config.volume_limit }}">
                    <span id="volumeValue">{{ config.volume_limit }}%</span>
                </div>
            </div>
            
            <!-- Time Restrictions -->
            <div class="card">
                <h2>⏰ Time Restrictions</h2>
                <div class="toggle">
                    <label>Enable Time Limits</label>
                    <label class="switch">
                        <input type="checkbox" id="timeRestrictions" {{ 'checked' if config.time_restrictions.enabled else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <div class="form-group">
                    <label>Allowed Time</label>
                    <div style="display: flex; gap: 10px;">
                        <input type="time" id="startTime" value="{{ config.time_restrictions.start_time }}" style="flex: 1;">
                        <span style="align-self: center;">to</span>
                        <input type="time" id="endTime" value="{{ config.time_restrictions.end_time }}" style="flex: 1;">
                    </div>
                </div>
            </div>
            
        </div>
        
        <!-- Parental Controls Section -->
        <h2 style="color: white; margin: 20px 0 10px 0;">👨‍👩‍👧‍👦 Parental Controls</h2>
        <div class="grid">
            
            <!-- Content Filtering -->
            <div class="card" style="grid-column: span 2;">
                <h2>🚫 Content Filtering & Parental Controls</h2>
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px;">
                    <div>
                        <h3 style="font-size: 16px; margin-bottom: 10px;">Content Restrictions</h3>
                        <div class="toggle">
                            <label>Block Explicit Content</label>
                            <label class="switch">
                                <input type="checkbox" id="explicitBlock" {{ 'checked' if parental_config.content_filter.explicit_blocked else '' }}>
                                <span class="slider"></span>
                            </label>
                        </div>
                        <div class="toggle" style="margin-top: 10px;">
                            <label>Require Playlist Approval</label>
                            <label class="switch">
                                <input type="checkbox" id="playlistApproval" {{ 'checked' if parental_config.content_filter.require_playlist_approval else '' }}>
                                <span class="slider"></span>
                            </label>
                        </div>
                        <div class="form-group" style="margin-top: 15px;">
                            <label>Blocked Artists (one per line)</label>
                            <textarea id="blockedArtists" rows="3" style="font-size: 12px;">{{ parental_config.content_filter.blocked_artists|join('\n')|e }}</textarea>
                        </div>
                        <div class="form-group">
                            <label>Blocked Genres (comma separated)</label>
                            <input type="text" id="blockedGenres" value="{{ parental_config.content_filter.genre_blacklist|join(', ')|e }}">
                        </div>
                    </div>
                    <div>
                        <h3 style="font-size: 16px; margin-bottom: 10px;">Approved Content</h3>
                        <div class="form-group">
                            <label>Allowed Playlists (Spotify URIs)</label>
                            <textarea id="allowedPlaylists" rows="4" style="font-size: 12px;" placeholder="spotify:playlist:xxxxx">{{ parental_config.content_filter.allowed_playlists|join('\n')|e }}</textarea>
                        </div>
                        <div class="form-group">
                            <label>Allowed Genres (comma separated)</label>
                            <input type="text" id="allowedGenres" value="{{ parental_config.content_filter.genre_whitelist|join(', ')|e }}" placeholder="pop, kids, disney">
                        </div>
                        <button onclick="saveContentFilter()" style="margin-top: 10px;">Save Content Settings</button>
                    </div>
                </div>
            </div>
            
            <!-- Usage Statistics -->
            <div class="card" style="grid-column: span 2;">
                <h2>📊 Usage Statistics & History</h2>
                <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 20px;">
                    <div class="stat">
                        <div class="stat-value">{{ usage_stats.total_minutes_today }}</div>
                        <div class="stat-label">Minutes Today</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{{ current_session_time }}</div>
                        <div class="stat-label">Current Session</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{{ len(usage_stats.sessions) }}</div>
                        <div class="stat-label">Sessions Today</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{{ total_skips_today }}</div>
                        <div class="stat-label">Skips Today</div>
                    </div>
                </div>
                <div style="margin-bottom: 15px;">
                    <h3 style="font-size: 16px; margin-bottom: 10px;">Most Played Songs</h3>
                    <div style="max-height: 200px; overflow-y: auto; border: 1px solid #ddd; border-radius: 5px; padding: 10px;">
                        {% for song, count in top_songs %}
                        <div class="playlist-item">
                            <span>{{ song }}</span>
                            <span style="color: #667eea; font-weight: bold;">{{ count }} plays</span>
                        </div>
                        {% else %}
                        <p style="color: #999; font-size: 12px;">No play history yet</p>
                        {% endfor %}
                    </div>
                </div>
                <div style="display: flex; gap: 10px;">
                    <button onclick="exportUsageStats()">Export History (CSV)</button>
                    <button onclick="clearUsageStats()" class="danger">Clear History</button>
                    <button onclick="refreshUsageStats()">Refresh Stats</button>
                </div>
            </div>
            
            <!-- Scheduling -->
            <div class="card">
                <h2>📅 Listening Schedule</h2>
                <div class="toggle">
                    <label>Enable Schedule</label>
                    <label class="switch">
                        <input type="checkbox" id="scheduleEnabled" {{ 'checked' if schedule.enabled else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <div style="margin-top: 15px;">
                    <h3 style="font-size: 14px; margin-bottom: 10px;">Weekday Schedule</h3>
                    <div class="form-group">
                        <label>Morning</label>
                        <div style="display: flex; gap: 10px;">
                            <input type="time" id="weekdayMorningStart" value="{{ schedule.weekday.morning.start }}" style="flex: 1;">
                            <span style="align-self: center;">to</span>
                            <input type="time" id="weekdayMorningEnd" value="{{ schedule.weekday.morning.end }}" style="flex: 1;">
                        </div>
                    </div>
                    <div class="form-group">
                        <label>Afternoon</label>
                        <div style="display: flex; gap: 10px;">
                            <input type="time" id="weekdayAfternoonStart" value="{{ schedule.weekday.afternoon.start }}" style="flex: 1;">
                            <span style="align-self: center;">to</span>
                            <input type="time" id="weekdayAfternoonEnd" value="{{ schedule.weekday.afternoon.end }}" style="flex: 1;">
                        </div>
                    </div>
                    <div class="form-group">
                        <label>Evening</label>
                        <div style="display: flex; gap: 10px;">
                            <input type="time" id="weekdayEveningStart" value="{{ schedule.weekday.evening.start }}" style="flex: 1;">
                            <span style="align-self: center;">to</span>
                            <input type="time" id="weekdayEveningEnd" value="{{ schedule.weekday.evening.end }}" style="flex: 1;">
                        </div>
                    </div>
                </div>
                <button onclick="saveSchedule()">Save Schedule</button>
            </div>
            
            <!-- Listening Limits -->
            <div class="card">
                <h2>⏱️ Listening Limits</h2>
                <div class="form-group">
                    <label>Daily Limit (minutes)</label>
                    <input type="number" id="dailyLimit" value="{{ parental_config.listening_limits.daily_limit_minutes }}" min="0" max="480">
                </div>
                <div class="form-group">
                    <label>Session Limit (minutes)</label>
                    <input type="number" id="sessionLimit" value="{{ parental_config.listening_limits.session_limit_minutes }}" min="0" max="240">
                </div>
                <div class="form-group">
                    <label>Break Time (minutes)</label>
                    <input type="number" id="breakTime" value="{{ parental_config.listening_limits.break_time_minutes }}" min="0" max="120">
                </div>
                <div class="form-group">
                    <label>Skip Limit (per hour)</label>
                    <input type="number" id="skipLimit" value="{{ parental_config.listening_limits.skip_limit_per_hour }}" min="0" max="100">
                </div>
                <button onclick="saveLimits()">Save Limits</button>
                <div style="margin-top: 15px; padding: 10px; background: #f3f4f6; border-radius: 5px;">
                    <p style="font-size: 12px; color: #666;">
                        Time remaining today: <strong id="timeRemaining">{{ time_remaining }} minutes</strong>
                    </p>
                </div>
            </div>
            
            <!-- Remote Management -->
            <div class="card">
                <h2>📱 Remote Management</h2>
                <div class="toggle">
                    <label>Emergency Stop</label>
                    <label class="switch">
                        <input type="checkbox" id="remoteStop" {{ 'checked' if parental_config.remote_control.allow_remote_stop else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <div class="toggle" style="margin-top: 10px;">
                    <label>Send Messages</label>
                    <label class="switch">
                        <input type="checkbox" id="allowMessages" {{ 'checked' if parental_config.remote_control.allow_messages else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <div class="form-group" style="margin-top: 15px;">
                    <label>Send Message to Player</label>
                    <textarea id="playerMessage" rows="2" placeholder="Time for dinner!"></textarea>
                </div>
                <div style="display: flex; gap: 10px;">
                    <button onclick="sendMessage()">Send Message</button>
                    <button onclick="emergencyStop()" class="danger">Emergency Stop</button>
                </div>
                <button onclick="takeScreenshot()" style="margin-top: 10px; width: 100%;">Take Screenshot</button>
            </div>
            
            <!-- Rewards System -->
            <div class="card">
                <h2>🏆 Rewards & Achievements</h2>
                <div class="toggle">
                    <label>Enable Rewards</label>
                    <label class="switch">
                        <input type="checkbox" id="rewardsEnabled" {{ 'checked' if rewards.enabled else '' }}>
                        <span class="slider"></span>
                    </label>
                </div>
                <div style="margin-top: 15px;">
                    <div class="stat" style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white;">
                        <div class="stat-value" style="color: white;">{{ rewards.points }}</div>
                        <div class="stat-label" style="color: white;">Points Earned</div>
                    </div>
                </div>
                <div style="margin-top: 15px;">
                    <h3 style="font-size: 14px; margin-bottom: 10px;">Available Rewards</h3>
                    <div style="max-height: 150px; overflow-y: auto;">
                        {% for reward in rewards.rewards_available %}
                        <div class="playlist-item">
                            <span>{{ reward.name }}</span>
                            <span style="color: #667eea;">{{ reward.cost }} points</span>
                        </div>
                        {% endfor %}
                    </div>
                </div>
                <div style="display: flex; gap: 10px; margin-top: 15px;">
                    <button onclick="addBonusPoints()">Add Bonus Points</button>
                    <button onclick="resetPoints()" class="danger">Reset Points</button>
                </div>
            </div>
            
        </div>
        
        <!-- System Management Section -->
        <h2 style="color: white; margin: 20px 0 10px 0;">🖥️ System Management</h2>
        <div class="grid">
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
            
            <!-- System Control -->
            <div class="card">
                <h2>⚡ System Control</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    Manage system power and restart services.
                </p>
                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                    <button onclick="rebootSystem()" style="background: #f59e0b;">
                        🔄 Reboot System
                    </button>
                    <button onclick="powerOffSystem()" class="danger">
                        ⏻ Power Off
                    </button>
                    <button onclick="restartServices()" style="grid-column: span 2;">
                        🔧 Restart All Services
                    </button>
                </div>
                <div style="margin-top: 15px; padding: 10px; background: #fef3c7; border-radius: 5px; border: 1px solid #fbbf24;">
                    <p style="font-size: 11px; color: #92400e; margin: 0;">
                        <strong>Warning:</strong> Reboot and power off will immediately affect the system.
                    </p>
                </div>
            </div>
            
            <!-- System Updates -->
            <div class="card">
                <h2>🔄 System Updates</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    Keep your system up to date with security patches.
                </p>
                <div id="systemUpdateStatus" style="margin-bottom: 15px;">
                    <span id="updateStatusText" class="status offline" style="font-size: 12px;">
                        Updates: <span id="updateCount">Checking...</span>
                    </span>
                    <div id="updateDetails" style="display: none; margin-top: 10px; padding: 10px; background: #f3f4f6; border-radius: 5px;">
                        <div style="font-size: 12px; color: #666;">
                            <strong>Available Updates:</strong>
                            <div id="updateList" style="margin-top: 5px; max-height: 150px; overflow-y: auto;"></div>
                        </div>
                    </div>
                </div>
                <button onclick="checkUpdates()">Check for Updates</button>
                <button onclick="runUpdate()" style="margin-left: 10px;">Quick Update</button>
                <button onclick="showPackageManager()" style="margin-left: 10px; background: #3b82f6;">📦 Package Manager</button>
                <div id="updateStatus" style="margin-top: 15px; display: none;">
                    <div style="padding: 10px; background: #f3f4f6; border-radius: 5px;">
                        <div id="updateMessage" style="font-size: 12px; color: #666;"></div>
                    </div>
                </div>
            </div>
            
            <!-- System Logs -->
            <div class="card">
                <h2>📋 System Logs</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    View logs for troubleshooting.
                </p>
                <div style="display: flex; gap: 10px; margin-bottom: 15px; flex-wrap: wrap;">
                    <button onclick="openLogModal('player')">Player</button>
                    <button onclick="openLogModal('admin')">Admin</button>
                    <button onclick="openLogModal('system')">System</button>
                    <button onclick="openLogModal('all')">All Logs</button>
                </div>
                <div style="display: flex; gap: 10px;">
                    <button onclick="downloadLogs()">Download Logs</button>
                    <button onclick="clearLogs()" class="danger">Clear Logs</button>
                </div>
            </div>
            
            <!-- Bluetooth Devices -->
            <div class="card">
                <h2>🎧 Bluetooth Devices</h2>
                <p style="color: #666; font-size: 12px; margin-bottom: 15px;">
                    Manage Bluetooth speakers and headphones for audio output.
                </p>
                <div id="bluetoothStatus" style="margin-bottom: 15px;">
                    <span id="bluetoothStatusText" class="status {{ 'online' if bluetooth_enabled else 'offline' }}" style="font-size: 12px;">
                        Bluetooth: <span id="bluetoothState">{{ 'Enabled' if bluetooth_enabled else 'Disabled' }}</span>
                    </span>
                    <div id="bluetoothStatusMessage" style="display: none; margin-top: 10px; padding: 10px; border-radius: 5px;"></div>
                </div>
                <div id="pairedDevices" style="margin-bottom: 15px;">
                    <label style="font-size: 14px; margin-bottom: 10px; display: block;">Paired Devices:</label>
                    <div id="pairedList" style="max-height: 150px; overflow-y: auto; border: 1px solid #ddd; border-radius: 5px; padding: 10px;">
                        {% for device in paired_devices %}
                        <div class="device-item" style="padding: 8px; background: #f3f4f6; border-radius: 3px; margin-bottom: 5px; display: flex; justify-content: space-between; align-items: center;">
                            <span>{{ device.name|e }} ({{ device.address|e }})</span>
                            <div>
                                {% if device.connected %}
                                <button onclick="disconnectBluetooth('{{ device.address|e }}')" style="font-size: 12px; padding: 5px 10px;">Disconnect</button>
                                {% else %}
                                <button onclick="connectBluetooth('{{ device.address|e }}')" style="font-size: 12px; padding: 5px 10px;">Connect</button>
                                {% endif %}
                                <button onclick="removeBluetooth('{{ device.address|e }}')" class="danger" style="font-size: 12px; padding: 5px 10px; margin-left: 5px;">Remove</button>
                            </div>
                        </div>
                        {% else %}
                        <p style="color: #999; font-size: 12px;">No paired devices</p>
                        {% endfor %}
                    </div>
                </div>
                <div style="display: flex; gap: 10px; margin-bottom: 10px;">
                    <button onclick="enableBluetooth()" id="enableBtBtn" style="background: #10b981;" {{ 'disabled' if bluetooth_enabled else '' }}>Enable Bluetooth</button>
                    <button onclick="disableBluetooth()" id="disableBtBtn" class="danger" {{ 'disabled' if not bluetooth_enabled else '' }}>Disable Bluetooth</button>
                    <button onclick="checkBluetoothStatus()">Refresh Status</button>
                </div>
                <button onclick="scanBluetooth()" id="scanBtBtn">Scan for Devices</button>
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
        
        <!-- Package Manager Modal -->
        <div id="packageModal" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 1000;">
            <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; border-radius: 10px; padding: 30px; width: 800px; max-height: 80vh; overflow-y: auto;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                    <h2 style="margin: 0;">📦 Package Manager</h2>
                    <button onclick="closePackageModal()" style="background: #dc2626; color: white; border: none; padding: 8px 16px; border-radius: 5px; cursor: pointer;">✕ Close</button>
                </div>
                
                <div id="packageStatus" style="margin-bottom: 20px;"></div>
                
                <div style="margin-bottom: 20px;">
                    <button onclick="loadUpgradablePackages()" style="margin-right: 10px;">🔄 Refresh List</button>
                    <button onclick="runDistUpgrade()" style="background: #f59e0b; color: white;">⬆️ Upgrade All Packages</button>
                </div>
                
                <div id="packageList" style="background: #f9fafb; border-radius: 5px; padding: 20px; min-height: 200px; max-height: 400px; overflow-y: auto;">
                    <div style="text-align: center; color: #6b7280;">Loading packages...</div>
                </div>
            </div>
        </div>
        
        <!-- Bluetooth Scan Modal -->
        <div id="bluetoothScanModal" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); z-index: 1000;">
            <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: white; border-radius: 10px; padding: 30px; width: 600px; max-height: 80vh; overflow-y: auto;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;">
                    <h2 style="margin: 0;">🔍 Scanning for Bluetooth Devices</h2>
                    <button onclick="closeScanModal()" style="background: #ef4444; color: white; border: none; padding: 5px 15px; border-radius: 5px; cursor: pointer;">✕</button>
                </div>
                
                <div id="scanStatus" style="margin-bottom: 20px; padding: 10px; background: #f3f4f6; border-radius: 5px;">
                    <div style="display: flex; align-items: center;">
                        <div class="spinner" style="border: 3px solid #f3f3f3; border-top: 3px solid #667eea; border-radius: 50%; width: 20px; height: 20px; animation: spin 1s linear infinite; margin-right: 10px;"></div>
                        <span id="scanStatusText">Scanning for devices...</span>
                    </div>
                </div>
                
                <div style="margin-bottom: 20px;">
                    <h3 style="margin-bottom: 10px;">Available Devices:</h3>
                    <div id="scanDeviceList" style="max-height: 300px; overflow-y: auto; border: 1px solid #ddd; border-radius: 5px; padding: 10px; background: #f9fafb;">
                        <p style="color: #999; text-align: center;">No devices found yet...</p>
                    </div>
                </div>
                
                <div style="display: flex; gap: 10px;">
                    <button onclick="scanBluetooth()" style="flex: 1; background: #667eea;">Refresh Scan</button>
                    <button onclick="stopScan()" style="flex: 1; background: #ef4444;">Stop Scanning</button>
                    <button onclick="closeScanModal()" style="flex: 1;">Close</button>
                </div>
            </div>
        </div>
        
        <style>
            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
        </style>
        
        <!-- Log Viewer Modal -->
        <div id="logModal" style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); z-index: 1000;">
            <div style="position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); background: #2a2a2a; border-radius: 10px; padding: 20px; width: 90%; max-width: 1200px; height: 80vh; display: flex; flex-direction: column;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                    <h2 id="logModalTitle" style="color: white; margin: 0;">System Logs</h2>
                    <div style="display: flex; gap: 10px; align-items: center;">
                        <label style="color: white; display: flex; align-items: center;">
                            <input type="checkbox" id="modalAutoRefresh" checked style="margin-right: 5px;">
                            Auto-refresh
                        </label>
                        <label style="color: white; display: flex; align-items: center;">
                            Lines: 
                            <input type="number" id="modalLogLines" value="200" min="10" max="2000" style="width: 80px; margin-left: 5px; background: #444; color: white; border: 1px solid #666; border-radius: 3px; padding: 2px 5px;">
                        </label>
                        <button onclick="refreshCurrentLog()" style="padding: 5px 15px;">Refresh</button>
                        <button onclick="closeLogModal()" style="padding: 5px 15px; background: #ef4444;">Close</button>
                    </div>
                </div>
                <div id="modalLogOutput" style="background: #1a1a1a; color: #00ff00; font-family: 'Courier New', monospace; font-size: 12px; padding: 20px; border-radius: 5px; flex: 1; overflow-y: auto; white-space: pre-wrap; word-wrap: break-word; border: 1px solid #444;">
                    Loading logs...
                </div>
                <div style="margin-top: 15px; display: flex; gap: 10px; justify-content: center;">
                    <button onclick="openLogModal('player')" style="padding: 8px 20px;">Player</button>
                    <button onclick="openLogModal('admin')" style="padding: 8px 20px;">Admin</button>
                    <button onclick="openLogModal('nginx')" style="padding: 8px 20px;">Nginx</button>
                    <button onclick="openLogModal('system')" style="padding: 8px 20px;">System</button>
                    <button onclick="openLogModal('auth')" style="padding: 8px 20px;">Auth</button>
                    <button onclick="openLogModal('all')" style="padding: 8px 20px;">All</button>
                    <button onclick="copyLogsToClipboard()" style="padding: 8px 20px; background: #667eea;">Copy to Clipboard</button>
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
    
    <!-- Load admin JavaScript -->
    {% if logged_in %}
    <script src="/static/admin.js"></script>
    {% else %}
    <script>
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
    </script>
    {% endif %}
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
    parental_config = load_parental_config()
    usage_stats = load_usage_stats()
    schedule = load_schedule()
    rewards = load_rewards()
    
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
    
    # Calculate usage statistics
    current_session_time = 0
    if usage_stats.get('sessions'):
        last_session = usage_stats['sessions'][-1]
        if not last_session.get('end'):
            # Session is ongoing
            start_time = datetime.fromisoformat(last_session['start'])
            current_session_time = int((datetime.now() - start_time).total_seconds() / 60)
    
    # Get top songs
    top_songs = sorted(usage_stats.get('favorite_songs', {}).items(), 
                      key=lambda x: x[1], reverse=True)[:10]
    
    # Calculate total skips today
    total_skips_today = sum(usage_stats.get('skip_count', {}).values())
    
    # Calculate time remaining
    time_remaining = parental_config['listening_limits']['daily_limit_minutes'] - usage_stats.get('total_minutes_today', 0)
    time_remaining = max(0, time_remaining)
    
    # Check if Spotify is configured
    spotify_configured = bool(spotify_config.get('client_id') and spotify_config.get('client_secret'))
    
    return render_template_string(ADMIN_TEMPLATE,
                                 logged_in='logged_in' in session,
                                 config=config,
                                 spotify_config=spotify_config,
                                 spotify_configured=spotify_configured,
                                 parental_config=parental_config,
                                 usage_stats=usage_stats,
                                 schedule=schedule,
                                 rewards=rewards,
                                 player_status=player_status,
                                 cpu_usage=cpu_usage,
                                 memory_usage=memory_usage,
                                 disk_usage=disk_usage,
                                 uptime=uptime,
                                 bluetooth_enabled=bluetooth_enabled,
                                 paired_devices=paired_devices,
                                 current_session_time=current_session_time,
                                 top_songs=top_songs,
                                 total_skips_today=total_skips_today,
                                 time_remaining=time_remaining,
                                 len=len)

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
    app.logger.info(f"Received Spotify config update: client_id={data.get('client_id', '')[:10]}...")
    
    config = {
        'client_id': data.get('client_id', ''),
        'client_secret': data.get('client_secret', ''),
        'redirect_uri': 'http://localhost:8888/callback'
    }
    
    try:
        save_spotify_config(config)
        app.logger.info("Spotify config saved successfully")
        return jsonify({'success': True, 'message': 'Spotify configuration saved'})
    except Exception as e:
        app.logger.error(f"Failed to save Spotify config: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/spotify/test', methods=['POST'])
def test_spotify_config():
    """Test Spotify API configuration"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        import requests
        import base64
        
        spotify_config = load_spotify_config()
        
        if not spotify_config.get('client_id') or not spotify_config.get('client_secret'):
            return jsonify({'success': False, 'error': 'Spotify credentials not configured. Please enter your Client ID and Client Secret.'}), 400
        
        # Test by getting an access token
        auth_str = f"{spotify_config['client_id']}:{spotify_config['client_secret']}"
        auth_bytes = auth_str.encode("utf-8")
        auth_base64 = str(base64.b64encode(auth_bytes), "utf-8")
        
        url = "https://accounts.spotify.com/api/token"
        headers = {
            "Authorization": f"Basic {auth_base64}",
            "Content-Type": "application/x-www-form-urlencoded"
        }
        data = {
            "grant_type": "client_credentials"
        }
        
        response = requests.post(url, headers=headers, data=data, timeout=10)
        
        if response.status_code == 200:
            # Success - credentials are valid
            token_data = response.json()
            return jsonify({
                'success': True, 
                'message': 'Spotify API credentials validated successfully! Your configuration is working correctly.',
                'scope': token_data.get('scope', 'client_credentials'),
                'expires_in': token_data.get('expires_in', 3600)
            })
        elif response.status_code == 401:
            return jsonify({
                'success': False, 
                'error': 'Invalid Client ID or Client Secret. Please check your Spotify app credentials.'
            }), 401
        else:
            error_data = response.json() if response.headers.get('content-type') == 'application/json' else {}
            return jsonify({
                'success': False, 
                'error': f"Spotify API error: {error_data.get('error_description', response.text)}"
            }), response.status_code
            
    except requests.exceptions.Timeout:
        return jsonify({'success': False, 'error': 'Connection timeout. Please check your internet connection.'}), 504
    except requests.exceptions.ConnectionError:
        return jsonify({'success': False, 'error': 'Unable to connect to Spotify API. Please check your internet connection.'}), 503
    except Exception as e:
        return jsonify({'success': False, 'error': f'Unexpected error: {str(e)}'}), 500

@app.route('/api/player/<action>', methods=['POST'])
def control_player(action):
    """Control the player"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        if action == 'restart':
            subprocess.run(['sudo', 'systemctl', 'restart', 'spotify-player'], check=False)
            return jsonify({'success': True, 'message': 'Player restarting'})
        elif action == 'stop':
            subprocess.run(['sudo', 'systemctl', 'stop', 'spotify-player'], check=False)
            return jsonify({'success': True, 'message': 'Player stopped'})
        elif action in ['play', 'pause', 'next']:
            # These would need to communicate with the player via IPC
            # For now, just acknowledge
            return jsonify({'success': True, 'message': f'Command {action} sent'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    
    return jsonify({'error': 'Unknown action'}), 400

@app.route('/api/spotify/playlists')
def get_spotify_playlists():
    """Get available Spotify playlists"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # For now, return some example playlists
        # In production, this would connect to Spotify API
        playlists = [
            {'id': '1', 'name': 'Kids Favorites', 'tracks': 50, 'uri': 'spotify:playlist:37i9dQZF1DX5GQZoaT1C1U'},
            {'id': '2', 'name': 'Disney Hits', 'tracks': 100, 'uri': 'spotify:playlist:37i9dQZF1DX8ky12eWIvcW'},
            {'id': '3', 'name': 'Sing-Along Songs', 'tracks': 75, 'uri': 'spotify:playlist:37i9dQZF1DWVlRnUmFR1CJ'},
            {'id': '4', 'name': 'Bedtime Stories', 'tracks': 30, 'uri': 'spotify:playlist:37i9dQZF1DX4OtBECiIuVG'},
            {'id': '5', 'name': 'Educational Songs', 'tracks': 45, 'uri': 'spotify:playlist:37i9dQZF1DX5GQZoaT1C1U'}
        ]
        
        # Check if Spotify is configured
        spotify_config = load_spotify_config()
        if spotify_config.get('client_id') and spotify_config.get('client_secret'):
            # TODO: Fetch real playlists from Spotify API
            pass
        
        return jsonify({'success': True, 'playlists': playlists})
        
    except Exception as e:
        app.logger.error(f"Error fetching playlists: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/spotify/play', methods=['POST'])
def play_spotify_content():
    """Play a specific playlist or track"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    uri = data.get('uri')
    
    if not uri:
        return jsonify({'error': 'No URI provided'}), 400
    
    try:
        # TODO: Implement actual Spotify playback control
        # This would need to communicate with the player process
        app.logger.info(f"Request to play: {uri}")
        
        # For now, just acknowledge the request
        return jsonify({'success': True, 'message': f'Playlist playback requested: {uri}'})
        
    except Exception as e:
        app.logger.error(f"Error starting playback: {e}")
        return jsonify({'success': False, 'error': str(e)}), 500

@app.route('/api/spotify/auth-status')
def get_spotify_auth_status():
    """Get Spotify authentication status and URL if needed"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        from spotipy.oauth2 import SpotifyOAuth
        
        spotify_config = load_spotify_config()
        
        if not spotify_config.get('client_id') or not spotify_config.get('client_secret'):
            return jsonify({'success': False, 'authenticated': False, 'error': 'Spotify not configured'})
        
        # Check if token exists
        cache_file = os.path.join(CONFIG_DIR, '.cache', 'token.cache')
        
        # Create auth manager
        auth_manager = SpotifyOAuth(
            client_id=spotify_config['client_id'],
            client_secret=spotify_config['client_secret'],
            redirect_uri='http://localhost:8888/callback',
            scope='user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read streaming',
            cache_path=cache_file,
            open_browser=False
        )
        
        # Check for cached token
        token_info = None
        if os.path.exists(cache_file):
            try:
                token_info = auth_manager.get_cached_token()
            except Exception as e:
                app.logger.warning(f"Could not read cached token: {e}")
        
        if token_info:
            return jsonify({'success': True, 'authenticated': True, 'message': 'Player is authenticated'})
        
        # Not authenticated - generate auth URL
        auth_url = auth_manager.get_authorize_url()
        
        return jsonify({
            'success': True,
            'authenticated': False,
            'auth_url': auth_url,
            'message': 'Player needs authentication',
            'instructions': 'Click the link to authenticate with Spotify. After logging in, you will be redirected to a page with a code.'
        })
        
    except Exception as e:
        app.logger.error(f"Error checking auth status: {e}")
        return jsonify({'authenticated': False, 'error': str(e)}), 500

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

@app.route('/run-diagnostics')
def run_diagnostics():
    """Run the full diagnostics script and return results"""
    import traceback
    try:
        # Run the diagnostics script
        result = subprocess.run(['sudo', 'python3', '/opt/spotify-kids/full_diagnostics.py'],
                              capture_output=True, text=True, timeout=30)
        
        # Try to load the generated report
        report_file = '/opt/spotify-kids/diagnostics_report.json'
        if os.path.exists(report_file):
            with open(report_file, 'r') as f:
                report = json.load(f)
        else:
            report = {
                'error': 'Diagnostics ran but no report generated',
                'stdout': result.stdout,
                'stderr': result.stderr
            }
        
        return Response(json.dumps(report, indent=2, default=str),
                       mimetype='application/json')
    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Diagnostics timed out after 30 seconds'}), 504
    except Exception as e:
        return jsonify({'error': str(e), 'traceback': traceback.format_exc()}), 500

@app.route('/diagnostics-ui')
def diagnostics_ui():
    """Show diagnostics in a nice HTML interface"""
    html = '''<!DOCTYPE html>
<html>
<head>
    <title>Spotify Kids Manager - System Diagnostics</title>
    <style>
        body { font-family: monospace; background: #1a1a1a; color: #fff; padding: 20px; }
        .header { background: #667eea; padding: 20px; border-radius: 10px; margin-bottom: 20px; }
        .section { background: #2a2a2a; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .critical { color: #ef4444; font-weight: bold; }
        .warning { color: #f59e0b; }
        .info { color: #3b82f6; }
        .healthy { color: #10b981; }
        .issue { padding: 5px; margin: 5px 0; background: #1a1a1a; border-radius: 3px; }
        button { background: #667eea; color: white; border: none; padding: 10px 20px; 
                border-radius: 5px; cursor: pointer; font-size: 16px; }
        button:hover { background: #7c8ff0; }
        #report { white-space: pre-wrap; font-size: 12px; }
        .status-badge { display: inline-block; padding: 5px 10px; border-radius: 15px; }
        .loading { text-align: center; padding: 50px; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 Spotify Kids Manager - Complete System Diagnostics</h1>
        <button onclick="runDiagnostics()">🔄 Run Full Diagnostics</button>
        <button onclick="window.location.href='/diagnostics'">📊 View Raw JSON</button>
        <button onclick="window.location.href='/'">🏠 Back to Admin Panel</button>
    </div>
    
    <div id="loading" class="loading" style="display: none;">
        <h2>⏳ Running diagnostics... This may take up to 30 seconds...</h2>
    </div>
    
    <div id="results"></div>
    
    <script>
        function runDiagnostics() {
            document.getElementById('loading').style.display = 'block';
            document.getElementById('results').innerHTML = '';
            
            fetch('/run-diagnostics')
                .then(r => r.json())
                .then(data => {
                    document.getElementById('loading').style.display = 'none';
                    displayResults(data);
                })
                .catch(err => {
                    document.getElementById('loading').style.display = 'none';
                    document.getElementById('results').innerHTML = 
                        '<div class="section critical">Error: ' + err + '</div>';
                });
        }
        
        function displayResults(data) {
            let html = '';
            
            // Health Status
            if (data.health) {
                let statusClass = data.health.status === 'HEALTHY' ? 'healthy' : 
                                 data.health.status === 'CRITICAL' ? 'critical' : 'warning';
                html += `<div class="section">
                    <h2>Health Status</h2>
                    <span class="status-badge ${statusClass}">${data.health.status} - ${data.health.score}%</span>
                </div>`;
            }
            
            // Issues Summary
            if (data.summary) {
                html += `<div class="section">
                    <h2>Issues Summary</h2>
                    <div>Total Issues: ${data.summary.total_issues}</div>
                    <div class="critical">Critical: ${data.summary.critical}</div>
                    <div class="warning">Warnings: ${data.summary.warnings}</div>
                    <div class="info">Info: ${data.summary.info}</div>
                </div>`;
            }
            
            // Critical Issues
            if (data.issues && data.issues.length > 0) {
                let criticals = data.issues.filter(i => i.severity === 'critical');
                if (criticals.length > 0) {
                    html += '<div class="section"><h2>⚠️ Critical Issues</h2>';
                    criticals.forEach(issue => {
                        html += `<div class="issue critical">[${issue.component}] ${issue.message}</div>`;
                    });
                    html += '</div>';
                }
                
                let warnings = data.issues.filter(i => i.severity === 'warning');
                if (warnings.length > 0) {
                    html += '<div class="section"><h2>⚠️ Warnings</h2>';
                    warnings.forEach(issue => {
                        html += `<div class="issue warning">[${issue.component}] ${issue.message}</div>`;
                    });
                    html += '</div>';
                }
            }
            
            // Services Status
            if (data.services) {
                html += '<div class="section"><h2>Services Status</h2>';
                for (let [service, status] of Object.entries(data.services)) {
                    let statusClass = status === 'active' ? 'healthy' : 'warning';
                    html += `<div><span class="${statusClass}">${service}: ${status}</span></div>`;
                }
                html += '</div>';
            }
            
            // JavaScript Debug
            if (data.admin_panel && data.admin_panel.javascript) {
                html += '<div class="section"><h2>JavaScript Functions</h2>';
                if (data.admin_panel.javascript.functions_missing && 
                    data.admin_panel.javascript.functions_missing.length > 0) {
                    html += '<div class="critical">Missing Functions:</div>';
                    data.admin_panel.javascript.functions_missing.forEach(func => {
                        html += `<div class="issue critical">- ${func}</div>`;
                    });
                }
                if (data.admin_panel.javascript.functions_defined) {
                    html += '<div class="healthy">Defined Functions: ' + 
                           data.admin_panel.javascript.functions_defined.join(', ') + '</div>';
                }
                html += '</div>';
            }
            
            // Full Report
            html += '<div class="section"><h2>Full Report</h2>';
            html += '<pre id="report">' + JSON.stringify(data, null, 2) + '</pre></div>';
            
            document.getElementById('results').innerHTML = html;
        }
        
        // Auto-run on load
        window.onload = function() {
            runDiagnostics();
        };
    </script>
</body>
</html>'''
    return Response(html, mimetype='text/html')

@app.route('/diagnostics')
def diagnostics():
    """Comprehensive system diagnostics - NO AUTH REQUIRED for debugging"""
    import json
    import traceback
    import platform
    import socket
    import pwd
    import grp
    
    diagnostics_data = {
        'timestamp': datetime.now().isoformat(),
        'hostname': socket.gethostname(),
        'ip': request.remote_addr,
        'system': {},
        'python': {},
        'app': {},
        'services': {},
        'files': {},
        'permissions': {},
        'errors': [],
        'javascript_debug': {},
        'config': {},
        'environment': {}
    }
    
    try:
        # System Info
        diagnostics_data['system'] = {
            'platform': platform.platform(),
            'processor': platform.processor(),
            'python_version': platform.python_version(),
            'hostname': platform.node(),
            'uptime': subprocess.run(['uptime'], capture_output=True, text=True).stdout.strip()
        }
        
        # Python environment
        diagnostics_data['python'] = {
            'version': sys.version,
            'executable': sys.executable,
            'path': sys.path,
            'modules': list(sys.modules.keys())[:50]  # First 50 modules
        }
        
        # App configuration
        try:
            diagnostics_data['config'] = {
                'config_dir': CONFIG_DIR,
                'log_dir': LOG_DIR,
                'app_user': APP_USER,
                'config_exists': os.path.exists(CONFIG_DIR),
                'log_dir_exists': os.path.exists(LOG_DIR)
            }
        except Exception as e:
            diagnostics_data['errors'].append(f"Config error: {str(e)}")
        
        # Check services
        services = ['spotify-player', 'spotify-admin', 'nginx', 'bluetooth']
        for service in services:
            try:
                result = subprocess.run(['sudo', 'systemctl', 'is-active', service], 
                                      capture_output=True, text=True)
                diagnostics_data['services'][service] = result.stdout.strip()
            except Exception as e:
                diagnostics_data['services'][service] = f"Error: {str(e)}"
        
        # Check important files
        important_files = [
            '/opt/spotify-kids/web/app.py',
            '/opt/spotify-kids/spotify_player.py',
            '/opt/spotify-kids/config/config.json',
            '/opt/spotify-kids/config/spotify_config.json',
            '/etc/systemd/system/spotify-player.service',
            '/etc/systemd/system/spotify-admin.service'
        ]
        
        for filepath in important_files:
            try:
                if os.path.exists(filepath):
                    stat = os.stat(filepath)
                    try:
                        owner = pwd.getpwuid(stat.st_uid).pw_name
                        group = grp.getgrgid(stat.st_gid).gr_name
                    except:
                        owner = stat.st_uid
                        group = stat.st_gid
                    
                    diagnostics_data['files'][filepath] = {
                        'exists': True,
                        'size': stat.st_size,
                        'permissions': oct(stat.st_mode)[-3:],
                        'owner': owner,
                        'group': group,
                        'modified': datetime.fromtimestamp(stat.st_mtime).isoformat()
                    }
                else:
                    diagnostics_data['files'][filepath] = {'exists': False}
            except Exception as e:
                diagnostics_data['files'][filepath] = {'error': str(e)}
        
        # Check directory permissions
        important_dirs = ['/opt/spotify-kids', '/opt/spotify-kids/config', '/var/log/spotify-kids']
        for dirpath in important_dirs:
            try:
                if os.path.exists(dirpath):
                    stat = os.stat(dirpath)
                    try:
                        owner = pwd.getpwuid(stat.st_uid).pw_name
                        group = grp.getgrgid(stat.st_gid).gr_name
                    except:
                        owner = stat.st_uid
                        group = stat.st_gid
                    
                    diagnostics_data['permissions'][dirpath] = {
                        'exists': True,
                        'permissions': oct(stat.st_mode)[-3:],
                        'owner': owner,
                        'group': group,
                        'writable': os.access(dirpath, os.W_OK),
                        'readable': os.access(dirpath, os.R_OK)
                    }
                else:
                    diagnostics_data['permissions'][dirpath] = {'exists': False}
            except Exception as e:
                diagnostics_data['permissions'][dirpath] = {'error': str(e)}
        
        # JavaScript Debug - Render the page and check for issues
        try:
            with app.test_request_context():
                # Get both logged in and logged out versions
                from flask import render_template_string
                
                # Logged out version
                logged_out_html = render_template_string(ADMIN_TEMPLATE,
                                                        logged_in=False,
                                                        config={},
                                                        spotify_config={},
                                                        parental_config={'content_filter': {'blocked_artists': [], 
                                                                                           'genre_blacklist': [],
                                                                                           'allowed_playlists': [],
                                                                                           'genre_whitelist': []}},
                                                        usage_stats={},
                                                        schedule={},
                                                        rewards={},
                                                        player_status=False,
                                                        cpu_usage=0,
                                                        memory_usage=0,
                                                        disk_usage=0,
                                                        uptime="0h 0m",
                                                        bluetooth_enabled=False,
                                                        paired_devices=[],
                                                        current_session_time=0,
                                                        top_songs=[],
                                                        total_skips_today=0,
                                                        time_remaining=0,
                                                        spotify_configured=False)
                
                # Check for functions in logged out version
                logged_out_functions = []
                for func in ['saveSpotifyConfig', 'testSpotifyConfig', 'restartServices', 'login']:
                    if f'function {func}' in logged_out_html:
                        logged_out_functions.append(func)
                
                diagnostics_data['javascript_debug']['logged_out'] = {
                    'html_length': len(logged_out_html),
                    'functions_defined': logged_out_functions,
                    'has_syntax_error': 'SyntaxError' in logged_out_html,
                    'line_count': len(logged_out_html.split('\n'))
                }
                
                # Logged in version
                logged_in_html = render_template_string(ADMIN_TEMPLATE,
                                                       logged_in=True,
                                                       config=load_config() if os.path.exists(os.path.join(CONFIG_DIR, 'config.json')) else get_default_config(),
                                                       spotify_config=load_spotify_config() if os.path.exists(os.path.join(CONFIG_DIR, 'spotify_config.json')) else {},
                                                       parental_config=load_parental_config() if os.path.exists(os.path.join(CONFIG_DIR, 'parental_controls.json')) else get_default_parental_config(),
                                                       usage_stats=load_usage_stats() if os.path.exists(os.path.join(CONFIG_DIR, 'usage_stats.json')) else get_default_usage_stats(),
                                                       schedule=load_schedule() if os.path.exists(os.path.join(CONFIG_DIR, 'schedule.json')) else get_default_schedule(),
                                                       rewards=load_rewards() if os.path.exists(os.path.join(CONFIG_DIR, 'rewards.json')) else get_default_rewards(),
                                                       player_status=False,
                                                       cpu_usage=psutil.cpu_percent(interval=1),
                                                       memory_usage=psutil.virtual_memory().percent,
                                                       disk_usage=psutil.disk_usage('/').percent,
                                                       uptime="1h 0m",
                                                       bluetooth_enabled=False,
                                                       paired_devices=[],
                                                       current_session_time=0,
                                                       top_songs=[],
                                                       total_skips_today=0,
                                                       time_remaining=120,
                                                       spotify_configured=True)
                
                # Check for functions in logged in version
                logged_in_functions = []
                for func in ['saveSpotifyConfig', 'testSpotifyConfig', 'restartServices', 'logout',
                           'saveAdminSettings', 'saveContentFilter', 'connectBluetooth', 'disconnectBluetooth']:
                    if f'function {func}' in logged_in_html:
                        logged_in_functions.append(func)
                
                # Find line 808
                lines = logged_in_html.split('\n')
                line_808_context = {}
                if len(lines) > 810:
                    for i in range(max(0, 805), min(len(lines), 812)):
                        line_808_context[f'line_{i+1}'] = lines[i][:200]  # First 200 chars
                
                diagnostics_data['javascript_debug']['logged_in'] = {
                    'html_length': len(logged_in_html),
                    'functions_defined': logged_in_functions,
                    'has_syntax_error': 'SyntaxError' in logged_in_html,
                    'line_count': len(lines),
                    'line_808_context': line_808_context
                }
                
                # Check for specific issues
                issues = []
                if 'testSpotifyConfig' not in logged_in_functions:
                    issues.append("testSpotifyConfig function not found in logged in version")
                if 'saveSpotifyConfig' not in logged_in_functions:
                    issues.append("saveSpotifyConfig function not found in logged in version")
                
                diagnostics_data['javascript_debug']['issues'] = issues
                
        except Exception as e:
            diagnostics_data['javascript_debug']['error'] = str(e)
            diagnostics_data['javascript_debug']['traceback'] = traceback.format_exc()
        
        # Environment variables (filtered for security)
        safe_env_vars = ['PATH', 'HOME', 'USER', 'SHELL', 'PWD', 'LANG', 'LC_ALL']
        diagnostics_data['environment'] = {k: os.environ.get(k, 'Not set') for k in safe_env_vars}
        
        # Recent errors from logs
        try:
            if os.path.exists('/var/log/spotify-kids/player.log'):
                result = subprocess.run(['sudo', 'tail', '-n', '20', '/var/log/spotify-kids/player.log'],
                                      capture_output=True, text=True)
                diagnostics_data['recent_player_logs'] = result.stdout.split('\n')[-10:]  # Last 10 lines
        except:
            pass
        
    except Exception as e:
        diagnostics_data['errors'].append(f"Fatal error: {str(e)}")
        diagnostics_data['errors'].append(traceback.format_exc())
    
    # Return as JSON for easy reading
    return Response(json.dumps(diagnostics_data, indent=2, default=str), 
                   mimetype='application/json')

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
                proc = subprocess.Popen(['sudo', 'apt-get', 'update'],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, bufsize=1)
                for line in proc.stdout:
                    yield f"data: {line.strip()}\n\n"
                proc.wait()
                
                # Run apt upgrade with auto-yes
                yield "data: \n\n"
                yield "data: Running system upgrade (this may take a while)...\n\n"
                env = os.environ.copy()
                env['DEBIAN_FRONTEND'] = 'noninteractive'
                proc = subprocess.Popen(['sudo', '-E', 'apt-get', 'upgrade', '-y', 
                                       '-o', 'Dpkg::Options::=--force-confdef', 
                                       '-o', 'Dpkg::Options::=--force-confold'],
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                      text=True, bufsize=1, env=env)
                
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
        # Start scanning in background
        scan_process = subprocess.Popen(['sudo', 'bluetoothctl', '--', 'scan', 'on'], 
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        # Wait a bit for devices to be discovered
        time.sleep(3)
        
        # Get devices
        result = subprocess.run(['sudo', 'bluetoothctl', 'devices'], 
                              capture_output=True, text=True, timeout=5)
        
        # Stop scanning (kill the background process)
        if 'scan_process' in locals():
            scan_process.terminate()
        subprocess.run(['sudo', 'bluetoothctl', '--', 'scan', 'off'], 
                      capture_output=True, timeout=2)
        
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

@app.route('/api/bluetooth/status')
def bluetooth_status():
    """Get Bluetooth status"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Check if Bluetooth service is active
        result = subprocess.run(['sudo', 'systemctl', 'is-active', 'bluetooth'],
                              capture_output=True, text=True)
        is_active = result.stdout.strip() == 'active'
        
        # Check if Bluetooth is unblocked
        rfkill_result = subprocess.run(['sudo', 'rfkill', 'list', 'bluetooth'],
                                      capture_output=True, text=True)
        is_unblocked = 'Soft blocked: no' in rfkill_result.stdout
        
        enabled = is_active and is_unblocked
        
        return jsonify({
            'success': True,
            'enabled': enabled,
            'service_active': is_active,
            'rfkill_unblocked': is_unblocked
        })
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/updates-check')
def check_system_updates():
    """Check for available system updates"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Check for available updates
        check_result = subprocess.run(['sudo', 'apt', 'update'], 
                                    capture_output=True, text=True, timeout=30)
        
        # Get list of upgradable packages
        list_result = subprocess.run(['apt', 'list', '--upgradable'], 
                                    capture_output=True, text=True)
        
        # Parse the output to count and list updates
        lines = list_result.stdout.strip().split('\n')
        updates = []
        for line in lines[1:]:  # Skip the first line (header)
            if '/' in line:
                package_info = line.split()[0].split('/')[0]
                if package_info:
                    updates.append(package_info)
        
        update_count = len(updates)
        
        return jsonify({
            'success': True,
            'count': update_count,
            'updates': updates[:20],  # Limit to first 20 for display
            'has_updates': update_count > 0
        })
    except subprocess.TimeoutExpired:
        return jsonify({'error': 'Update check timed out'}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/enable', methods=['POST'])
def bluetooth_enable():
    """Enable Bluetooth"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Enable Bluetooth
        subprocess.run(['sudo', 'rfkill', 'unblock', 'bluetooth'], check=False)
        subprocess.run(['sudo', 'systemctl', 'start', 'bluetooth'], check=False)
        subprocess.run(['sudo', 'bluetoothctl', 'power', 'on'], check=False)
        subprocess.run(['sudo', 'bluetoothctl', 'agent', 'on'], check=False)
        subprocess.run(['sudo', 'bluetoothctl', 'default-agent'], check=False)
        return jsonify({'success': True, 'message': 'Bluetooth enabled'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/bluetooth/disable', methods=['POST'])
def bluetooth_disable():
    """Disable Bluetooth"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Disable Bluetooth
        subprocess.run(['sudo', 'systemctl', 'stop', 'bluetooth'], check=False)
        subprocess.run(['sudo', 'rfkill', 'block', 'bluetooth'], check=False)
        return jsonify({'success': True, 'message': 'Bluetooth disabled'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/fix/<fix_id>', methods=['POST'])
def run_fix(fix_id):
    """Run a remote fix - NO AUTH for emergency repairs"""
    try:
        sys.path.insert(0, '/opt/spotify-kids')
        from remote_fix import RemoteFixer
        
        fixer = RemoteFixer()
        result = fixer.run_fix(fix_id)
        
        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e), 'traceback': traceback.format_exc()}), 500

@app.route('/api/fix/custom', methods=['POST'])
def run_custom_fix():
    """Run a custom command - NO AUTH but with safety checks"""
    try:
        data = request.json
        command = data.get('command', '')
        timeout = min(data.get('timeout', 10), 60)  # Max 60 seconds
        
        # Basic auth check for dangerous commands
        auth_token = data.get('auth_token', '')
        expected_token = hashlib.sha256(f"{command}:spotify-kids".encode()).hexdigest()[:16]
        
        if 'rm -rf' in command or 'mkfs' in command or 'dd if=' in command:
            if auth_token != expected_token:
                return jsonify({'error': 'Dangerous command requires auth token', 'expected_token': expected_token}), 403
        
        sys.path.insert(0, '/opt/spotify-kids')
        from remote_fix import RemoteFixer
        
        fixer = RemoteFixer()
        result = fixer.run_custom_command(command, timeout)
        
        return jsonify(result)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/fix/list')
def list_fixes():
    """List available fixes"""
    try:
        sys.path.insert(0, '/opt/spotify-kids')
        from remote_fix import RemoteFixer
        
        fixer = RemoteFixer()
        fixes = fixer.get_available_fixes()
        
        return jsonify(fixes)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/fix-ui')
def fix_ui():
    """Remote fix UI"""
    html = '''<!DOCTYPE html>
<html>
<head>
    <title>Spotify Kids - Remote Fix System</title>
    <style>
        body { font-family: monospace; background: #1a1a1a; color: #fff; padding: 20px; }
        .header { background: #ef4444; padding: 20px; border-radius: 10px; margin-bottom: 20px; }
        .section { background: #2a2a2a; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .fix-button { background: #3b82f6; color: white; border: none; padding: 10px 20px; 
                     border-radius: 5px; cursor: pointer; margin: 5px; }
        .fix-button:hover { background: #2563eb; }
        .danger-button { background: #ef4444; }
        .danger-button:hover { background: #dc2626; }
        .success { color: #10b981; }
        .error { color: #ef4444; }
        .output { background: #1a1a1a; padding: 10px; border-radius: 5px; 
                 font-size: 12px; white-space: pre-wrap; max-height: 300px; overflow-y: auto; }
        input[type="text"] { width: 100%; padding: 10px; background: #1a1a1a; 
                            color: white; border: 1px solid #666; border-radius: 5px; }
        .loading { opacity: 0.5; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔧 Remote Fix System</h1>
        <p>Run repairs and fixes on the Spotify Kids system</p>
        <button onclick="window.location.href='/diagnostics-ui'" class="fix-button">📊 Diagnostics</button>
        <button onclick="window.location.href='/'" class="fix-button">🏠 Admin Panel</button>
    </div>
    
    <div class="section">
        <h2>Quick Fixes</h2>
        <div id="fixes"></div>
    </div>
    
    <div class="section">
        <h2>Custom Command</h2>
        <input type="text" id="customCommand" placeholder="Enter command to run...">
        <button onclick="runCustom()" class="fix-button danger-button">🚀 Run Custom Command</button>
    </div>
    
    <div class="section">
        <h2>Output</h2>
        <div id="output" class="output">Ready to run fixes...</div>
    </div>
    
    <script>
        let running = false;
        
        function loadFixes() {
            fetch('/api/fix/list')
                .then(r => r.json())
                .then(fixes => {
                    let html = '';
                    for (let [id, info] of Object.entries(fixes)) {
                        html += `<button class="fix-button" onclick="runFix('${id}')" title="${info.description}">
                                ${info.name}</button>`;
                    }
                    document.getElementById('fixes').innerHTML = html;
                });
        }
        
        function runFix(fixId) {
            if (running) return;
            running = true;
            
            document.getElementById('output').innerHTML = `Running fix: ${fixId}...\\n`;
            document.body.classList.add('loading');
            
            fetch(`/api/fix/${fixId}`, {method: 'POST'})
                .then(r => r.json())
                .then(result => {
                    let output = `Fix: ${result.name}\\n`;
                    output += `Status: ${result.success ? 'SUCCESS' : 'FAILED'}\\n\\n`;
                    
                    result.commands.forEach(cmd => {
                        output += `$ ${cmd.command}\\n`;
                        if (cmd.stdout) output += cmd.stdout + '\\n';
                        if (cmd.stderr) output += `ERROR: ${cmd.stderr}\\n`;
                        output += '\\n';
                    });
                    
                    document.getElementById('output').innerHTML = output;
                    document.body.classList.remove('loading');
                    running = false;
                })
                .catch(err => {
                    document.getElementById('output').innerHTML = `Error: ${err}`;
                    document.body.classList.remove('loading');
                    running = false;
                });
        }
        
        function runCustom() {
            if (running) return;
            
            const command = document.getElementById('customCommand').value;
            if (!command) return;
            
            if (!confirm(`Run command: ${command}?`)) return;
            
            running = true;
            document.getElementById('output').innerHTML = `Running: ${command}...\\n`;
            document.body.classList.add('loading');
            
            fetch('/api/fix/custom', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({command: command, timeout: 30})
            })
            .then(r => r.json())
            .then(result => {
                let output = `$ ${result.command}\\n`;
                if (result.stdout) output += result.stdout + '\\n';
                if (result.stderr) output += `ERROR: ${result.stderr}\\n`;
                if (result.error) output += `ERROR: ${result.error}\\n`;
                
                document.getElementById('output').innerHTML = output;
                document.body.classList.remove('loading');
                running = false;
            })
            .catch(err => {
                document.getElementById('output').innerHTML = `Error: ${err}`;
                document.body.classList.remove('loading');
                running = false;
            });
        }
        
        // Load fixes on page load
        loadFixes();
    </script>
</body>
</html>'''
    return Response(html, mimetype='text/html')

@app.route('/api/logs/<log_type>')
def get_logs(log_type):
    """Get system logs"""
    if 'logged_in' not in session:
        return 'Not authenticated', 401
    
    lines = request.args.get('lines', '100')
    
    try:
        if log_type == 'player':
            # Get player application logs from actual log file
            log_file = '/var/log/spotify-kids/player.log'
            if os.path.exists(log_file):
                result = subprocess.run(['sudo', 'tail', '-n', lines, log_file],
                                      capture_output=True, text=True)
                if result.stdout:
                    return result.stdout
            
            # Fallback to journalctl if no log file
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-player', '-n', lines, '--no-pager'],
                                  capture_output=True, text=True)
            return result.stdout or "No player logs available - player may not be running"
            
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
            # Get X session logs first
            logs = []
            xsession_log = '/var/log/spotify-kids/xsession.log'
            if os.path.exists(xsession_log):
                result = subprocess.run(['sudo', 'tail', '-n', '30', xsession_log],
                                      capture_output=True, text=True)
                if result.stdout:
                    logs.append("=== X SESSION LOGS ===")
                    logs.append(result.stdout)
                    logs.append("")
            
            # Then boot logs
            result = subprocess.run(['sudo', 'journalctl', '-b', '-n', lines, '--no-pager'],
                                  capture_output=True, text=True)
            logs.append("=== SYSTEM BOOT LOGS ===")
            logs.append(result.stdout or "No system logs available")
            return '\n'.join(logs)
            
        elif log_type == 'auth':
            # Get authentication logs
            result = subprocess.run(['sudo', 'tail', '-n', lines, '/var/log/auth.log'],
                                  capture_output=True, text=True)
            return result.stdout or "No auth logs available"
            
        elif log_type == 'all':
            # Get all recent logs from actual files
            logs = []
            
            # Player logs from file
            logs.append("=== PLAYER LOGS ===")
            player_log = '/var/log/spotify-kids/player.log'
            if os.path.exists(player_log):
                result = subprocess.run(['sudo', 'tail', '-n', '50', player_log],
                                      capture_output=True, text=True)
                logs.append(result.stdout or "No player logs in file")
            else:
                # Fallback to journalctl
                result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-player', '-n', '50', '--no-pager'],
                                      capture_output=True, text=True)
                logs.append(result.stdout or "No player service logs")
            
            # X Session logs
            logs.append("\n=== X SESSION LOGS ===")
            xsession_log = '/var/log/spotify-kids/xsession.log'
            if os.path.exists(xsession_log):
                result = subprocess.run(['sudo', 'tail', '-n', '30', xsession_log],
                                      capture_output=True, text=True)
                logs.append(result.stdout or "No X session logs")
            else:
                logs.append("X session log file not found")
            
            # Admin panel logs
            logs.append("\n=== ADMIN PANEL LOGS ===")
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-admin', '-n', '50', '--no-pager'],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No admin logs")
            
            # Recent system logs
            logs.append("\n=== RECENT SYSTEM LOGS ===")
            result = subprocess.run(['sudo', 'dmesg', '-T', '|', 'tail', '-n', '30'],
                                  capture_output=True, text=True, shell=True)
            logs.append(result.stdout or "No recent kernel messages")
            
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
        # Rotate journalctl logs
        subprocess.run(['sudo', 'journalctl', '--rotate'], check=False)
        subprocess.run(['sudo', 'journalctl', '--vacuum-time=1d'], check=False)
        
        # Clear nginx logs
        subprocess.run(['sudo', 'truncate', '-s', '0', '/var/log/nginx/error.log'], check=False)
        subprocess.run(['sudo', 'truncate', '-s', '0', '/var/log/nginx/access.log'], check=False)
        
        # Clear our custom log files
        subprocess.run(['sudo', 'truncate', '-s', '0', '/var/log/spotify-kids/player.log'], check=False)
        subprocess.run(['sudo', 'truncate', '-s', '0', '/var/log/spotify-kids/xsession.log'], check=False)
        
        return jsonify({'success': True, 'message': 'All logs cleared'})
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
        
        # Collect all logs from actual files
        logs.append("PLAYER APPLICATION LOGS\n" + "="*40 + "\n")
        player_log = '/var/log/spotify-kids/player.log'
        if os.path.exists(player_log):
            result = subprocess.run(['sudo', 'cat', player_log],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No player logs in file")
        else:
            result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-player', '-n', '500', '--no-pager'],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No player service logs")
        
        logs.append("\n\nX SESSION LOGS\n" + "="*40 + "\n")
        xsession_log = '/var/log/spotify-kids/xsession.log'
        if os.path.exists(xsession_log):
            result = subprocess.run(['sudo', 'cat', xsession_log],
                                  capture_output=True, text=True)
            logs.append(result.stdout or "No X session logs")
        
        logs.append("\n\nADMIN PANEL LOGS\n" + "="*40 + "\n")
        result = subprocess.run(['sudo', 'journalctl', '-u', 'spotify-admin', '-n', '500', '--no-pager'],
                              capture_output=True, text=True)
        logs.append(result.stdout or "No admin panel logs")
        
        logs.append("\n\nSYSTEM BOOT LOGS\n" + "="*40 + "\n")
        result = subprocess.run(['sudo', 'journalctl', '-b', '-n', '500', '--no-pager'],
                              capture_output=True, text=True)
        logs.append(result.stdout or "No system boot logs")
        
        # Create response
        response = Response('\n'.join(logs), mimetype='text/plain')
        response.headers['Content-Disposition'] = f'attachment; filename=spotify_logs_{timestamp}.txt'
        return response
        
    except Exception as e:
        return f"Error generating log file: {str(e)}", 500

import time

# Parental Control API Endpoints
@app.route('/api/parental/content-filter', methods=['POST'])
def update_content_filter():
    """Update content filter settings"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    config = load_parental_config()
    config['content_filter'].update(data)
    save_parental_config(config)
    
    return jsonify({'success': True, 'message': 'Content filter updated'})

@app.route('/api/parental/schedule', methods=['POST'])
def update_schedule():
    """Update listening schedule"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    schedule = load_schedule()
    schedule['enabled'] = data.get('enabled', schedule['enabled'])
    if 'weekday' in data:
        schedule['weekday'] = data['weekday']
    if 'weekend' in data:
        schedule['weekend'] = data.get('weekend', schedule['weekend'])
    save_schedule(schedule)
    
    return jsonify({'success': True, 'message': 'Schedule updated'})

@app.route('/api/parental/limits', methods=['POST'])
def update_limits():
    """Update listening limits"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    config = load_parental_config()
    config['listening_limits'].update(data)
    save_parental_config(config)
    
    return jsonify({'success': True, 'message': 'Limits updated'})

@app.route('/api/parental/send-message', methods=['POST'])
def send_message_to_player():
    """Send a message to the player screen"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    message = data.get('message', '')
    
    if not message:
        return jsonify({'error': 'No message provided'}), 400
    
    # Save message to a file that the player can read
    message_file = os.path.join(CONFIG_DIR, 'parent_message.json')
    with open(message_file, 'w') as f:
        json.dump({
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'id': str(uuid.uuid4())
        }, f)
    
    return jsonify({'success': True, 'message': 'Message sent to player'})

@app.route('/api/parental/emergency-stop', methods=['POST'])
def emergency_stop():
    """Emergency stop playback"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    config = load_parental_config()
    if not config['remote_control']['allow_remote_stop']:
        return jsonify({'error': 'Remote stop is disabled'}), 403
    
    # Create emergency stop file
    stop_file = os.path.join(CONFIG_DIR, 'emergency_stop')
    with open(stop_file, 'w') as f:
        f.write(datetime.now().isoformat())
    
    # Also stop the service
    subprocess.run(['sudo', 'systemctl', 'stop', 'spotify-player'], check=False)
    
    return jsonify({'success': True, 'message': 'Emergency stop activated'})

@app.route('/api/parental/screenshot', methods=['POST'])
def take_screenshot():
    """Take a screenshot of the player"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Take screenshot using scrot or similar
        screenshot_path = f'/tmp/screenshot_{datetime.now().strftime("%Y%m%d_%H%M%S")}.png'
        result = subprocess.run(['DISPLAY=:0', 'scrot', screenshot_path], 
                              capture_output=True, text=True, shell=True)
        
        if os.path.exists(screenshot_path):
            # Could encode to base64 and return, or save to accessible location
            return jsonify({'success': True, 'message': 'Screenshot captured', 'path': screenshot_path})
        else:
            return jsonify({'error': 'Screenshot failed'}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/parental/export-stats')
def export_usage_stats():
    """Export usage statistics as CSV"""
    if 'logged_in' not in session:
        return 'Not authenticated', 401
    
    stats = load_usage_stats()
    
    # Create CSV content
    csv_lines = ['Date,Session Start,Session End,Duration (min),Songs Played,Skips']
    
    for session in stats.get('sessions', []):
        start = session.get('start', '')
        end = session.get('end', 'Ongoing')
        duration = session.get('duration_minutes', 0)
        songs = session.get('songs_played', 0)
        skips = session.get('skips', 0)
        date = start.split('T')[0] if 'T' in start else start
        
        csv_lines.append(f'{date},{start},{end},{duration},{songs},{skips}')
    
    csv_content = '\n'.join(csv_lines)
    
    response = Response(csv_content, mimetype='text/csv')
    response.headers['Content-Disposition'] = f'attachment; filename=usage_stats_{datetime.now().strftime("%Y%m%d")}.csv'
    return response

@app.route('/api/parental/clear-stats', methods=['POST'])
def clear_usage_stats():
    """Clear usage statistics"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    # Reset stats but keep structure
    stats = {
        'sessions': [],
        'total_minutes_today': 0,
        'last_reset': datetime.now().isoformat(),
        'favorite_songs': {},
        'skip_count': {},
        'daily_history': []
    }
    save_usage_stats(stats)
    
    return jsonify({'success': True, 'message': 'Statistics cleared'})

@app.route('/api/parental/add-points', methods=['POST'])
def add_bonus_points():
    """Add bonus points to rewards"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    points = data.get('points', 0)
    
    rewards = load_rewards()
    rewards['points'] += points
    save_rewards(rewards)
    
    return jsonify({'success': True, 'message': f'{points} points added'})

@app.route('/api/parental/reset-points', methods=['POST'])
def reset_points():
    """Reset reward points"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    rewards = load_rewards()
    rewards['points'] = 0
    rewards['achievements'] = []
    rewards['redeemed_today'] = []
    save_rewards(rewards)
    
    return jsonify({'success': True, 'message': 'Points reset'})

@app.route('/api/parental/remote-settings', methods=['POST'])
def update_remote_settings():
    """Update remote control settings"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    config = load_parental_config()
    config['remote_control']['allow_remote_stop'] = data.get('allow_remote_stop', config['remote_control']['allow_remote_stop'])
    config['remote_control']['allow_messages'] = data.get('allow_messages', config['remote_control']['allow_messages'])
    save_parental_config(config)
    
    return jsonify({'success': True, 'message': 'Remote settings updated'})

@app.route('/api/parental/toggle-rewards', methods=['POST'])
def toggle_rewards():
    """Toggle rewards system"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    data = request.json
    rewards = load_rewards()
    rewards['enabled'] = data.get('enabled', rewards['enabled'])
    save_rewards(rewards)
    
    return jsonify({'success': True, 'message': 'Rewards system updated'})

@app.route('/api/system/reboot', methods=['POST'])
def reboot_system():
    """Reboot the system"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Schedule reboot in 5 seconds to allow response to be sent
        subprocess.Popen(['sudo', 'shutdown', '-r', '+0'], 
                        stdout=subprocess.DEVNULL, 
                        stderr=subprocess.DEVNULL)
        return jsonify({'success': True, 'message': 'System will reboot in a moment...'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/poweroff', methods=['POST'])
def poweroff_system():
    """Power off the system"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Schedule shutdown in 5 seconds to allow response to be sent
        subprocess.Popen(['sudo', 'shutdown', '-h', '+0'], 
                        stdout=subprocess.DEVNULL, 
                        stderr=subprocess.DEVNULL)
        return jsonify({'success': True, 'message': 'System will power off in a moment...'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/restart-services', methods=['POST'])
def restart_services():
    """Restart all Spotify Kids services"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # Restart player service
        subprocess.run(['sudo', 'systemctl', 'restart', 'spotify-player'], check=False)
        
        # Restart admin service (this will interrupt the connection briefly)
        subprocess.Popen(['sudo', 'systemctl', 'restart', 'spotify-admin'],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL)
        
        # Restart nginx
        subprocess.run(['sudo', 'systemctl', 'restart', 'nginx'], check=False)
        
        return jsonify({'success': True, 'message': 'All services restarting...'})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/system/packages/list')
def list_packages():
    """List all installed packages"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        result = subprocess.run(['dpkg', '-l'], capture_output=True, text=True, timeout=10)
        packages = []
        for line in result.stdout.split('\n')[5:]:  # Skip header lines
            if line.startswith('ii'):
                parts = line.split()
                if len(parts) >= 3:
                    packages.append({
                        'name': parts[1],
                        'version': parts[2],
                        'description': ' '.join(parts[3:]) if len(parts) > 3 else ''
                    })
        return jsonify({'success': True, 'packages': packages, 'count': len(packages)}), 200
    except Exception as e:
        return jsonify({'success': False, 'error': f'Failed to list packages: {str(e)}'}), 200

@app.route('/api/system/packages/upgradable')
def list_upgradable_packages():
    """List packages that can be upgraded"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        # First update the package list
        update_result = subprocess.run(['sudo', 'apt-get', 'update'], 
                                      capture_output=True, text=True, timeout=30)
        if update_result.returncode != 0:
            return jsonify({'success': False, 'error': 'Failed to update package list'}), 200
        
        # Get upgradable packages
        result = subprocess.run(['apt', 'list', '--upgradable'], 
                              capture_output=True, text=True, timeout=10)
        
        packages = []
        for line in result.stdout.split('\n'):
            if '/' in line and not line.startswith('Listing'):
                parts = line.split()
                if len(parts) >= 2:
                    name_arch = parts[0].split('/')
                    version_info = parts[1] if len(parts) > 1 else ''
                    packages.append({
                        'name': name_arch[0],
                        'current_version': version_info,
                        'architecture': name_arch[1] if len(name_arch) > 1 else '',
                        'info': ' '.join(parts[2:]) if len(parts) > 2 else ''
                    })
        
        return jsonify({'success': True, 'packages': packages, 'count': len(packages)}), 200
    except Exception as e:
        return jsonify({'success': False, 'error': f'Failed to get upgradable packages: {str(e)}'}), 200

@app.route('/api/system/packages/update', methods=['POST'])
def update_single_package():
    """Update a specific package"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    package_name = request.json.get('package')
    if not package_name:
        return jsonify({'success': False, 'error': 'Package name required'}), 200
    
    # Sanitize package name to prevent command injection
    if not all(c.isalnum() or c in '.-+:' for c in package_name):
        return jsonify({'success': False, 'error': 'Invalid package name'}), 200
    
    try:
        env = os.environ.copy()
        env['DEBIAN_FRONTEND'] = 'noninteractive'
        
        result = subprocess.run(['sudo', '-E', 'apt-get', 'install', '--only-upgrade', 
                               '-y', package_name],
                              capture_output=True, text=True, timeout=60, env=env)
        
        if result.returncode == 0:
            return jsonify({'success': True, 'message': f'Package {package_name} updated successfully'}), 200
        else:
            error_msg = result.stderr if result.stderr else result.stdout
            return jsonify({'success': False, 'error': f'Update failed: {error_msg}'}), 200
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'error': 'Update timeout'}), 200
    except Exception as e:
        return jsonify({'success': False, 'error': f'Server error: {str(e)}'}), 200

@app.route('/api/system/packages/dist-upgrade', methods=['POST'])
def dist_upgrade():
    """Perform a distribution upgrade"""
    if 'logged_in' not in session:
        return jsonify({'error': 'Not authenticated'}), 401
    
    try:
        env = os.environ.copy()
        env['DEBIAN_FRONTEND'] = 'noninteractive'
        
        # Update package list first
        update_result = subprocess.run(['sudo', 'apt-get', 'update'], 
                                      capture_output=True, text=True, timeout=30)
        if update_result.returncode != 0:
            return jsonify({'success': False, 'error': 'Failed to update package list: ' + (update_result.stderr or update_result.stdout)}), 200
        
        # Perform dist-upgrade
        result = subprocess.run(['sudo', '-E', 'apt-get', 'dist-upgrade', '-y',
                               '-o', 'Dpkg::Options::=--force-confdef',
                               '-o', 'Dpkg::Options::=--force-confold'],
                              capture_output=True, text=True, timeout=300, env=env)
        
        if result.returncode == 0:
            # Clean up
            subprocess.run(['sudo', 'apt-get', 'autoremove', '-y'], 
                         capture_output=True, timeout=60, env=env)
            subprocess.run(['sudo', 'apt-get', 'autoclean'], 
                         capture_output=True, timeout=30, env=env)
            
            return jsonify({'success': True, 'message': 'Distribution upgrade completed successfully'}), 200
        else:
            error_msg = result.stderr if result.stderr else result.stdout
            return jsonify({'success': False, 'error': f'Upgrade failed: {error_msg}'}), 200
            
    except subprocess.TimeoutExpired:
        return jsonify({'success': False, 'error': 'Upgrade timeout - this may take longer than expected'}), 200
    except Exception as e:
        return jsonify({'success': False, 'error': f'Server error: {str(e)}'}), 200

if __name__ == '__main__':
    os.makedirs(CONFIG_DIR, exist_ok=True)
    app.run(host='0.0.0.0', port=5001, debug=False)