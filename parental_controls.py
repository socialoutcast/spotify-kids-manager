#!/usr/bin/env python3
"""
Parental Controls Module for Spotify Kids Player
Handles all parental control features and restrictions
"""

import json
import os
from datetime import datetime, time
import logging

logger = logging.getLogger('ParentalControls')

class ParentalControls:
    def __init__(self, config_dir):
        self.config_dir = config_dir
        self.parental_config_file = os.path.join(config_dir, 'parental_controls.json')
        self.usage_stats_file = os.path.join(config_dir, 'usage_stats.json')
        self.schedule_file = os.path.join(config_dir, 'schedule.json')
        self.rewards_file = os.path.join(config_dir, 'rewards.json')
        self.message_file = os.path.join(config_dir, 'parent_message.json')
        self.emergency_stop_file = os.path.join(config_dir, 'emergency_stop')
        
        self.load_configs()
        self.session_start = datetime.now()
        self.session_songs = 0
        self.session_skips = 0
        self.last_message_id = None
        
    def load_configs(self):
        """Load all configuration files"""
        # Load parental controls
        if os.path.exists(self.parental_config_file):
            with open(self.parental_config_file, 'r') as f:
                self.parental_config = json.load(f)
        else:
            self.parental_config = self.get_default_parental_config()
            
        # Load usage stats
        if os.path.exists(self.usage_stats_file):
            with open(self.usage_stats_file, 'r') as f:
                self.usage_stats = json.load(f)
        else:
            self.usage_stats = self.get_default_usage_stats()
            
        # Load schedule
        if os.path.exists(self.schedule_file):
            with open(self.schedule_file, 'r') as f:
                self.schedule = json.load(f)
        else:
            self.schedule = self.get_default_schedule()
            
        # Load rewards
        if os.path.exists(self.rewards_file):
            with open(self.rewards_file, 'r') as f:
                self.rewards = json.load(f)
        else:
            self.rewards = self.get_default_rewards()
            
        # Check for daily reset
        self.check_daily_reset()
        
    def get_default_parental_config(self):
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
        
    def get_default_usage_stats(self):
        return {
            'sessions': [],
            'total_minutes_today': 0,
            'last_reset': datetime.now().isoformat(),
            'favorite_songs': {},
            'skip_count': {},
            'daily_history': []
        }
        
    def get_default_schedule(self):
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
        
    def get_default_rewards(self):
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
        
    def check_daily_reset(self):
        """Reset daily counters if it's a new day"""
        if 'last_reset' in self.usage_stats:
            last_reset = datetime.fromisoformat(self.usage_stats['last_reset'])
            if last_reset.date() < datetime.now().date():
                # New day - reset counters
                self.usage_stats['total_minutes_today'] = 0
                self.usage_stats['sessions'] = []
                self.usage_stats['skip_count'] = {}
                self.usage_stats['last_reset'] = datetime.now().isoformat()
                self.save_usage_stats()
                
                # Reset rewards
                if self.rewards['enabled']:
                    self.rewards['redeemed_today'] = []
                    # Add daily login points
                    self.rewards['points'] += self.rewards['point_rules']['daily_login']
                    self.save_rewards()
                    
    def is_within_schedule(self):
        """Check if current time is within allowed schedule"""
        if not self.schedule['enabled']:
            return True
            
        now = datetime.now()
        current_time = now.time()
        
        # Check if it's a weekday or weekend
        is_weekend = now.weekday() >= 5
        schedule_key = 'weekend' if is_weekend else 'weekday'
        
        # Check each time slot
        for period in ['morning', 'afternoon', 'evening']:
            slot = self.schedule[schedule_key][period]
            start_time = datetime.strptime(slot['start'], '%H:%M').time()
            end_time = datetime.strptime(slot['end'], '%H:%M').time()
            
            if start_time <= current_time <= end_time:
                return True
                
        return False
        
    def check_time_limits(self):
        """Check if time limits have been exceeded"""
        # Daily limit
        if self.usage_stats['total_minutes_today'] >= self.parental_config['listening_limits']['daily_limit_minutes']:
            return False, "Daily listening limit reached"
            
        # Session limit
        session_minutes = (datetime.now() - self.session_start).total_seconds() / 60
        if session_minutes >= self.parental_config['listening_limits']['session_limit_minutes']:
            return False, "Session limit reached. Time for a break!"
            
        return True, None
        
    def check_skip_limit(self):
        """Check if skip limit has been exceeded"""
        current_hour = datetime.now().hour
        hour_key = f"hour_{current_hour}"
        
        skips_this_hour = self.usage_stats['skip_count'].get(hour_key, 0)
        if skips_this_hour >= self.parental_config['listening_limits']['skip_limit_per_hour']:
            return False
        return True
        
    def is_content_allowed(self, track_info):
        """Check if a track is allowed based on content filters"""
        if not track_info:
            return True
            
        # Check explicit content
        if self.parental_config['content_filter']['explicit_blocked']:
            if track_info.get('explicit', False):
                logger.info(f"Blocked explicit track: {track_info.get('name', 'Unknown')}")
                return False
                
        # Check blocked artists
        artists = [artist['name'] for artist in track_info.get('artists', [])]
        for artist in artists:
            if artist.lower() in [a.lower() for a in self.parental_config['content_filter']['blocked_artists']]:
                logger.info(f"Blocked artist: {artist}")
                return False
                
        # Check blocked songs
        track_name = track_info.get('name', '')
        if track_name.lower() in [s.lower() for s in self.parental_config['content_filter'].get('blocked_songs', [])]:
            logger.info(f"Blocked song: {track_name}")
            return False
            
        return True
        
    def check_emergency_stop(self):
        """Check if emergency stop has been triggered"""
        if os.path.exists(self.emergency_stop_file):
            # Remove the file and return True
            try:
                os.remove(self.emergency_stop_file)
                return True
            except:
                pass
        return False
        
    def check_parent_message(self):
        """Check for new parent messages"""
        if os.path.exists(self.message_file):
            try:
                with open(self.message_file, 'r') as f:
                    message_data = json.load(f)
                    
                # Check if it's a new message
                if message_data.get('id') != self.last_message_id:
                    self.last_message_id = message_data.get('id')
                    return message_data.get('message')
            except:
                pass
        return None
        
    def record_song_play(self, track_info):
        """Record that a song was played"""
        if not track_info:
            return
            
        track_name = f"{track_info.get('name', 'Unknown')} - {track_info['artists'][0]['name'] if track_info.get('artists') else 'Unknown'}"
        
        # Update favorite songs
        if track_name in self.usage_stats['favorite_songs']:
            self.usage_stats['favorite_songs'][track_name] += 1
        else:
            self.usage_stats['favorite_songs'][track_name] = 1
            
        self.session_songs += 1
        
        # Add points if rewards enabled
        if self.rewards['enabled']:
            self.rewards['points'] += self.rewards['point_rules']['per_minute_listened']
            self.save_rewards()
            
        self.save_usage_stats()
        
    def record_skip(self):
        """Record that a song was skipped"""
        current_hour = datetime.now().hour
        hour_key = f"hour_{current_hour}"
        
        if hour_key in self.usage_stats['skip_count']:
            self.usage_stats['skip_count'][hour_key] += 1
        else:
            self.usage_stats['skip_count'][hour_key] = 1
            
        self.session_skips += 1
        self.save_usage_stats()
        
    def start_session(self):
        """Start a new listening session"""
        self.session_start = datetime.now()
        self.session_songs = 0
        self.session_skips = 0
        
        # Add to sessions list
        self.usage_stats['sessions'].append({
            'start': self.session_start.isoformat(),
            'end': None,
            'duration_minutes': 0,
            'songs_played': 0,
            'skips': 0
        })
        self.save_usage_stats()
        
    def end_session(self):
        """End the current listening session"""
        if self.usage_stats['sessions']:
            session_duration = (datetime.now() - self.session_start).total_seconds() / 60
            
            # Update the last session
            self.usage_stats['sessions'][-1].update({
                'end': datetime.now().isoformat(),
                'duration_minutes': round(session_duration, 1),
                'songs_played': self.session_songs,
                'skips': self.session_skips
            })
            
            # Update total minutes
            self.usage_stats['total_minutes_today'] += session_duration
            
            # Check for no-skips bonus
            if self.rewards['enabled'] and self.session_skips == 0 and self.session_songs > 5:
                self.rewards['points'] += self.rewards['point_rules']['no_skips_bonus']
                self.save_rewards()
                
            self.save_usage_stats()
            
    def update_listening_time(self):
        """Update the total listening time (called periodically)"""
        if self.usage_stats['sessions'] and not self.usage_stats['sessions'][-1].get('end'):
            # Session is ongoing
            session_duration = (datetime.now() - self.session_start).total_seconds() / 60
            self.usage_stats['total_minutes_today'] = sum(
                s.get('duration_minutes', 0) for s in self.usage_stats['sessions'][:-1]
            ) + session_duration
            self.save_usage_stats()
            
    def get_time_remaining(self):
        """Get minutes remaining for today"""
        limit = self.parental_config['listening_limits']['daily_limit_minutes']
        used = self.usage_stats['total_minutes_today']
        return max(0, limit - used)
        
    def save_usage_stats(self):
        """Save usage statistics to file"""
        try:
            with open(self.usage_stats_file, 'w') as f:
                json.dump(self.usage_stats, f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save usage stats: {e}")
            
    def save_rewards(self):
        """Save rewards to file"""
        try:
            with open(self.rewards_file, 'w') as f:
                json.dump(self.rewards, f, indent=2)
        except Exception as e:
            logger.error(f"Failed to save rewards: {e}")