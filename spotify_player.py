#!/usr/bin/env python3
"""
Native Python Spotify Player
Replaces the web-based player with a native tkinter GUI
"""

import tkinter as tk
from tkinter import ttk, messagebox, font as tkfont
import json
import os
import subprocess
import threading
import time
from datetime import datetime
import requests
from PIL import Image, ImageTk
import io
import spotipy
from spotipy.oauth2 import SpotifyOAuth
import queue

class SpotifyPlayer:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("Spotify Kids Player")
        self.root.configure(bg="#191414")
        
        # Always start fullscreen for kiosk mode
        self.root.attributes('-fullscreen', True)
        
        # Bind F11 to toggle fullscreen (for testing)
        self.root.bind('<F11>', lambda e: self.root.attributes('-fullscreen', 
                                         not self.root.attributes('-fullscreen')))
        
        # Configuration
        self.base_dir = '/opt/spotify-terminal'
        if not os.access('/opt', os.W_OK):
            self.base_dir = os.path.expanduser('~/.spotify-terminal')
        
        self.config_dir = os.path.join(self.base_dir, 'config')
        self.data_dir = os.path.join(self.base_dir, 'data')
        self.lock_file = os.path.join(self.data_dir, 'device.lock')
        
        # Spotify client
        self.sp = None
        self.token_info = None
        self.current_track = None
        self.is_playing = False
        self.devices = []
        self.active_device = None
        
        # Queue for thread-safe GUI updates
        self.update_queue = queue.Queue()
        
        # Load configuration
        self.load_config()
        
        # Setup GUI
        self.setup_styles()
        self.create_widgets()
        
        # Initialize Spotify connection
        self.init_spotify()
        
        # Start update loops
        self.update_playback_state()
        self.process_queue()
        
        # Check for lock status
        self.check_lock_status()
    
    def setup_styles(self):
        """Setup custom styles for widgets"""
        self.style = ttk.Style()
        self.style.theme_use('clam')
        
        # Colors (Spotify theme)
        self.bg_color = "#191414"
        self.fg_color = "#FFFFFF"
        self.accent_color = "#1DB954"
        self.hover_color = "#282828"
        self.button_bg = "#1DB954"
        
        # Configure styles
        self.style.configure("Title.TLabel", 
                           background=self.bg_color, 
                           foreground=self.fg_color,
                           font=('Arial', 24, 'bold'))
        
        self.style.configure("Info.TLabel",
                           background=self.bg_color,
                           foreground=self.fg_color,
                           font=('Arial', 12))
        
        self.style.configure("Player.TFrame",
                           background=self.bg_color)
    
    def create_widgets(self):
        """Create all GUI widgets"""
        # Header
        self.create_header()
        
        # Main container
        main_container = ttk.Frame(self.root, style="Player.TFrame")
        main_container.pack(fill=tk.BOTH, expand=True)
        
        # Left sidebar
        self.create_sidebar(main_container)
        
        # Center content
        self.create_center_content(main_container)
        
        # Player controls at bottom
        self.create_player_controls()
    
    def create_header(self):
        """Create header with logo and status"""
        header = tk.Frame(self.root, bg="#282828", height=60)
        header.pack(fill=tk.X)
        header.pack_propagate(False)
        
        # Logo
        logo_frame = tk.Frame(header, bg="#282828")
        logo_frame.pack(side=tk.LEFT, padx=20, pady=10)
        
        logo_label = tk.Label(logo_frame, text="🎵 Spotify Kids", 
                             font=('Arial', 18, 'bold'),
                             bg="#282828", fg=self.accent_color)
        logo_label.pack(side=tk.LEFT)
        
        # Connection status
        status_frame = tk.Frame(header, bg="#282828")
        status_frame.pack(side=tk.RIGHT, padx=20, pady=10)
        
        self.status_dot = tk.Label(status_frame, text="●", 
                                  font=('Arial', 12),
                                  bg="#282828", fg="#FF0000")
        self.status_dot.pack(side=tk.LEFT, padx=5)
        
        self.status_label = tk.Label(status_frame, text="Connecting...",
                                    font=('Arial', 12),
                                    bg="#282828", fg=self.fg_color)
        self.status_label.pack(side=tk.LEFT)
        
        # Admin button (if not locked)
        if not os.path.exists(self.lock_file):
            admin_btn = tk.Button(header, text="Admin Panel",
                                command=self.open_admin,
                                bg=self.button_bg, fg="white",
                                font=('Arial', 10),
                                relief=tk.FLAT,
                                padx=15, pady=5)
            admin_btn.pack(side=tk.RIGHT, padx=10)
    
    def create_sidebar(self, parent):
        """Create sidebar with navigation"""
        sidebar = tk.Frame(parent, bg="#121212", width=250)
        sidebar.pack(side=tk.LEFT, fill=tk.Y)
        sidebar.pack_propagate(False)
        
        # Navigation items
        nav_items = [
            ("🏠", "Home", self.show_home),
            ("🔍", "Search", self.show_search),
            ("📚", "Library", self.show_library),
            ("📜", "Playlists", self.show_playlists),
            ("⏰", "Recent", self.show_recent)
        ]
        
        for icon, text, command in nav_items:
            btn = tk.Button(sidebar, text=f"{icon}  {text}",
                          command=command,
                          bg="#121212", fg=self.fg_color,
                          font=('Arial', 14),
                          relief=tk.FLAT,
                          anchor=tk.W,
                          padx=20, pady=15)
            btn.pack(fill=tk.X)
            
            # Hover effect
            btn.bind("<Enter>", lambda e, b=btn: b.config(bg=self.hover_color))
            btn.bind("<Leave>", lambda e, b=btn: b.config(bg="#121212"))
        
        # Playlists section
        playlist_frame = tk.Frame(sidebar, bg="#121212")
        playlist_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        tk.Label(playlist_frame, text="Your Playlists",
                font=('Arial', 12, 'bold'),
                bg="#121212", fg=self.fg_color).pack(anchor=tk.W, pady=(0, 10))
        
        # Playlist listbox with scrollbar
        list_frame = tk.Frame(playlist_frame, bg="#121212")
        list_frame.pack(fill=tk.BOTH, expand=True)
        
        scrollbar = tk.Scrollbar(list_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        self.playlist_listbox = tk.Listbox(list_frame,
                                          bg="#121212", fg=self.fg_color,
                                          font=('Arial', 11),
                                          selectbackground=self.accent_color,
                                          selectforeground="white",
                                          relief=tk.FLAT,
                                          yscrollcommand=scrollbar.set)
        self.playlist_listbox.pack(fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.playlist_listbox.yview)
        
        self.playlist_listbox.bind("<<ListboxSelect>>", self.on_playlist_select)
    
    def create_center_content(self, parent):
        """Create main content area"""
        self.content_frame = tk.Frame(parent, bg=self.bg_color)
        self.content_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=20, pady=20)
        
        # Now playing section
        self.now_playing_frame = tk.Frame(self.content_frame, bg=self.bg_color)
        self.now_playing_frame.pack(fill=tk.BOTH, expand=True)
        
        # Album art
        self.album_art_label = tk.Label(self.now_playing_frame, 
                                       bg=self.bg_color,
                                       width=300, height=300)
        self.album_art_label.pack(pady=20)
        
        # Track info
        self.track_name_label = tk.Label(self.now_playing_frame,
                                        text="No track playing",
                                        font=('Arial', 24, 'bold'),
                                        bg=self.bg_color, fg=self.fg_color)
        self.track_name_label.pack(pady=(10, 5))
        
        self.artist_name_label = tk.Label(self.now_playing_frame,
                                         text="",
                                         font=('Arial', 16),
                                         bg=self.bg_color, fg="#B3B3B3")
        self.artist_name_label.pack(pady=(0, 20))
        
        # Progress bar
        progress_frame = tk.Frame(self.now_playing_frame, bg=self.bg_color)
        progress_frame.pack(fill=tk.X, padx=50, pady=10)
        
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Scale(progress_frame, 
                                     from_=0, to=100,
                                     orient=tk.HORIZONTAL,
                                     variable=self.progress_var,
                                     command=self.on_seek)
        self.progress_bar.pack(fill=tk.X, pady=5)
        
        # Time labels
        time_frame = tk.Frame(progress_frame, bg=self.bg_color)
        time_frame.pack(fill=tk.X)
        
        self.time_current = tk.Label(time_frame, text="0:00",
                                    font=('Arial', 10),
                                    bg=self.bg_color, fg="#B3B3B3")
        self.time_current.pack(side=tk.LEFT)
        
        self.time_total = tk.Label(time_frame, text="0:00",
                                  font=('Arial', 10),
                                  bg=self.bg_color, fg="#B3B3B3")
        self.time_total.pack(side=tk.RIGHT)
    
    def create_player_controls(self):
        """Create player control buttons"""
        controls_frame = tk.Frame(self.root, bg="#282828", height=100)
        controls_frame.pack(side=tk.BOTTOM, fill=tk.X)
        controls_frame.pack_propagate(False)
        
        # Main controls
        main_controls = tk.Frame(controls_frame, bg="#282828")
        main_controls.pack(expand=True)
        
        # Control buttons
        buttons = [
            ("⟲", self.toggle_shuffle, "shuffle"),
            ("⏮", self.previous_track, "previous"),
            ("⏯", self.toggle_play, "play"),
            ("⏭", self.next_track, "next"),
            ("🔁", self.toggle_repeat, "repeat")
        ]
        
        self.control_buttons = {}
        for symbol, command, name in buttons:
            btn = tk.Button(main_controls, text=symbol,
                          command=command,
                          font=('Arial', 20 if name == "play" else 16),
                          bg="#282828", fg=self.fg_color,
                          relief=tk.FLAT,
                          width=3, height=1)
            btn.pack(side=tk.LEFT, padx=10)
            self.control_buttons[name] = btn
            
            # Hover effect
            btn.bind("<Enter>", lambda e, b=btn: b.config(bg="#383838"))
            btn.bind("<Leave>", lambda e, b=btn: b.config(bg="#282828"))
        
        # Volume control
        volume_frame = tk.Frame(controls_frame, bg="#282828")
        volume_frame.pack(side=tk.RIGHT, padx=20)
        
        tk.Label(volume_frame, text="🔊",
                font=('Arial', 14),
                bg="#282828", fg=self.fg_color).pack(side=tk.LEFT, padx=5)
        
        self.volume_var = tk.IntVar(value=50)
        volume_scale = tk.Scale(volume_frame,
                              from_=0, to=100,
                              orient=tk.HORIZONTAL,
                              variable=self.volume_var,
                              command=self.on_volume_change,
                              bg="#282828", fg=self.fg_color,
                              highlightbackground="#282828",
                              troughcolor="#404040",
                              length=100)
        volume_scale.pack(side=tk.LEFT)
        
        # Device selector
        device_frame = tk.Frame(controls_frame, bg="#282828")
        device_frame.pack(side=tk.LEFT, padx=20)
        
        tk.Label(device_frame, text="Device:",
                font=('Arial', 11),
                bg="#282828", fg=self.fg_color).pack(side=tk.LEFT, padx=5)
        
        self.device_var = tk.StringVar()
        self.device_menu = ttk.Combobox(device_frame,
                                       textvariable=self.device_var,
                                       state="readonly",
                                       width=20)
        self.device_menu.pack(side=tk.LEFT)
        self.device_menu.bind("<<ComboboxSelected>>", self.on_device_change)
    
    def load_config(self):
        """Load configuration from file"""
        config_file = os.path.join(self.config_dir, 'spotify.json')
        if os.path.exists(config_file):
            with open(config_file, 'r') as f:
                self.config = json.load(f)
        else:
            self.config = {}
        
        # Load API credentials from env file
        env_file = os.path.join(self.config_dir, 'spotify.env')
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        os.environ[key] = value
    
    def init_spotify(self):
        """Initialize Spotify connection"""
        client_id = os.getenv('SPOTIFY_CLIENT_ID')
        client_secret = os.getenv('SPOTIFY_CLIENT_SECRET')
        redirect_uri = os.getenv('SPOTIFY_REDIRECT_URI', 'http://localhost:8888/callback')
        
        if not client_id or not client_secret:
            self.show_setup_required()
            return
        
        # Setup OAuth
        scope = '''user-read-playback-state user-modify-playback-state 
                   user-read-currently-playing playlist-read-private 
                   playlist-read-collaborative user-library-read 
                   user-library-modify user-read-recently-played 
                   streaming user-read-email user-read-private'''
        
        try:
            # Try to get cached token
            cache_file = os.path.join(self.data_dir, '.spotify_cache')
            self.sp_oauth = SpotifyOAuth(
                client_id=client_id,
                client_secret=client_secret,
                redirect_uri=redirect_uri,
                scope=scope,
                cache_path=cache_file
            )
            
            self.token_info = self.sp_oauth.get_cached_token()
            
            if not self.token_info:
                # Need to authenticate
                self.authenticate_spotify()
            else:
                # Create Spotify client
                self.sp = spotipy.Spotify(auth=self.token_info['access_token'])
                self.on_connected()
        except Exception as e:
            messagebox.showerror("Error", f"Failed to initialize Spotify: {e}")
    
    def authenticate_spotify(self):
        """Open browser for Spotify authentication"""
        auth_url = self.sp_oauth.get_authorize_url()
        
        # Create auth window
        auth_window = tk.Toplevel(self.root)
        auth_window.title("Spotify Authentication")
        auth_window.geometry("500x200")
        auth_window.configure(bg=self.bg_color)
        
        tk.Label(auth_window, 
                text="Authentication Required",
                font=('Arial', 16, 'bold'),
                bg=self.bg_color, fg=self.fg_color).pack(pady=20)
        
        tk.Label(auth_window,
                text="Please login to Spotify in your browser.\nAfter authorizing, paste the redirect URL below:",
                font=('Arial', 12),
                bg=self.bg_color, fg=self.fg_color).pack(pady=10)
        
        url_entry = tk.Entry(auth_window, width=50, font=('Arial', 10))
        url_entry.pack(pady=10)
        
        def complete_auth():
            redirect_url = url_entry.get()
            try:
                code = self.sp_oauth.parse_response_code(redirect_url)
                self.token_info = self.sp_oauth.get_access_token(code)
                self.sp = spotipy.Spotify(auth=self.token_info['access_token'])
                auth_window.destroy()
                self.on_connected()
            except Exception as e:
                messagebox.showerror("Error", f"Authentication failed: {e}")
        
        tk.Button(auth_window, text="Complete Authentication",
                 command=complete_auth,
                 bg=self.button_bg, fg="white",
                 font=('Arial', 12),
                 relief=tk.FLAT,
                 padx=20, pady=10).pack(pady=10)
        
        # Open browser
        import webbrowser
        webbrowser.open(auth_url)
    
    def on_connected(self):
        """Called when successfully connected to Spotify"""
        self.status_dot.config(fg=self.accent_color)
        self.status_label.config(text="Connected")
        
        # Load playlists
        self.load_playlists()
        
        # Get devices
        self.refresh_devices()
        
        # Start playback monitoring
        self.monitor_playback()
    
    def show_setup_required(self):
        """Show message that setup is required"""
        msg_frame = tk.Frame(self.content_frame, bg=self.bg_color)
        msg_frame.place(relx=0.5, rely=0.5, anchor=tk.CENTER)
        
        tk.Label(msg_frame,
                text="Setup Required",
                font=('Arial', 24, 'bold'),
                bg=self.bg_color, fg=self.fg_color).pack(pady=10)
        
        tk.Label(msg_frame,
                text="Please configure Spotify API credentials in the Admin Panel",
                font=('Arial', 14),
                bg=self.bg_color, fg="#B3B3B3").pack(pady=10)
        
        tk.Button(msg_frame, text="Open Admin Panel",
                 command=self.open_admin,
                 bg=self.button_bg, fg="white",
                 font=('Arial', 12),
                 relief=tk.FLAT,
                 padx=20, pady=10).pack(pady=10)
    
    def load_playlists(self):
        """Load user's playlists"""
        def load():
            try:
                playlists = self.sp.current_user_playlists(limit=50)
                self.update_queue.put(("playlists", playlists['items']))
            except:
                pass
        
        threading.Thread(target=load, daemon=True).start()
    
    def refresh_devices(self):
        """Refresh available devices"""
        def refresh():
            try:
                devices = self.sp.devices()
                self.update_queue.put(("devices", devices['devices']))
            except:
                pass
        
        threading.Thread(target=refresh, daemon=True).start()
    
    def monitor_playback(self):
        """Monitor current playback state"""
        def monitor():
            while True:
                try:
                    if self.sp:
                        current = self.sp.current_playback()
                        if current:
                            self.update_queue.put(("playback", current))
                except:
                    pass
                time.sleep(1)
        
        threading.Thread(target=monitor, daemon=True).start()
    
    def update_playback_state(self):
        """Update playback state periodically"""
        # This runs in the main thread
        self.root.after(1000, self.update_playback_state)
    
    def process_queue(self):
        """Process updates from background threads"""
        try:
            while True:
                update_type, data = self.update_queue.get_nowait()
                
                if update_type == "playlists":
                    self.playlist_listbox.delete(0, tk.END)
                    for playlist in data:
                        self.playlist_listbox.insert(tk.END, playlist['name'])
                
                elif update_type == "devices":
                    self.devices = data
                    device_names = [d['name'] for d in data]
                    self.device_menu['values'] = device_names
                    
                    # Select active device
                    for device in data:
                        if device.get('is_active'):
                            self.device_var.set(device['name'])
                            self.active_device = device
                            break
                
                elif update_type == "playback":
                    self.update_now_playing(data)
                
        except queue.Empty:
            pass
        
        self.root.after(100, self.process_queue)
    
    def update_now_playing(self, playback):
        """Update now playing display"""
        if playback and playback.get('item'):
            track = playback['item']
            
            # Update track info
            self.track_name_label.config(text=track['name'])
            artists = ", ".join([a['name'] for a in track['artists']])
            self.artist_name_label.config(text=artists)
            
            # Update progress
            if track['duration_ms'] > 0:
                progress = (playback['progress_ms'] / track['duration_ms']) * 100
                self.progress_var.set(progress)
                
                # Update time labels
                current_time = self.format_time(playback['progress_ms'])
                total_time = self.format_time(track['duration_ms'])
                self.time_current.config(text=current_time)
                self.time_total.config(text=total_time)
            
            # Update play button
            self.is_playing = playback['is_playing']
            play_symbol = "⏸" if self.is_playing else "▶"
            self.control_buttons['play'].config(text=play_symbol)
            
            # Update shuffle/repeat states
            if playback.get('shuffle_state'):
                self.control_buttons['shuffle'].config(fg=self.accent_color)
            else:
                self.control_buttons['shuffle'].config(fg=self.fg_color)
            
            if playback.get('repeat_state') != 'off':
                self.control_buttons['repeat'].config(fg=self.accent_color)
            else:
                self.control_buttons['repeat'].config(fg=self.fg_color)
            
            # Load album art
            if track.get('album') and track['album'].get('images'):
                self.load_album_art(track['album']['images'][0]['url'])
    
    def load_album_art(self, url):
        """Load and display album art"""
        def load():
            try:
                response = requests.get(url)
                img = Image.open(io.BytesIO(response.content))
                img = img.resize((300, 300), Image.LANCZOS)
                photo = ImageTk.PhotoImage(img)
                
                # Update in main thread
                self.root.after(0, lambda: self.album_art_label.config(image=photo))
                self.album_art_label.image = photo  # Keep reference
            except:
                pass
        
        threading.Thread(target=load, daemon=True).start()
    
    def format_time(self, milliseconds):
        """Format milliseconds to MM:SS"""
        seconds = milliseconds // 1000
        minutes = seconds // 60
        seconds = seconds % 60
        return f"{minutes}:{seconds:02d}"
    
    # Control functions
    def toggle_play(self):
        """Toggle play/pause"""
        try:
            if self.is_playing:
                self.sp.pause_playback()
            else:
                self.sp.start_playback()
        except:
            pass
    
    def next_track(self):
        """Skip to next track"""
        try:
            self.sp.next_track()
        except:
            pass
    
    def previous_track(self):
        """Go to previous track"""
        try:
            self.sp.previous_track()
        except:
            pass
    
    def toggle_shuffle(self):
        """Toggle shuffle mode"""
        try:
            current = self.sp.current_playback()
            if current:
                new_state = not current.get('shuffle_state', False)
                self.sp.shuffle(new_state)
        except:
            pass
    
    def toggle_repeat(self):
        """Toggle repeat mode"""
        try:
            current = self.sp.current_playback()
            if current:
                repeat_state = current.get('repeat_state', 'off')
                if repeat_state == 'off':
                    self.sp.repeat('context')
                elif repeat_state == 'context':
                    self.sp.repeat('track')
                else:
                    self.sp.repeat('off')
        except:
            pass
    
    def on_seek(self, value):
        """Handle seek bar change"""
        try:
            current = self.sp.current_playback()
            if current and current.get('item'):
                position_ms = int(float(value) / 100 * current['item']['duration_ms'])
                self.sp.seek_track(position_ms)
        except:
            pass
    
    def on_volume_change(self, value):
        """Handle volume change"""
        try:
            self.sp.volume(int(value))
        except:
            pass
    
    def on_device_change(self, event):
        """Handle device selection change"""
        device_name = self.device_var.get()
        for device in self.devices:
            if device['name'] == device_name:
                try:
                    self.sp.transfer_playback(device['id'])
                    self.active_device = device
                except:
                    pass
                break
    
    def on_playlist_select(self, event):
        """Handle playlist selection"""
        selection = self.playlist_listbox.curselection()
        if selection:
            index = selection[0]
            # Get playlist from stored data
            # For now, just load playlists again to get URIs
            try:
                playlists = self.sp.current_user_playlists(limit=50)
                if index < len(playlists['items']):
                    playlist = playlists['items'][index]
                    self.sp.start_playback(context_uri=playlist['uri'])
            except:
                pass
    
    # Navigation functions
    def show_home(self):
        """Show home view"""
        # Clear content frame
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        # Recreate now playing view
        self.now_playing_frame = tk.Frame(self.content_frame, bg=self.bg_color)
        self.now_playing_frame.pack(fill=tk.BOTH, expand=True)
        
        self.album_art_label = tk.Label(self.now_playing_frame, 
                                       bg=self.bg_color,
                                       width=300, height=300)
        self.album_art_label.pack(pady=20)
        
        self.track_name_label = tk.Label(self.now_playing_frame,
                                        text="No track playing",
                                        font=('Arial', 24, 'bold'),
                                        bg=self.bg_color, fg=self.fg_color)
        self.track_name_label.pack(pady=(10, 5))
        
        self.artist_name_label = tk.Label(self.now_playing_frame,
                                         text="",
                                         font=('Arial', 16),
                                         bg=self.bg_color, fg="#B3B3B3")
        self.artist_name_label.pack(pady=(0, 20))
    
    def show_search(self):
        """Show search view"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        search_frame = tk.Frame(self.content_frame, bg=self.bg_color)
        search_frame.pack(fill=tk.BOTH, expand=True)
        
        # Search bar
        search_bar_frame = tk.Frame(search_frame, bg=self.bg_color)
        search_bar_frame.pack(fill=tk.X, pady=20)
        
        search_entry = tk.Entry(search_bar_frame,
                               font=('Arial', 14),
                               bg="#404040", fg=self.fg_color,
                               insertbackground=self.fg_color)
        search_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 10))
        
        def do_search():
            query = search_entry.get()
            if query:
                self.search_spotify(query, search_frame)
        
        tk.Button(search_bar_frame, text="Search",
                 command=do_search,
                 bg=self.button_bg, fg="white",
                 font=('Arial', 12),
                 relief=tk.FLAT,
                 padx=20, pady=8).pack(side=tk.LEFT)
        
        search_entry.bind("<Return>", lambda e: do_search())
    
    def search_spotify(self, query, parent):
        """Search Spotify and display results"""
        def search():
            try:
                results = self.sp.search(q=query, type='track,album,artist', limit=20)
                self.display_search_results(results, parent)
            except:
                pass
        
        threading.Thread(target=search, daemon=True).start()
    
    def display_search_results(self, results, parent):
        """Display search results"""
        # Clear previous results
        for widget in parent.winfo_children()[1:]:
            widget.destroy()
        
        # Results frame with scrollbar
        results_frame = tk.Frame(parent, bg=self.bg_color)
        results_frame.pack(fill=tk.BOTH, expand=True, pady=20)
        
        canvas = tk.Canvas(results_frame, bg=self.bg_color, highlightthickness=0)
        scrollbar = tk.Scrollbar(results_frame, command=canvas.yview)
        scrollable_frame = tk.Frame(canvas, bg=self.bg_color)
        
        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        # Display tracks
        if results.get('tracks') and results['tracks']['items']:
            tk.Label(scrollable_frame, text="Tracks",
                    font=('Arial', 16, 'bold'),
                    bg=self.bg_color, fg=self.fg_color).pack(anchor=tk.W, pady=10)
            
            for track in results['tracks']['items'][:10]:
                track_frame = tk.Frame(scrollable_frame, bg=self.bg_color)
                track_frame.pack(fill=tk.X, pady=5)
                
                # Track info
                info_frame = tk.Frame(track_frame, bg=self.bg_color)
                info_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
                
                tk.Label(info_frame, text=track['name'],
                        font=('Arial', 12, 'bold'),
                        bg=self.bg_color, fg=self.fg_color).pack(anchor=tk.W)
                
                artists = ", ".join([a['name'] for a in track['artists']])
                tk.Label(info_frame, text=artists,
                        font=('Arial', 10),
                        bg=self.bg_color, fg="#B3B3B3").pack(anchor=tk.W)
                
                # Play button
                play_btn = tk.Button(track_frame, text="▶",
                                   command=lambda uri=track['uri']: self.play_track(uri),
                                   bg=self.button_bg, fg="white",
                                   font=('Arial', 10),
                                   relief=tk.FLAT,
                                   padx=10, pady=5)
                play_btn.pack(side=tk.RIGHT, padx=10)
        
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
    
    def play_track(self, uri):
        """Play a specific track"""
        try:
            self.sp.start_playback(uris=[uri])
        except:
            pass
    
    def show_library(self):
        """Show user's library"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        tk.Label(self.content_frame, text="Your Library",
                font=('Arial', 24, 'bold'),
                bg=self.bg_color, fg=self.fg_color).pack(pady=20)
        
        # Load saved tracks
        def load_library():
            try:
                tracks = self.sp.current_user_saved_tracks(limit=50)
                self.display_library_tracks(tracks['items'])
            except:
                pass
        
        threading.Thread(target=load_library, daemon=True).start()
    
    def display_library_tracks(self, tracks):
        """Display library tracks"""
        # Create scrollable frame
        canvas = tk.Canvas(self.content_frame, bg=self.bg_color, highlightthickness=0)
        scrollbar = tk.Scrollbar(self.content_frame, command=canvas.yview)
        scrollable_frame = tk.Frame(canvas, bg=self.bg_color)
        
        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        for item in tracks:
            track = item['track']
            track_frame = tk.Frame(scrollable_frame, bg=self.bg_color)
            track_frame.pack(fill=tk.X, pady=5, padx=20)
            
            # Track info
            info_frame = tk.Frame(track_frame, bg=self.bg_color)
            info_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
            
            tk.Label(info_frame, text=track['name'],
                    font=('Arial', 12, 'bold'),
                    bg=self.bg_color, fg=self.fg_color).pack(anchor=tk.W)
            
            artists = ", ".join([a['name'] for a in track['artists']])
            tk.Label(info_frame, text=artists,
                    font=('Arial', 10),
                    bg=self.bg_color, fg="#B3B3B3").pack(anchor=tk.W)
            
            # Play button
            play_btn = tk.Button(track_frame, text="▶",
                               command=lambda uri=track['uri']: self.play_track(uri),
                               bg=self.button_bg, fg="white",
                               font=('Arial', 10),
                               relief=tk.FLAT,
                               padx=10, pady=5)
            play_btn.pack(side=tk.RIGHT, padx=10)
        
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
    
    def show_playlists(self):
        """Show playlists view"""
        self.show_home()  # For now, just show home
    
    def show_recent(self):
        """Show recently played"""
        for widget in self.content_frame.winfo_children():
            widget.destroy()
        
        tk.Label(self.content_frame, text="Recently Played",
                font=('Arial', 24, 'bold'),
                bg=self.bg_color, fg=self.fg_color).pack(pady=20)
        
        # Load recent tracks
        def load_recent():
            try:
                recent = self.sp.current_user_recently_played(limit=20)
                self.display_recent_tracks(recent['items'])
            except:
                pass
        
        threading.Thread(target=load_recent, daemon=True).start()
    
    def display_recent_tracks(self, items):
        """Display recently played tracks"""
        canvas = tk.Canvas(self.content_frame, bg=self.bg_color, highlightthickness=0)
        scrollbar = tk.Scrollbar(self.content_frame, command=canvas.yview)
        scrollable_frame = tk.Frame(canvas, bg=self.bg_color)
        
        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        
        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)
        
        for item in items:
            track = item['track']
            track_frame = tk.Frame(scrollable_frame, bg=self.bg_color)
            track_frame.pack(fill=tk.X, pady=5, padx=20)
            
            # Track info
            info_frame = tk.Frame(track_frame, bg=self.bg_color)
            info_frame.pack(side=tk.LEFT, fill=tk.X, expand=True)
            
            tk.Label(info_frame, text=track['name'],
                    font=('Arial', 12, 'bold'),
                    bg=self.bg_color, fg=self.fg_color).pack(anchor=tk.W)
            
            artists = ", ".join([a['name'] for a in track['artists']])
            tk.Label(info_frame, text=artists,
                    font=('Arial', 10),
                    bg=self.bg_color, fg="#B3B3B3").pack(anchor=tk.W)
            
            # Played at time
            played_at = item.get('played_at', '')
            if played_at:
                # Parse and format time
                from datetime import datetime
                dt = datetime.fromisoformat(played_at.replace('Z', '+00:00'))
                time_str = dt.strftime('%H:%M')
                tk.Label(info_frame, text=f"Played at {time_str}",
                        font=('Arial', 9),
                        bg=self.bg_color, fg="#808080").pack(anchor=tk.W)
            
            # Play button
            play_btn = tk.Button(track_frame, text="▶",
                               command=lambda uri=track['uri']: self.play_track(uri),
                               bg=self.button_bg, fg="white",
                               font=('Arial', 10),
                               relief=tk.FLAT,
                               padx=10, pady=5)
            play_btn.pack(side=tk.RIGHT, padx=10)
        
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
    
    def open_admin(self):
        """Open admin panel in browser"""
        import webbrowser
        webbrowser.open('http://localhost:5001')
    
    def check_lock_status(self):
        """Check if device is locked and adjust UI"""
        if os.path.exists(self.lock_file):
            # Force fullscreen and prevent exit
            self.root.attributes('-fullscreen', True)
            
            # Disable all exit keys
            self.root.bind('<Escape>', lambda e: None)
            self.root.bind('<Alt-F4>', lambda e: None)
            self.root.protocol('WM_DELETE_WINDOW', lambda: None)
            
            # Remove window manager decorations
            self.root.overrideredirect(True)
    
    def run(self):
        """Start the application"""
        try:
            self.root.mainloop()
        except KeyboardInterrupt:
            self.root.quit()

if __name__ == "__main__":
    # Make sure required directories exist
    base_dir = '/opt/spotify-terminal'
    if not os.access('/opt', os.W_OK):
        base_dir = os.path.expanduser('~/.spotify-terminal')
    
    os.makedirs(os.path.join(base_dir, 'config'), exist_ok=True)
    os.makedirs(os.path.join(base_dir, 'data'), exist_ok=True)
    
    # Check if Pillow is installed
    try:
        from PIL import Image, ImageTk
    except ImportError:
        print("Installing required dependencies...")
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'pillow', 'spotipy', 'requests'])
        from PIL import Image, ImageTk
    
    # Run the player
    app = SpotifyPlayer()
    app.run()