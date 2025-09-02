const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const WebSocket = require('ws');
const SpotifyWebApi = require('spotify-web-api-node');
const session = require('express-session');

const app = express();
const PORT = process.env.PORT || 5000;

// Configuration
const CONFIG_DIR = process.env.SPOTIFY_CONFIG_DIR || '/opt/spotify-kids/config';
const SPOTIFY_CONFIG_FILE = path.join(CONFIG_DIR, 'spotify_config.json');
const PARENTAL_CONFIG_FILE = path.join(CONFIG_DIR, 'parental_controls.json');
const PLAYER_CONFIG_FILE = path.join(CONFIG_DIR, 'player_config.json');
const TOKEN_CACHE_FILE = path.join(CONFIG_DIR, 'cache', 'token.cache');

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'client')));
app.use(session({
    secret: process.env.SESSION_SECRET || 'spotify-kids-player-secret',
    resave: false,
    saveUninitialized: true
}));

// Load configurations
function loadConfig(filePath, defaults = {}) {
    try {
        if (fs.existsSync(filePath)) {
            return JSON.parse(fs.readFileSync(filePath, 'utf8'));
        }
    } catch (error) {
        console.error(`Error loading config from ${filePath}:`, error);
    }
    return defaults;
}

function saveConfig(filePath, config) {
    try {
        fs.writeFileSync(filePath, JSON.stringify(config, null, 2));
        // Set group-readable permissions
        fs.chmodSync(filePath, 0o664);
    } catch (error) {
        console.error(`Error saving config to ${filePath}:`, error);
    }
}

// Load configurations
const spotifyConfig = loadConfig(SPOTIFY_CONFIG_FILE);
const parentalConfig = loadConfig(PARENTAL_CONFIG_FILE, {
    volume_limit: 85,
    allowed_playlists: [],
    explicit_filter: true,
    max_play_time: 120, // minutes
    blocked_artists: [],
    blocked_songs: []
});

// Player configuration (theme, UI settings, etc.)
const playerConfig = loadConfig(PLAYER_CONFIG_FILE, {
    theme: 'spotify-dark',
    show_visualizer: false,
    show_lyrics: false,
    auto_play_on_start: false,
    crossfade: 0,
    normalize_volume: true,
    hide_cursor_timeout: 0, // 0 = always hidden for touchscreen
    enable_gestures: true,
    large_touch_targets: true
});

// Initialize Spotify client
let spotifyApi = null;

function initSpotifyClient() {
    if (!spotifyConfig.client_id || !spotifyConfig.client_secret) {
        console.error('Spotify credentials not configured');
        return false;
    }

    spotifyApi = new SpotifyWebApi({
        clientId: spotifyConfig.client_id,
        clientSecret: spotifyConfig.client_secret,
        redirectUri: spotifyConfig.redirect_uri || 'https://192.168.1.164/callback'
    });

    // Load cached token
    if (fs.existsSync(TOKEN_CACHE_FILE)) {
        try {
            const tokenData = JSON.parse(fs.readFileSync(TOKEN_CACHE_FILE, 'utf8'));
            spotifyApi.setAccessToken(tokenData.access_token);
            spotifyApi.setRefreshToken(tokenData.refresh_token);
            
            // Check if token needs refresh
            if (tokenData.expires_at && Date.now() > tokenData.expires_at) {
                refreshAccessToken();
            }
            
            return true;
        } catch (error) {
            console.error('Error loading token cache:', error);
        }
    }
    
    console.error('No valid token found. Please authenticate through admin panel first.');
    return false;
}

async function refreshAccessToken() {
    try {
        const data = await spotifyApi.refreshAccessToken();
        spotifyApi.setAccessToken(data.body.access_token);
        
        // Save new token
        const tokenData = {
            access_token: data.body.access_token,
            refresh_token: spotifyApi.getRefreshToken(),
            expires_at: Date.now() + (data.body.expires_in * 1000)
        };
        
        fs.writeFileSync(TOKEN_CACHE_FILE, JSON.stringify(tokenData));
        console.log('Access token refreshed successfully');
    } catch (error) {
        console.error('Error refreshing access token:', error);
    }
}

// WebSocket for real-time updates
const wss = new WebSocket.Server({ noServer: true });
const clients = new Set();

wss.on('connection', (ws) => {
    clients.add(ws);
    
    ws.on('close', () => {
        clients.delete(ws);
    });
    
    // Send initial configuration
    ws.send(JSON.stringify({
        type: 'config',
        data: {
            parental: parentalConfig,
            player: playerConfig
        }
    }));
});

// Broadcast playback state to all clients
let playbackState = {};
let updateInterval = null;

async function updatePlaybackState() {
    if (!spotifyApi) return;
    
    try {
        const data = await spotifyApi.getMyCurrentPlaybackState();
        
        if (data.body && data.body.item) {
            playbackState = {
                is_playing: data.body.is_playing,
                item: data.body.item,
                progress_ms: data.body.progress_ms,
                device: data.body.device,
                shuffle_state: data.body.shuffle_state,
                repeat_state: data.body.repeat_state,
                context: data.body.context
            };
            
            // Check if track is liked
            if (data.body.item && data.body.item.id) {
                const liked = await spotifyApi.containsMySavedTracks([data.body.item.id]);
                playbackState.is_liked = liked.body[0];
            }
            
            // Broadcast to all connected clients
            const message = JSON.stringify({
                type: 'playback',
                data: playbackState
            });
            
            clients.forEach(client => {
                if (client.readyState === WebSocket.OPEN) {
                    client.send(message);
                }
            });
        }
    } catch (error) {
        if (error.statusCode === 401) {
            await refreshAccessToken();
        } else {
            console.error('Error updating playback state:', error);
        }
    }
}

// API Routes

app.get('/api/token', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        // Get the current access token
        let accessToken = spotifyApi.getAccessToken();
        if (!accessToken) {
            // Try to refresh if no token
            await refreshAccessToken();
            accessToken = spotifyApi.getAccessToken();
        }
        res.json({ access_token: accessToken });
    } catch (error) {
        console.error('Error getting token:', error);
        res.status(500).json({ error: 'Failed to get token' });
    }
});

app.get('/api/config', (req, res) => {
    res.json({
        parental: parentalConfig,
        player: playerConfig,
        features: {
            has_spotify: !!spotifyApi,
            theme_options: ['spotify-dark', 'spotify-light', 'kids-colorful', 'minimal'],
            max_volume: parentalConfig.volume_limit
        }
    });
});

app.post('/api/config/player', (req, res) => {
    Object.assign(playerConfig, req.body);
    saveConfig(PLAYER_CONFIG_FILE, playerConfig);
    
    // Broadcast config change
    const message = JSON.stringify({
        type: 'config_update',
        data: { player: playerConfig }
    });
    
    clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(message);
        }
    });
    
    res.json({ success: true });
});

app.get('/api/playlists', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        // Get user playlists
        const data = await spotifyApi.getUserPlaylists({ limit: 50 });
        let playlists = data.body.items || [];
        
        // Add special Spotify playlists
        const specialPlaylists = [
            {
                id: 'liked-songs',
                name: 'Liked Songs',
                uri: 'spotify:collection:tracks',
                type: 'collection',
                owner: { display_name: 'You' },
                images: [{ url: 'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDgiIGhlaWdodD0iNDgiIHZpZXdCb3g9IjAgMCA0OCA0OCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHJlY3Qgd2lkdGg9IjQ4IiBoZWlnaHQ9IjQ4IiBmaWxsPSJsaW5lYXItZ3JhZGllbnRoMTM1ZGVnLCAjNDUwYWY1LCAjYzRlZWZmKSIvPgo8cGF0aCBkPSJNMjQgMzZDMjQgMzYgMzcgMjcuNSAzNyAxOC41QzM3IDEzLjUgMzMgMTAgMjguNSAxMEMyNi41IDEwIDI0LjUgMTEgMjQgMTJDMjMuNSAxMSAyMS41IDEwIDE5LjUgMTBDMTUgMTAgMTEgMTMuNSAxMSAxOC41QzExIDI3LjUgMjQgMzYgMjQgMzZaIiBmaWxsPSJ3aGl0ZSIvPgo8L3N2Zz4=' }]
            },
            {
                id: 'spotify-dj',
                name: 'DJ',
                uri: 'spotify:playlist:37i9dQZF1EYkqdzj48dyYq',  // DJ playlist URI
                type: 'playlist',
                owner: { display_name: 'Spotify' },
                images: [{ 
                    url: 'https://champlaincrossover.org/wp-content/uploads/2023/03/Screen-Shot-2023-03-30-at-3.31.46-PM-898x900.png'
                }],
                description: 'Your personal AI DJ'
            }
        ];
        
        // Also check user's playlists for any Spotify-made playlists like Daily Mixes
        const spotifyMadePlaylists = playlists.filter(p => 
            p.owner?.id === 'spotify' && 
            (p.name.includes('Daily Mix') || p.name.includes('Discover') || p.name.includes('Release Radar'))
        );
        
        // Organize playlists: special playlists first, then Spotify-made, then user playlists
        const userPlaylists = playlists.filter(p => 
            p.owner?.id !== 'spotify' && p.type !== 'collection'
        );
        
        playlists = [...specialPlaylists, ...spotifyMadePlaylists, ...userPlaylists];
        
        // Filter by parental controls if configured
        if (parentalConfig.allowed_playlists && parentalConfig.allowed_playlists.length > 0) {
            playlists = playlists.filter(p => 
                parentalConfig.allowed_playlists.includes(p.uri) ||
                p.type === 'collection' // Always allow Liked Songs
            );
        }
        
        res.json({ playlists });
    } catch (error) {
        console.error('Error getting playlists:', error);
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/playlist/:id', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const playlistId = req.params.id;
        
        // Handle special playlists
        if (playlistId === 'liked-songs') {
            // Get liked songs
            const tracks = await spotifyApi.getMySavedTracks({ limit: 50 });
            const formattedTracks = tracks.body.items.map(item => ({
                id: item.track.id,
                uri: item.track.uri,
                name: item.track.name,
                artists: item.track.artists.map(a => a.name).join(', '),
                album: item.track.album.name,
                duration_ms: item.track.duration_ms,
                explicit: item.track.explicit,
                image: item.track.album.images?.[0]?.url
            }));
            
            res.json({
                id: 'liked-songs',
                name: 'Liked Songs',
                tracks: formattedTracks,
                total: tracks.body.total
            });
        } else if (playlistId === 'spotify-dj') {
            // For DJ, we'll return it as a special playlist that can be played directly
            // DJ doesn't have tracks we can list, it's an AI-generated stream
            res.json({
                id: 'spotify-dj',
                name: 'DJ',
                image: 'https://champlaincrossover.org/wp-content/uploads/2023/03/Screen-Shot-2023-03-30-at-3.31.46-PM-898x900.png',
                tracks: [{
                    id: 'dj-stream',
                    uri: 'spotify:playlist:37i9dQZF1EYkqdzj48dyYq',
                    name: 'Start DJ Session',
                    artists: 'AI-powered music and commentary',
                    album: 'Personalized for you',
                    duration_ms: 0,
                    explicit: false,
                    image: 'https://champlaincrossover.org/wp-content/uploads/2023/03/Screen-Shot-2023-03-30-at-3.31.46-PM-898x900.png'
                }],
                total: 1,
                description: 'Your personal AI DJ - tap to start listening',
                isDJ: true
            });
        } else {
            // Get regular playlist tracks
            const playlist = await spotifyApi.getPlaylist(playlistId);
            const formattedTracks = playlist.body.tracks.items
                .filter(item => item.track) // Filter out null tracks
                .map(item => ({
                    id: item.track.id,
                    uri: item.track.uri,
                    name: item.track.name,
                    artists: item.track.artists.map(a => a.name).join(', '),
                    album: item.track.album.name,
                    duration_ms: item.track.duration_ms,
                    explicit: item.track.explicit,
                    image: item.track.album.images?.[0]?.url
                }));
            
            res.json({
                id: playlist.body.id,
                name: playlist.body.name,
                description: playlist.body.description,
                image: playlist.body.images?.[0]?.url,
                tracks: formattedTracks,
                total: playlist.body.tracks.total
            });
        }
    } catch (error) {
        console.error('Error getting playlist tracks:', error);
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/playback', async (req, res) => {
    res.json(playbackState);
});

// Get available devices
app.get('/api/devices', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const devices = await spotifyApi.getMyDevices();
        res.json({ devices: devices.body.devices });
    } catch (error) {
        console.error('Error getting devices:', error);
        res.json({ devices: [] });
    }
});

app.post('/api/play', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { context_uri, uris, offset } = req.body;
        const options = {};
        
        // Get available devices
        const devices = await spotifyApi.getMyDevices();
        if (devices.body.devices.length === 0) {
            return res.status(404).json({ error: 'No Spotify devices available. Please open Spotify on a device.' });
        }
        
        // Find active device or use first available
        let device = devices.body.devices.find(d => d.is_active);
        if (!device) {
            device = devices.body.devices[0];
            // Transfer playback to this device
            await spotifyApi.transferMyPlayback([device.id]);
            await new Promise(resolve => setTimeout(resolve, 500)); // Small delay for transfer
        }
        
        options.device_id = device.id;
        
        // Handle Liked Songs special case
        if (context_uri === 'spotify:collection:tracks') {
            // Get liked songs and play them
            const tracks = await spotifyApi.getMySavedTracks({ limit: 50 });
            if (tracks.body.items.length > 0) {
                options.uris = tracks.body.items.map(item => item.track.uri);
            }
        } else if (context_uri) {
            options.context_uri = context_uri;
        }
        
        if (uris) options.uris = uris;
        if (offset !== undefined) options.offset = { position: offset };
        
        await spotifyApi.play(options);
        res.json({ success: true });
    } catch (error) {
        console.error('Error playing:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/pause', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        await spotifyApi.pause();
        res.json({ success: true });
    } catch (error) {
        console.error('Error pausing:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/next', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        await spotifyApi.skipToNext();
        res.json({ success: true });
    } catch (error) {
        console.error('Error skipping:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/previous', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        await spotifyApi.skipToPrevious();
        res.json({ success: true });
    } catch (error) {
        console.error('Error going back:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/shuffle', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { state } = req.body;
        // Accept boolean or string values
        const shuffleOn = state === true || state === 'on' || state === 'smart';
        await spotifyApi.setShuffle(shuffleOn);
        res.json({ success: true });
    } catch (error) {
        console.error('Error setting shuffle:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/repeat', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { state } = req.body; // off, context, track
        await spotifyApi.setRepeat(state);
        res.json({ success: true });
    } catch (error) {
        console.error('Error setting repeat:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/volume', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        let { volume } = req.body;
        
        // Apply parental volume limit
        volume = Math.min(volume, parentalConfig.volume_limit);
        
        await spotifyApi.setVolume(volume);
        res.json({ success: true, volume });
    } catch (error) {
        console.error('Error setting volume:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/seek', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { position_ms } = req.body;
        await spotifyApi.seek(position_ms);
        res.json({ success: true });
    } catch (error) {
        console.error('Error seeking:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/like', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { track_id, liked } = req.body;
        
        if (liked) {
            await spotifyApi.addToMySavedTracks([track_id]);
        } else {
            await spotifyApi.removeFromMySavedTracks([track_id]);
        }
        
        res.json({ success: true });
    } catch (error) {
        console.error('Error toggling like:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/download/playlist/:id', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const playlistId = req.params.id;
        const downloadDir = path.join(__dirname, 'downloads');
        
        // Create downloads directory if it doesn't exist
        if (!fs.existsSync(downloadDir)) {
            fs.mkdirSync(downloadDir, { recursive: true });
        }
        
        // Get playlist details
        let playlistData;
        
        if (playlistId === 'liked-songs') {
            // Get liked songs
            const tracks = await spotifyApi.getMySavedTracks({ limit: 50 });
            playlistData = {
                id: 'liked-songs',
                name: 'Liked Songs',
                tracks: tracks.body.items.map(item => ({
                    id: item.track.id,
                    uri: item.track.uri,
                    name: item.track.name,
                    artists: item.track.artists.map(a => a.name).join(', '),
                    album: item.track.album.name,
                    duration_ms: item.track.duration_ms,
                    image: item.track.album.images?.[0]?.url
                })),
                total: tracks.body.total,
                downloaded_at: new Date().toISOString()
            };
        } else {
            // Get regular playlist
            const playlist = await spotifyApi.getPlaylist(playlistId);
            playlistData = {
                id: playlist.body.id,
                name: playlist.body.name,
                description: playlist.body.description,
                image: playlist.body.images?.[0]?.url,
                tracks: playlist.body.tracks.items
                    .filter(item => item.track)
                    .map(item => ({
                        id: item.track.id,
                        uri: item.track.uri,
                        name: item.track.name,
                        artists: item.track.artists.map(a => a.name).join(', '),
                        album: item.track.album.name,
                        duration_ms: item.track.duration_ms,
                        image: item.track.album.images?.[0]?.url
                    })),
                total: playlist.body.tracks.total,
                downloaded_at: new Date().toISOString()
            };
        }
        
        // Save playlist metadata to file
        const fileName = `${playlistId}.json`;
        const filePath = path.join(downloadDir, fileName);
        fs.writeFileSync(filePath, JSON.stringify(playlistData, null, 2));
        
        // Store in parental config for offline access
        if (!parentalConfig.downloaded_playlists) {
            parentalConfig.downloaded_playlists = [];
        }
        
        // Update or add playlist in downloaded list
        const existingIndex = parentalConfig.downloaded_playlists.findIndex(p => p.id === playlistId);
        if (existingIndex >= 0) {
            parentalConfig.downloaded_playlists[existingIndex] = {
                id: playlistId,
                name: playlistData.name,
                track_count: playlistData.tracks.length,
                downloaded_at: playlistData.downloaded_at
            };
        } else {
            parentalConfig.downloaded_playlists.push({
                id: playlistId,
                name: playlistData.name,
                track_count: playlistData.tracks.length,
                downloaded_at: playlistData.downloaded_at
            });
        }
        
        saveConfig(PARENTAL_CONFIG_FILE, parentalConfig);
        
        res.json({ 
            success: true, 
            message: `Downloaded ${playlistData.tracks.length} tracks from "${playlistData.name}"`,
            playlist_id: playlistId
        });
    } catch (error) {
        console.error('Error downloading playlist:', error);
        res.status(500).json({ error: error.message });
    }
});

// Play a specific track URI
app.post('/api/play-uri', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { uri } = req.body;
        
        // Get available devices
        const devices = await spotifyApi.getMyDevices();
        if (devices.body.devices.length === 0) {
            return res.status(404).json({ error: 'No Spotify devices available. Please open Spotify on a device.' });
        }
        
        // Find active device or use first available
        let device = devices.body.devices.find(d => d.is_active);
        if (!device) {
            device = devices.body.devices[0];
            await spotifyApi.transferMyPlayback([device.id]);
            await new Promise(resolve => setTimeout(resolve, 500));
        }
        
        await spotifyApi.play({
            device_id: device.id,
            uris: [uri]
        });
        
        res.json({ success: true });
    } catch (error) {
        console.error('Error playing URI:', error);
        res.status(500).json({ error: error.message });
    }
});

// Play a playlist
app.post('/api/play-playlist', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { uri } = req.body;
        
        // Get available devices
        const devices = await spotifyApi.getMyDevices();
        if (devices.body.devices.length === 0) {
            return res.status(404).json({ error: 'No Spotify devices available. Please open Spotify on a device.' });
        }
        
        // Find active device or use first available
        let device = devices.body.devices.find(d => d.is_active);
        if (!device) {
            device = devices.body.devices[0];
            await spotifyApi.transferMyPlayback([device.id]);
            await new Promise(resolve => setTimeout(resolve, 500));
        }
        
        // Handle special playlists
        if (uri === 'spotify:collection:tracks') {
            // Liked Songs
            const tracks = await spotifyApi.getMySavedTracks({ limit: 50 });
            if (tracks.body.items.length > 0) {
                await spotifyApi.play({
                    device_id: device.id,
                    uris: tracks.body.items.map(item => item.track.uri)
                });
            }
        } else {
            await spotifyApi.play({
                device_id: device.id,
                context_uri: uri
            });
        }
        
        res.json({ success: true });
    } catch (error) {
        console.error('Error playing playlist:', error);
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/search', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        const { query, types = ['track', 'album', 'artist', 'playlist'] } = req.body;
        const data = await spotifyApi.search(query, types, { limit: 20 });
        
        const results = [];
        
        // Format results
        if (data.body.tracks) {
            data.body.tracks.items.forEach(track => {
                // Apply parental filters
                if (parentalConfig.explicit_filter && track.explicit) return;
                if (parentalConfig.blocked_songs.includes(track.id)) return;
                if (track.artists.some(a => parentalConfig.blocked_artists.includes(a.id))) return;
                
                results.push({
                    type: 'track',
                    id: track.id,
                    uri: track.uri,
                    name: track.name,
                    artist: track.artists.map(a => a.name).join(', '),
                    image: track.album.images[0]?.url
                });
            });
        }
        
        if (data.body.albums) {
            data.body.albums.items.forEach(album => {
                results.push({
                    type: 'album',
                    id: album.id,
                    uri: album.uri,
                    name: album.name,
                    artist: album.artists.map(a => a.name).join(', '),
                    image: album.images[0]?.url
                });
            });
        }
        
        if (data.body.artists) {
            data.body.artists.items.forEach(artist => {
                if (parentalConfig.blocked_artists.includes(artist.id)) return;
                
                results.push({
                    type: 'artist',
                    id: artist.id,
                    uri: artist.uri,
                    name: artist.name,
                    followers: artist.followers.total,
                    image: artist.images[0]?.url
                });
            });
        }
        
        if (data.body.playlists) {
            data.body.playlists.items.forEach(playlist => {
                results.push({
                    type: 'playlist',
                    id: playlist.id,
                    uri: playlist.uri,
                    name: playlist.name,
                    owner: playlist.owner.display_name,
                    image: playlist.images[0]?.url
                });
            });
        }
        
        res.json({ results });
    } catch (error) {
        console.error('Error searching:', error);
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/recommendations', async (req, res) => {
    if (!spotifyApi) {
        return res.status(503).json({ error: 'Spotify not connected' });
    }
    
    try {
        // Get user's top tracks for seeds
        const topTracks = await spotifyApi.getMyTopTracks({ limit: 5 });
        const seedTracks = topTracks.body.items.map(t => t.id);
        
        const recommendations = await spotifyApi.getRecommendations({
            seed_tracks: seedTracks,
            limit: 50,
            target_energy: 0.7,
            target_valence: 0.8 // More positive/happy music for kids
        });
        
        res.json({ tracks: recommendations.body.tracks });
    } catch (error) {
        console.error('Error getting recommendations:', error);
        res.status(500).json({ error: error.message });
    }
});

// Serve Spotify clone interface
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'client', 'index.html'));
});

// HTTP server
const server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`Spotify Kids Player running on port ${PORT}`);
    
    // Initialize Spotify client
    if (initSpotifyClient()) {
        console.log('Spotify client initialized');
        
        // Start playback state updates
        updateInterval = setInterval(updatePlaybackState, 1000);
    } else {
        console.log('Failed to initialize Spotify client');
    }
});

// WebSocket upgrade
server.on('upgrade', (request, socket, head) => {
    wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
    });
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('SIGTERM received, shutting down gracefully');
    
    if (updateInterval) {
        clearInterval(updateInterval);
    }
    
    clients.forEach(client => {
        client.close();
    });
    
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});