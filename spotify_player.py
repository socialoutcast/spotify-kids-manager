#!/usr/bin/env python3

import tkinter as tk
from tkinter import ttk, messagebox, Frame, Label, Button, Entry, Listbox, Canvas, Scrollbar
from PIL import Image, ImageTk
import spotipy
from spotipy.oauth2 import SpotifyOAuth
import json
import os
import threading
import time
import requests
from io import BytesIO
import subprocess
import sys
import logging
from logging.handlers import RotatingFileHandler
import traceback

# Configuration
CONFIG_DIR = os.environ.get('SPOTIFY_CONFIG_DIR', '/opt/spotify-kids/config')
CACHE_DIR = os.path.join(CONFIG_DIR, '.cache')
LOG_DIR = '/var/log/spotify-kids'
CLIENT_ID = None
CLIENT_SECRET = None
DEFAULT_REDIRECT_URI = 'http://127.0.0.1:4202'
DEBUG_MODE = os.environ.get('SPOTIFY_DEBUG', 'true').lower() == 'true'  # Enable debug by default

# Setup logging
try:
    os.makedirs(LOG_DIR, exist_ok=True)
    log_file = os.path.join(LOG_DIR, 'player.log')
except PermissionError:
    # Fallback to /tmp if no permission
    LOG_DIR = '/tmp/spotify-kids'
    os.makedirs(LOG_DIR, exist_ok=True)
    log_file = os.path.join(LOG_DIR, 'player.log')
    print(f"Warning: Using fallback log directory {LOG_DIR}")

# Configure logger
logger = logging.getLogger('SpotifyPlayer')
logger.setLevel(logging.DEBUG if DEBUG_MODE else logging.INFO)

# File handler with rotation
file_handler = RotatingFileHandler(log_file, maxBytes=10*1024*1024, backupCount=5)
file_handler.setLevel(logging.DEBUG if DEBUG_MODE else logging.INFO)

# Console handler for systemd
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setLevel(logging.DEBUG if DEBUG_MODE else logging.INFO)

# Format
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
file_handler.setFormatter(formatter)
console_handler.setFormatter(formatter)

logger.addHandler(file_handler)
logger.addHandler(console_handler)

logger.info("="*60)
logger.info("Spotify Kids Player Starting")
logger.info(f"Debug Mode: {DEBUG_MODE}")
logger.info(f"Config Dir: {CONFIG_DIR}")
logger.info(f"Log Dir: {LOG_DIR}")
logger.info(f"Python Version: {sys.version}")
logger.info("="*60)

class VirtualKeyboard(tk.Toplevel):
    """On-screen keyboard for touchscreen input"""
    def __init__(self, parent, entry_widget):
        super().__init__(parent)
        self.entry_widget = entry_widget
        self.title("Keyboard")
        self.geometry("800x300")
        self.overrideredirect(True)  # Remove window decorations
        self.configure(bg='#282828')
        
        # Position at bottom of screen
        self.update_idletasks()
        x = (self.winfo_screenwidth() // 2) - 400
        y = self.winfo_screenheight() - 350
        self.geometry(f"+{x}+{y}")
        
        self.create_keyboard()
        self.transient(parent)
        self.grab_set()
        
    def create_keyboard(self):
        keys = [
            ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'BACK'],
            ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
            ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
            ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.'],
            ['SPACE', 'DONE']
        ]
        
        for row_num, row in enumerate(keys):
            frame = Frame(self, bg='#282828')
            frame.pack(pady=2)
            
            for key in row:
                if key == 'SPACE':
                    btn = Button(frame, text='Space', width=20, height=2,
                               bg='#535353', fg='white', font=('Arial', 14),
                               command=lambda: self.key_press(' '))
                elif key == 'BACK':
                    btn = Button(frame, text='←', width=8, height=2,
                               bg='#535353', fg='white', font=('Arial', 14),
                               command=self.backspace)
                elif key == 'DONE':
                    btn = Button(frame, text='Done', width=15, height=2,
                               bg='#1DB954', fg='white', font=('Arial', 14),
                               command=self.done)
                else:
                    btn = Button(frame, text=key, width=4, height=2,
                               bg='#535353', fg='white', font=('Arial', 14),
                               command=lambda k=key: self.key_press(k))
                btn.pack(side=tk.LEFT, padx=2)
    
    def key_press(self, key):
        self.entry_widget.insert(tk.END, key)
    
    def backspace(self):
        current = self.entry_widget.get()
        self.entry_widget.delete(0, tk.END)
        self.entry_widget.insert(0, current[:-1])
    
    def done(self):
        self.destroy()

class SpotifyPlayer:
    def __init__(self):
        logger.info("Initializing SpotifyPlayer class")
        try:
            self.root = tk.Tk()
            self.root.title("Spotify Player")
            logger.info("Tkinter root window created")
            
            # Fullscreen kiosk mode
            self.root.attributes('-fullscreen', True)
            self.root.configure(bg='#121212')
            logger.info("Set fullscreen kiosk mode")
            
            # Prevent closing with Alt+F4
            self.root.protocol("WM_DELETE_WINDOW", lambda: None)
            
            # Disable Alt+Tab and other key combinations
            self.root.bind('<Alt-Tab>', lambda e: 'break')
            self.root.bind('<Alt-F4>', lambda e: 'break')
            self.root.bind('<Control-Alt-Delete>', lambda e: 'break')
            logger.debug("Disabled window closing and key combinations")
        
            # Load configuration
            self.load_config()
            
            # Initialize Spotify
            self.sp = None
            self.current_track = None
            self.is_playing = False
            self.current_device = None
            logger.info("Initialized Spotify variables")
            
            # Create UI
            self.create_ui()
            logger.info("UI created successfully")
            
            # Try to authenticate
            self.authenticate()
            
            # Start update loop
            self.update_loop()
            logger.info("Update loop started")
            
        except Exception as e:
            logger.error(f"Failed to initialize SpotifyPlayer: {str(e)}")
            logger.error(traceback.format_exc())
            raise
        
    def load_config(self):
        """Load Spotify API credentials from config file"""
        global CLIENT_ID, CLIENT_SECRET
        
        config_file = os.path.join(CONFIG_DIR, 'spotify_config.json')
        logger.info(f"Looking for config file at: {config_file}")
        
        if os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    CLIENT_ID = config.get('client_id')
                    CLIENT_SECRET = config.get('client_secret')
                    logger.info(f"Config loaded - Client ID: {CLIENT_ID[:8]}..." if CLIENT_ID else "No Client ID found")
                    logger.info("Client Secret: [HIDDEN]" if CLIENT_SECRET else "No Client Secret found")
            except Exception as e:
                logger.error(f"Error loading config: {e}")
        else:
            logger.warning(f"Config file not found at {config_file}")
        
        if not CLIENT_ID or not CLIENT_SECRET:
            logger.info("Missing credentials - showing configuration screen")
            # Show configuration screen
            self.show_config_screen()
        else:
            logger.info("Spotify credentials loaded successfully")
    
    def show_config_screen(self):
        """Show configuration screen for API credentials"""
        config_window = tk.Toplevel(self.root)
        config_window.title("Spotify Configuration")
        config_window.geometry("600x400")
        config_window.configure(bg='#121212')
        
        Label(config_window, text="Spotify API Configuration", 
              font=('Arial', 20, 'bold'), bg='#121212', fg='white').pack(pady=20)
        
        Label(config_window, text="Client ID:", 
              font=('Arial', 12), bg='#121212', fg='white').pack(pady=5)
        client_id_entry = Entry(config_window, width=50, font=('Arial', 12))
        client_id_entry.pack(pady=5)
        client_id_entry.bind('<Button-1>', lambda e: self.show_keyboard(client_id_entry))
        
        Label(config_window, text="Client Secret:", 
              font=('Arial', 12), bg='#121212', fg='white').pack(pady=5)
        client_secret_entry = Entry(config_window, width=50, font=('Arial', 12))
        client_secret_entry.pack(pady=5)
        client_secret_entry.bind('<Button-1>', lambda e: self.show_keyboard(client_secret_entry))
        
        def save_config():
            global CLIENT_ID, CLIENT_SECRET
            CLIENT_ID = client_id_entry.get()
            CLIENT_SECRET = client_secret_entry.get()
            
            os.makedirs(CONFIG_DIR, exist_ok=True)
            config = {
                'client_id': CLIENT_ID,
                'client_secret': CLIENT_SECRET,
                'redirect_uri': DEFAULT_REDIRECT_URI  # Player uses default, web uses dynamic
            }
            
            with open(os.path.join(CONFIG_DIR, 'spotify_config.json'), 'w') as f:
                json.dump(config, f, indent=2)
            
            config_window.destroy()
            self.authenticate()
        
        Button(config_window, text="Save", command=save_config,
               bg='#1DB954', fg='white', font=('Arial', 14),
               width=20, height=2).pack(pady=20)
        
        config_window.transient(self.root)
        config_window.grab_set()
    
    def show_keyboard(self, entry_widget):
        """Show virtual keyboard for entry widget"""
        VirtualKeyboard(self.root, entry_widget)
    
    def authenticate(self):
        """Authenticate with Spotify using OAuth"""
        logger.info("Starting Spotify authentication")
        
        if not CLIENT_ID or not CLIENT_SECRET:
            logger.warning("Cannot authenticate - missing credentials")
            return
        
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            logger.info(f"Cache directory: {CACHE_DIR}")
            
            auth_manager = SpotifyOAuth(
                client_id=CLIENT_ID,
                client_secret=CLIENT_SECRET,
                redirect_uri=DEFAULT_REDIRECT_URI,  # Player uses default, web uses dynamic
                scope='user-read-playback-state user-modify-playback-state user-read-currently-playing playlist-read-private playlist-read-collaborative user-library-read streaming',
                cache_path=os.path.join(CACHE_DIR, 'token.cache'),
                open_browser=False
            )
            logger.info("SpotifyOAuth manager created")
            
            # Get auth URL
            auth_url = auth_manager.get_authorize_url()
            logger.info(f"Auth URL generated: {auth_url[:50]}...")
            
            # Check if we have cached token
            token_info = auth_manager.get_cached_token()
            
            if not token_info:
                logger.info("No cached token found - showing auth screen")
                # Need to authenticate
                self.show_auth_screen(auth_url, auth_manager)
            else:
                logger.info("Using cached token")
                # Use cached token
                self.sp = spotipy.Spotify(auth_manager=auth_manager)
                self.on_authenticated()
                
        except Exception as e:
            logger.error(f"Authentication error: {str(e)}")
            logger.error(traceback.format_exc())
            messagebox.showerror("Authentication Error", str(e))
    
    def show_auth_screen(self, auth_url, auth_manager):
        """Show authentication screen with URL and code input"""
        auth_window = tk.Toplevel(self.root)
        auth_window.title("Spotify Authentication")
        auth_window.geometry("800x600")
        auth_window.configure(bg='#121212')
        
        Label(auth_window, text="Spotify Authentication Required", 
              font=('Arial', 20, 'bold'), bg='#121212', fg='white').pack(pady=20)
        
        Label(auth_window, text="1. Open this URL in a browser on another device:", 
              font=('Arial', 12), bg='#121212', fg='white').pack(pady=10)
        
        url_text = tk.Text(auth_window, height=3, width=80, font=('Arial', 10))
        url_text.pack(pady=10)
        url_text.insert('1.0', auth_url)
        url_text.config(state='disabled')
        
        Label(auth_window, text="2. After authorizing, you'll be redirected to a URL starting with:", 
              font=('Arial', 12), bg='#121212', fg='white').pack(pady=10)
        Label(auth_window, text="http://localhost:8888/callback?code=...", 
              font=('Courier', 10), bg='#121212', fg='#1DB954').pack()
        
        Label(auth_window, text="3. Copy the 'code' value from that URL and paste it here:", 
              font=('Arial', 12), bg='#121212', fg='white').pack(pady=10)
        
        code_entry = Entry(auth_window, width=60, font=('Arial', 12))
        code_entry.pack(pady=10)
        code_entry.bind('<Button-1>', lambda e: self.show_keyboard(code_entry))
        
        def submit_code():
            code = code_entry.get()
            if code:
                try:
                    token_info = auth_manager.get_access_token(code, as_dict=True)
                    self.sp = spotipy.Spotify(auth_manager=auth_manager)
                    auth_window.destroy()
                    self.on_authenticated()
                except Exception as e:
                    messagebox.showerror("Error", f"Authentication failed: {str(e)}")
        
        Button(auth_window, text="Submit Code", command=submit_code,
               bg='#1DB954', fg='white', font=('Arial', 14),
               width=20, height=2).pack(pady=20)
        
        auth_window.transient(self.root)
        auth_window.grab_set()
    
    def on_authenticated(self):
        """Called when authentication is successful"""
        self.refresh_devices()
        self.refresh_playlists()
        self.start_playback_monitor()
    
    def create_ui(self):
        """Create the main UI"""
        # Main container
        main_frame = Frame(self.root, bg='#121212')
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        # Left sidebar
        sidebar = Frame(main_frame, bg='#000000', width=250)
        sidebar.pack(side=tk.LEFT, fill=tk.Y)
        sidebar.pack_propagate(False)
        
        # Logo area
        logo_frame = Frame(sidebar, bg='#000000', height=60)
        logo_frame.pack(fill=tk.X, padx=10, pady=10)
        Label(logo_frame, text="Spotify", font=('Arial', 24, 'bold'),
              bg='#000000', fg='#1DB954').pack()
        
        # Navigation
        nav_frame = Frame(sidebar, bg='#000000')
        nav_frame.pack(fill=tk.BOTH, expand=True, padx=10)
        
        Button(nav_frame, text="🏠 Home", font=('Arial', 12), 
               bg='#000000', fg='white', anchor='w',
               command=self.show_home).pack(fill=tk.X, pady=2)
        Button(nav_frame, text="🔍 Search", font=('Arial', 12),
               bg='#000000', fg='white', anchor='w',
               command=self.show_search).pack(fill=tk.X, pady=2)
        Button(nav_frame, text="📚 Your Library", font=('Arial', 12),
               bg='#000000', fg='white', anchor='w',
               command=self.show_library).pack(fill=tk.X, pady=2)
        
        # Playlists
        Label(nav_frame, text="PLAYLISTS", font=('Arial', 10),
              bg='#000000', fg='#B3B3B3').pack(fill=tk.X, pady=(20, 5))
        
        self.playlist_frame = Frame(nav_frame, bg='#000000')
        self.playlist_frame.pack(fill=tk.BOTH, expand=True)
        
        # Main content area
        self.content_frame = Frame(main_frame, bg='#121212')
        self.content_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        # Bottom player bar
        self.create_player_bar()
        
        # Show home by default
        self.show_home()
    
    def create_player_bar(self):
        """Create the bottom player control bar"""
        player_bar = Frame(self.root, bg='#181818', height=90)
        player_bar.pack(side=tk.BOTTOM, fill=tk.X)
        player_bar.pack_propagate(False)
        
        # Now playing info
        info_frame = Frame(player_bar, bg='#181818', width=300)
        info_frame.pack(side=tk.LEFT, fill=tk.Y, padx=10)
        
        self.album_art_label = Label(info_frame, bg='#181818')
        self.album_art_label.pack(side=tk.LEFT, padx=(0, 10))
        
        track_info = Frame(info_frame, bg='#181818')
        track_info.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        self.track_name_label = Label(track_info, text="No track playing",
                                      font=('Arial', 12, 'bold'),
                                      bg='#181818', fg='white', anchor='w')
        self.track_name_label.pack(fill=tk.X)
        
        self.artist_label = Label(track_info, text="",
                                 font=('Arial', 10),
                                 bg='#181818', fg='#B3B3B3', anchor='w')
        self.artist_label.pack(fill=tk.X)
        
        # Player controls
        controls_frame = Frame(player_bar, bg='#181818')
        controls_frame.pack(expand=True)
        
        button_frame = Frame(controls_frame, bg='#181818')
        button_frame.pack()
        
        Button(button_frame, text="⏮", font=('Arial', 20),
               bg='#181818', fg='white', bd=0,
               command=self.previous_track).pack(side=tk.LEFT, padx=10)
        
        self.play_button = Button(button_frame, text="▶", font=('Arial', 24),
                                 bg='#181818', fg='white', bd=0,
                                 command=self.toggle_playback)
        self.play_button.pack(side=tk.LEFT, padx=10)
        
        Button(button_frame, text="⏭", font=('Arial', 20),
               bg='#181818', fg='white', bd=0,
               command=self.next_track).pack(side=tk.LEFT, padx=10)
        
        # Progress bar
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Scale(controls_frame, from_=0, to=100,
                                      orient=tk.HORIZONTAL, variable=self.progress_var,
                                      length=400)
        self.progress_bar.pack(pady=5)
        
        # Volume and device controls
        right_frame = Frame(player_bar, bg='#181818', width=200)
        right_frame.pack(side=tk.RIGHT, fill=tk.Y, padx=10)
        
        self.volume_var = tk.DoubleVar(value=50)
        volume_frame = Frame(right_frame, bg='#181818')
        volume_frame.pack()
        Label(volume_frame, text="🔊", font=('Arial', 12),
              bg='#181818', fg='white').pack(side=tk.LEFT)
        ttk.Scale(volume_frame, from_=0, to=100, orient=tk.HORIZONTAL,
                 variable=self.volume_var, command=self.change_volume,
                 length=100).pack(side=tk.LEFT, padx=5)
        
        self.device_button = Button(right_frame, text="📱 Devices",
                                   font=('Arial', 10), bg='#181818', fg='white',
                                   command=self.show_devices)
        self.device_button.pack(pady=5)
    
    def show_home(self):
        """Show home screen"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        Label(self.content_frame, text="Good Evening", 
              font=('Arial', 32, 'bold'), bg='#121212', fg='white').pack(anchor='w', padx=20, pady=20)
        
        # Recently played
        if self.sp:
            try:
                recent = self.sp.current_user_recently_played(limit=6)
                if recent['items']:
                    Label(self.content_frame, text="Recently Played",
                          font=('Arial', 20, 'bold'), bg='#121212', fg='white').pack(anchor='w', padx=20, pady=10)
                    
                    recent_frame = Frame(self.content_frame, bg='#121212')
                    recent_frame.pack(fill=tk.X, padx=20)
                    
                    for i, item in enumerate(recent['items'][:6]):
                        track = item['track']
                        track_btn = Button(recent_frame, text=f"{track['name']}\n{track['artists'][0]['name']}",
                                         font=('Arial', 10), bg='#282828', fg='white',
                                         width=20, height=3, wraplength=150,
                                         command=lambda t=track: self.play_track(t['uri']))
                        track_btn.grid(row=i//3, column=i%3, padx=5, pady=5)
            except:
                pass
    
    def show_search(self):
        """Show search screen"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        Label(self.content_frame, text="Search", 
              font=('Arial', 32, 'bold'), bg='#121212', fg='white').pack(anchor='w', padx=20, pady=20)
        
        search_frame = Frame(self.content_frame, bg='#121212')
        search_frame.pack(fill=tk.X, padx=20, pady=10)
        
        self.search_entry = Entry(search_frame, font=('Arial', 14), width=40)
        self.search_entry.pack(side=tk.LEFT, padx=(0, 10))
        self.search_entry.bind('<Button-1>', lambda e: self.show_keyboard(self.search_entry))
        
        Button(search_frame, text="Search", font=('Arial', 12),
               bg='#1DB954', fg='white', command=self.perform_search).pack(side=tk.LEFT)
        
        self.search_results_frame = Frame(self.content_frame, bg='#121212')
        self.search_results_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)
    
    def perform_search(self):
        """Perform Spotify search"""
        query = self.search_entry.get()
        if not query or not self.sp:
            return
        
        for widget in self.search_results_frame.winfo_children():
            widget.destroy()
        
        try:
            results = self.sp.search(q=query, type='track,album,playlist', limit=10)
            
            # Display tracks
            if results['tracks']['items']:
                Label(self.search_results_frame, text="Tracks",
                      font=('Arial', 16, 'bold'), bg='#121212', fg='white').pack(anchor='w', pady=5)
                
                for track in results['tracks']['items'][:5]:
                    track_frame = Frame(self.search_results_frame, bg='#282828')
                    track_frame.pack(fill=tk.X, pady=2)
                    
                    Button(track_frame, text=f"{track['name']} - {track['artists'][0]['name']}",
                          font=('Arial', 11), bg='#282828', fg='white', anchor='w',
                          command=lambda t=track: self.play_track(t['uri'])).pack(side=tk.LEFT, fill=tk.X, expand=True)
                    
                    Button(track_frame, text="▶", font=('Arial', 12),
                          bg='#282828', fg='#1DB954',
                          command=lambda t=track: self.play_track(t['uri'])).pack(side=tk.RIGHT, padx=5)
            
            # Display albums
            if results['albums']['items']:
                Label(self.search_results_frame, text="Albums",
                      font=('Arial', 16, 'bold'), bg='#121212', fg='white').pack(anchor='w', pady=(10, 5))
                
                for album in results['albums']['items'][:3]:
                    Button(self.search_results_frame, text=f"{album['name']} - {album['artists'][0]['name']}",
                          font=('Arial', 11), bg='#282828', fg='white', anchor='w',
                          command=lambda a=album: self.play_album(a['uri'])).pack(fill=tk.X, pady=2)
            
            # Display playlists
            if results['playlists']['items']:
                Label(self.search_results_frame, text="Playlists",
                      font=('Arial', 16, 'bold'), bg='#121212', fg='white').pack(anchor='w', pady=(10, 5))
                
                for playlist in results['playlists']['items'][:3]:
                    Button(self.search_results_frame, text=playlist['name'],
                          font=('Arial', 11), bg='#282828', fg='white', anchor='w',
                          command=lambda p=playlist: self.play_playlist(p['uri'])).pack(fill=tk.X, pady=2)
                          
        except Exception as e:
            Label(self.search_results_frame, text=f"Search error: {str(e)}",
                  font=('Arial', 10), bg='#121212', fg='red').pack()
    
    def show_library(self):
        """Show user's library"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        Label(self.content_frame, text="Your Library", 
              font=('Arial', 32, 'bold'), bg='#121212', fg='white').pack(anchor='w', padx=20, pady=20)
        
        if self.sp:
            try:
                # Get saved tracks
                saved = self.sp.current_user_saved_tracks(limit=20)
                if saved['items']:
                    Label(self.content_frame, text="Liked Songs",
                          font=('Arial', 20, 'bold'), bg='#121212', fg='white').pack(anchor='w', padx=20, pady=10)
                    
                    tracks_frame = Frame(self.content_frame, bg='#121212')
                    tracks_frame.pack(fill=tk.BOTH, expand=True, padx=20)
                    
                    for item in saved['items']:
                        track = item['track']
                        track_frame = Frame(tracks_frame, bg='#282828')
                        track_frame.pack(fill=tk.X, pady=2)
                        
                        Button(track_frame, text=f"{track['name']} - {track['artists'][0]['name']}",
                              font=('Arial', 11), bg='#282828', fg='white', anchor='w',
                              command=lambda t=track: self.play_track(t['uri'])).pack(side=tk.LEFT, fill=tk.X, expand=True)
                        
                        Button(track_frame, text="▶", font=('Arial', 12),
                              bg='#282828', fg='#1DB954',
                              command=lambda t=track: self.play_track(t['uri'])).pack(side=tk.RIGHT, padx=5)
            except:
                pass
    
    def refresh_playlists(self):
        """Refresh user's playlists in sidebar"""
        if not self.sp:
            return
        
        for widget in self.playlist_frame.winfo_children():
            widget.destroy()
        
        try:
            playlists = self.sp.current_user_playlists(limit=10)
            for playlist in playlists['items']:
                Button(self.playlist_frame, text=playlist['name'][:25],
                      font=('Arial', 10), bg='#000000', fg='#B3B3B3', anchor='w',
                      command=lambda p=playlist: self.show_playlist(p)).pack(fill=tk.X, pady=1)
        except:
            pass
    
    def show_playlist(self, playlist):
        """Show playlist contents"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        Label(self.content_frame, text=playlist['name'], 
              font=('Arial', 32, 'bold'), bg='#121212', fg='white').pack(anchor='w', padx=20, pady=20)
        
        if self.sp:
            try:
                tracks = self.sp.playlist_tracks(playlist['id'])
                tracks_frame = Frame(self.content_frame, bg='#121212')
                tracks_frame.pack(fill=tk.BOTH, expand=True, padx=20)
                
                for item in tracks['items']:
                    if item['track']:
                        track = item['track']
                        track_frame = Frame(tracks_frame, bg='#282828')
                        track_frame.pack(fill=tk.X, pady=2)
                        
                        Button(track_frame, text=f"{track['name']} - {track['artists'][0]['name']}",
                              font=('Arial', 11), bg='#282828', fg='white', anchor='w',
                              command=lambda t=track: self.play_track(t['uri'])).pack(side=tk.LEFT, fill=tk.X, expand=True)
                        
                        Button(track_frame, text="▶", font=('Arial', 12),
                              bg='#282828', fg='#1DB954',
                              command=lambda t=track: self.play_track(t['uri'])).pack(side=tk.RIGHT, padx=5)
                
                # Play all button
                Button(self.content_frame, text="Play All", font=('Arial', 14),
                      bg='#1DB954', fg='white', width=20, height=2,
                      command=lambda: self.play_playlist(playlist['uri'])).pack(pady=10)
            except:
                pass
    
    def refresh_devices(self):
        """Refresh available Spotify devices"""
        if not self.sp:
            return
        
        try:
            devices = self.sp.devices()
            if devices['devices']:
                for device in devices['devices']:
                    if device['is_active']:
                        self.current_device = device
                        break
                else:
                    self.current_device = devices['devices'][0]
        except:
            pass
    
    def show_devices(self):
        """Show device selection dialog"""
        if not self.sp:
            return
        
        devices_window = tk.Toplevel(self.root)
        devices_window.title("Select Device")
        devices_window.geometry("400x300")
        devices_window.configure(bg='#121212')
        
        Label(devices_window, text="Available Devices", 
              font=('Arial', 16, 'bold'), bg='#121212', fg='white').pack(pady=10)
        
        try:
            devices = self.sp.devices()
            for device in devices['devices']:
                device_frame = Frame(devices_window, bg='#282828' if device['is_active'] else '#121212')
                device_frame.pack(fill=tk.X, padx=10, pady=2)
                
                Button(device_frame, text=f"{device['name']} ({device['type']})",
                      font=('Arial', 11), bg='#282828' if device['is_active'] else '#121212',
                      fg='#1DB954' if device['is_active'] else 'white',
                      command=lambda d=device: self.select_device(d, devices_window)).pack(fill=tk.X)
        except:
            Label(devices_window, text="No devices found", 
                  font=('Arial', 10), bg='#121212', fg='red').pack()
        
        devices_window.transient(self.root)
        devices_window.grab_set()
    
    def select_device(self, device, window):
        """Select a Spotify device"""
        self.current_device = device
        if self.sp:
            try:
                self.sp.transfer_playback(device['id'], force_play=False)
            except:
                pass
        window.destroy()
    
    def play_track(self, uri):
        """Play a track"""
        if not self.sp or not self.current_device:
            self.refresh_devices()
            if not self.current_device:
                return
        
        try:
            self.sp.start_playback(device_id=self.current_device['id'], uris=[uri])
            self.is_playing = True
            self.play_button.config(text="⏸")
        except Exception as e:
            print(f"Playback error: {e}")
    
    def play_album(self, uri):
        """Play an album"""
        if not self.sp or not self.current_device:
            self.refresh_devices()
            if not self.current_device:
                return
        
        try:
            self.sp.start_playback(device_id=self.current_device['id'], context_uri=uri)
            self.is_playing = True
            self.play_button.config(text="⏸")
        except:
            pass
    
    def play_playlist(self, uri):
        """Play a playlist"""
        if not self.sp or not self.current_device:
            self.refresh_devices()
            if not self.current_device:
                return
        
        try:
            self.sp.start_playback(device_id=self.current_device['id'], context_uri=uri)
            self.is_playing = True
            self.play_button.config(text="⏸")
        except:
            pass
    
    def toggle_playback(self):
        """Toggle play/pause"""
        if not self.sp:
            return
        
        try:
            if self.is_playing:
                self.sp.pause_playback()
                self.is_playing = False
                self.play_button.config(text="▶")
            else:
                self.sp.start_playback()
                self.is_playing = True
                self.play_button.config(text="⏸")
        except:
            pass
    
    def next_track(self):
        """Skip to next track"""
        if self.sp:
            try:
                self.sp.next_track()
            except:
                pass
    
    def previous_track(self):
        """Go to previous track"""
        if self.sp:
            try:
                self.sp.previous_track()
            except:
                pass
    
    def change_volume(self, value):
        """Change playback volume"""
        if self.sp:
            try:
                self.sp.volume(int(float(value)))
            except:
                pass
    
    def start_playback_monitor(self):
        """Start monitoring playback in background thread"""
        def monitor():
            while True:
                if self.sp:
                    try:
                        current = self.sp.current_playback()
                        if current and current['item']:
                            self.current_track = current['item']
                            self.is_playing = current['is_playing']
                            
                            # Update UI in main thread
                            self.root.after(0, self.update_now_playing)
                    except:
                        pass
                time.sleep(2)
        
        thread = threading.Thread(target=monitor, daemon=True)
        thread.start()
    
    def update_now_playing(self):
        """Update now playing display"""
        if self.current_track:
            self.track_name_label.config(text=self.current_track['name'][:30])
            self.artist_label.config(text=self.current_track['artists'][0]['name'][:30])
            
            # Update play button
            self.play_button.config(text="⏸" if self.is_playing else "▶")
            
            # Update album art
            if self.current_track['album']['images']:
                threading.Thread(target=self.load_album_art, 
                               args=(self.current_track['album']['images'][2]['url'],),
                               daemon=True).start()
    
    def load_album_art(self, url):
        """Load album art from URL"""
        try:
            response = requests.get(url)
            img = Image.open(BytesIO(response.content))
            img = img.resize((64, 64), Image.Resampling.LANCZOS)
            photo = ImageTk.PhotoImage(img)
            
            self.root.after(0, lambda: self.album_art_label.config(image=photo))
            self.root.after(0, lambda: setattr(self.album_art_label, 'image', photo))
        except:
            pass
    
    def update_loop(self):
        """Main update loop"""
        # Update progress bar if playing
        if self.sp and self.is_playing and self.current_track:
            try:
                current = self.sp.current_playback()
                if current:
                    progress = (current['progress_ms'] / current['item']['duration_ms']) * 100
                    self.progress_var.set(progress)
            except:
                pass
        
        # Schedule next update
        self.root.after(1000, self.update_loop)
    
    def run(self):
        """Start the application"""
        self.root.mainloop()

if __name__ == "__main__":
    # Ensure we're running as the correct user
    if os.getuid() == 0:
        print("Error: Do not run as root")
        sys.exit(1)
    
    # Create necessary directories
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    
    # Start the player
    player = SpotifyPlayer()
    player.run()