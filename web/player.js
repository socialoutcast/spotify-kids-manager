// Spotify Web Player Interface
class SpotifyPlayer {
    constructor() {
        this.accessToken = null;
        this.deviceId = null;
        this.player = null;
        this.currentTrack = null;
        this.isPlaying = false;
        this.shuffle = false;
        this.repeat = 'off'; // off, context, track
        this.volume = 0.7;
        this.position = 0;
        this.duration = 0;
        
        this.init();
    }

    async init() {
        // Check for saved credentials
        await this.checkAuth();
        
        // Initialize UI event listeners
        this.setupEventListeners();
        
        // Connect to Spotify Connect device (raspotify/spotifyd)
        this.connectToDevice();
        
        // Load initial content
        this.loadHome();
        
        // Start position update timer
        setInterval(() => this.updateProgress(), 1000);
    }

    async checkAuth() {
        try {
            const response = await fetch('/api/spotify/token');
            const data = await response.json();
            
            if (data.access_token) {
                // OAuth mode - we have tokens
                this.accessToken = data.access_token;
                document.getElementById('username').textContent = data.username || 'User';
                document.getElementById('connectionText').textContent = 'Connected';
                
                // Refresh token before expiry
                setTimeout(() => this.refreshToken(), (data.expires_in - 60) * 1000);
            } else if (data.username && data.needs_oauth) {
                // Username/password mode - no tokens needed for raspotify/spotifyd
                // The backend handles auth directly
                this.accessToken = 'backend-auth'; // Dummy token to indicate auth is handled by backend
                document.getElementById('username').textContent = data.username;
                document.getElementById('connectionText').textContent = 'Connected (Direct)';
                
                // Don't need to refresh for direct backend auth
            } else {
                this.showAuthPrompt();
            }
        } catch (error) {
            console.error('Auth check failed:', error);
            document.getElementById('connectionText').textContent = 'Offline';
            // Still try to load content even if auth check fails
            // Backend might handle auth directly
        }
    }

    async refreshToken() {
        try {
            const response = await fetch('/api/spotify/refresh', { method: 'POST' });
            const data = await response.json();
            
            if (data.access_token) {
                this.accessToken = data.access_token;
                setTimeout(() => this.refreshToken(), (data.expires_in - 60) * 1000);
            }
        } catch (error) {
            console.error('Token refresh failed:', error);
        }
    }

    async connectToDevice() {
        // Connect to local Spotify Connect device
        try {
            const response = await fetch('https://api.spotify.com/v1/me/player/devices', {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const data = await response.json();
            const localDevice = data.devices.find(d => d.name === window.location.hostname);
            
            if (localDevice) {
                this.deviceId = localDevice.id;
                console.log('Connected to device:', localDevice.name);
            }
        } catch (error) {
            console.error('Device connection failed:', error);
        }
    }

    setupEventListeners() {
        // Navigation
        document.querySelectorAll('.nav-item').forEach(item => {
            item.addEventListener('click', (e) => {
                document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
                e.currentTarget.classList.add('active');
                
                const view = e.currentTarget.dataset.view;
                this.switchView(view);
            });
        });

        // Search input focus (show keyboard)
        const searchInput = document.getElementById('searchInput');
        searchInput.addEventListener('focus', () => {
            if ('ontouchstart' in window) {
                // On touch devices, trigger system keyboard
                // The browser will handle this automatically
                // Or we can show our custom keyboard
                this.showTouchKeyboard();
            }
        });

        searchInput.addEventListener('blur', () => {
            this.hideTouchKeyboard();
        });

        searchInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.performSearch();
            }
        });

        // Progress bar interaction
        const progressBar = document.getElementById('progressBar');
        progressBar.addEventListener('click', (e) => {
            const rect = progressBar.getBoundingClientRect();
            const percent = (e.clientX - rect.left) / rect.width;
            this.seek(percent * this.duration);
        });

        // Volume control
        const volumeSlider = document.getElementById('volumeSlider');
        volumeSlider.addEventListener('click', (e) => {
            const rect = volumeSlider.getBoundingClientRect();
            const percent = (e.clientX - rect.left) / rect.width;
            this.setVolume(percent);
        });
    }

    switchView(view) {
        const searchContainer = document.getElementById('searchContainer');
        searchContainer.classList.toggle('active', view === 'search');
        
        switch(view) {
            case 'home':
                this.loadHome();
                break;
            case 'search':
                document.getElementById('searchInput').focus();
                break;
            case 'liked':
                this.loadLikedSongs();
                break;
            default:
                if (view.startsWith('playlist:')) {
                    this.loadPlaylist(view.substring(9));
                }
        }
    }

    async loadHome() {
        const content = document.getElementById('contentArea');
        content.innerHTML = '<h2 style="color: white; margin-bottom: 20px;">Recently Played</h2>';
        
        try {
            const response = await fetch('https://api.spotify.com/v1/me/player/recently-played?limit=20', {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const data = await response.json();
            const grid = document.createElement('div');
            grid.className = 'content-grid';
            
            data.items.forEach(item => {
                const card = this.createCard(item.track);
                grid.appendChild(card);
            });
            
            content.appendChild(grid);
        } catch (error) {
            content.innerHTML = '<p style="color: white;">Unable to load recent tracks</p>';
        }
        
        // Also load playlists in sidebar
        this.loadPlaylists();
    }

    async loadPlaylists() {
        const playlistsList = document.getElementById('playlistsList');
        
        try {
            const response = await fetch('https://api.spotify.com/v1/me/playlists?limit=50', {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const data = await response.json();
            playlistsList.innerHTML = '';
            
            data.items.forEach(playlist => {
                const item = document.createElement('a');
                item.className = 'playlist-item';
                item.textContent = playlist.name;
                item.href = '#';
                item.onclick = (e) => {
                    e.preventDefault();
                    this.loadPlaylist(playlist.id);
                };
                playlistsList.appendChild(item);
            });
        } catch (error) {
            console.error('Failed to load playlists:', error);
        }
    }

    async loadPlaylist(playlistId) {
        const content = document.getElementById('contentArea');
        
        try {
            const response = await fetch(`https://api.spotify.com/v1/playlists/${playlistId}`, {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const playlist = await response.json();
            
            content.innerHTML = `
                <div style="color: white; margin-bottom: 30px;">
                    <h1>${playlist.name}</h1>
                    <p style="opacity: 0.7;">${playlist.description || ''}</p>
                    <button class="search-btn" style="margin-top: 15px;" onclick="player.playPlaylist('${playlistId}')">
                        Play All
                    </button>
                </div>
            `;
            
            const grid = document.createElement('div');
            grid.className = 'content-grid';
            
            playlist.tracks.items.forEach(item => {
                if (item.track) {
                    const card = this.createCard(item.track);
                    grid.appendChild(card);
                }
            });
            
            content.appendChild(grid);
        } catch (error) {
            content.innerHTML = '<p style="color: white;">Unable to load playlist</p>';
        }
    }

    async loadLikedSongs() {
        const content = document.getElementById('contentArea');
        content.innerHTML = '<h2 style="color: white; margin-bottom: 20px;">Liked Songs</h2>';
        
        try {
            const response = await fetch('https://api.spotify.com/v1/me/tracks?limit=50', {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const data = await response.json();
            const grid = document.createElement('div');
            grid.className = 'content-grid';
            
            data.items.forEach(item => {
                const card = this.createCard(item.track);
                grid.appendChild(card);
            });
            
            content.appendChild(grid);
        } catch (error) {
            content.innerHTML = '<p style="color: white;">Unable to load liked songs</p>';
        }
    }

    async performSearch() {
        const query = document.getElementById('searchInput').value;
        if (!query) return;
        
        const content = document.getElementById('contentArea');
        content.innerHTML = '<p style="color: white;">Searching...</p>';
        
        try {
            const response = await fetch(`https://api.spotify.com/v1/search?q=${encodeURIComponent(query)}&type=track,album,artist&limit=20`, {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const data = await response.json();
            
            content.innerHTML = '';
            
            // Show tracks
            if (data.tracks && data.tracks.items.length > 0) {
                content.innerHTML += '<h3 style="color: white; margin: 20px 0 10px;">Songs</h3>';
                const tracksGrid = document.createElement('div');
                tracksGrid.className = 'content-grid';
                
                data.tracks.items.forEach(track => {
                    const card = this.createCard(track);
                    tracksGrid.appendChild(card);
                });
                
                content.appendChild(tracksGrid);
            }
            
            // Show albums
            if (data.albums && data.albums.items.length > 0) {
                content.innerHTML += '<h3 style="color: white; margin: 20px 0 10px;">Albums</h3>';
                const albumsGrid = document.createElement('div');
                albumsGrid.className = 'content-grid';
                
                data.albums.items.forEach(album => {
                    const card = this.createAlbumCard(album);
                    albumsGrid.appendChild(card);
                });
                
                content.appendChild(albumsGrid);
            }
            
            // Show artists
            if (data.artists && data.artists.items.length > 0) {
                content.innerHTML += '<h3 style="color: white; margin: 20px 0 10px;">Artists</h3>';
                const artistsGrid = document.createElement('div');
                artistsGrid.className = 'content-grid';
                
                data.artists.items.forEach(artist => {
                    const card = this.createArtistCard(artist);
                    artistsGrid.appendChild(card);
                });
                
                content.appendChild(artistsGrid);
            }
        } catch (error) {
            content.innerHTML = '<p style="color: white;">Search failed</p>';
        }
    }

    createCard(track) {
        const card = document.createElement('div');
        card.className = 'card';
        card.onclick = () => this.playTrack(track.uri);
        
        const img = document.createElement('img');
        img.className = 'card-image';
        img.src = track.album.images[0]?.url || 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"%3E%3Crect fill="%23333" width="100" height="100"/%3E%3C/svg%3E';
        img.alt = track.album.name;
        
        const title = document.createElement('div');
        title.className = 'card-title';
        title.textContent = track.name;
        
        const subtitle = document.createElement('div');
        subtitle.className = 'card-subtitle';
        subtitle.textContent = track.artists.map(a => a.name).join(', ');
        
        card.appendChild(img);
        card.appendChild(title);
        card.appendChild(subtitle);
        
        return card;
    }

    createAlbumCard(album) {
        const card = document.createElement('div');
        card.className = 'card';
        card.onclick = () => this.playAlbum(album.uri);
        
        const img = document.createElement('img');
        img.className = 'card-image';
        img.src = album.images[0]?.url || 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"%3E%3Crect fill="%23333" width="100" height="100"/%3E%3C/svg%3E';
        img.alt = album.name;
        
        const title = document.createElement('div');
        title.className = 'card-title';
        title.textContent = album.name;
        
        const subtitle = document.createElement('div');
        subtitle.className = 'card-subtitle';
        subtitle.textContent = album.artists.map(a => a.name).join(', ');
        
        card.appendChild(img);
        card.appendChild(title);
        card.appendChild(subtitle);
        
        return card;
    }

    createArtistCard(artist) {
        const card = document.createElement('div');
        card.className = 'card';
        card.onclick = () => this.playArtist(artist.uri);
        
        const img = document.createElement('img');
        img.className = 'card-image';
        img.src = artist.images[0]?.url || 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"%3E%3Crect fill="%23333" width="100" height="100"/%3E%3C/svg%3E';
        img.alt = artist.name;
        img.style.borderRadius = '50%';
        
        const title = document.createElement('div');
        title.className = 'card-title';
        title.textContent = artist.name;
        
        const subtitle = document.createElement('div');
        subtitle.className = 'card-subtitle';
        subtitle.textContent = 'Artist';
        
        card.appendChild(img);
        card.appendChild(title);
        card.appendChild(subtitle);
        
        return card;
    }

    async playTrack(uri) {
        try {
            await fetch(`https://api.spotify.com/v1/me/player/play${this.deviceId ? `?device_id=${this.deviceId}` : ''}`, {
                method: 'PUT',
                headers: {
                    'Authorization': `Bearer ${this.accessToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ uris: [uri] })
            });
            
            this.updateNowPlaying();
        } catch (error) {
            console.error('Play failed:', error);
        }
    }

    async playPlaylist(playlistId) {
        try {
            await fetch(`https://api.spotify.com/v1/me/player/play${this.deviceId ? `?device_id=${this.deviceId}` : ''}`, {
                method: 'PUT',
                headers: {
                    'Authorization': `Bearer ${this.accessToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ context_uri: `spotify:playlist:${playlistId}` })
            });
            
            this.updateNowPlaying();
        } catch (error) {
            console.error('Play playlist failed:', error);
        }
    }

    async playAlbum(uri) {
        try {
            await fetch(`https://api.spotify.com/v1/me/player/play${this.deviceId ? `?device_id=${this.deviceId}` : ''}`, {
                method: 'PUT',
                headers: {
                    'Authorization': `Bearer ${this.accessToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ context_uri: uri })
            });
            
            this.updateNowPlaying();
        } catch (error) {
            console.error('Play album failed:', error);
        }
    }

    async playArtist(uri) {
        try {
            await fetch(`https://api.spotify.com/v1/me/player/play${this.deviceId ? `?device_id=${this.deviceId}` : ''}`, {
                method: 'PUT',
                headers: {
                    'Authorization': `Bearer ${this.accessToken}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ context_uri: uri })
            });
            
            this.updateNowPlaying();
        } catch (error) {
            console.error('Play artist failed:', error);
        }
    }

    async togglePlayPause() {
        try {
            const endpoint = this.isPlaying ? 'pause' : 'play';
            await fetch(`https://api.spotify.com/v1/me/player/${endpoint}`, {
                method: 'PUT',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            this.isPlaying = !this.isPlaying;
            this.updatePlayPauseButton();
        } catch (error) {
            console.error('Play/pause failed:', error);
        }
    }

    async previousTrack() {
        try {
            await fetch('https://api.spotify.com/v1/me/player/previous', {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            setTimeout(() => this.updateNowPlaying(), 500);
        } catch (error) {
            console.error('Previous track failed:', error);
        }
    }

    async nextTrack() {
        try {
            await fetch('https://api.spotify.com/v1/me/player/next', {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            setTimeout(() => this.updateNowPlaying(), 500);
        } catch (error) {
            console.error('Next track failed:', error);
        }
    }

    async toggleShuffle() {
        this.shuffle = !this.shuffle;
        
        try {
            await fetch(`https://api.spotify.com/v1/me/player/shuffle?state=${this.shuffle}`, {
                method: 'PUT',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            document.getElementById('shuffleBtn').classList.toggle('active', this.shuffle);
        } catch (error) {
            console.error('Shuffle toggle failed:', error);
        }
    }

    async toggleRepeat() {
        const modes = ['off', 'context', 'track'];
        const currentIndex = modes.indexOf(this.repeat);
        this.repeat = modes[(currentIndex + 1) % 3];
        
        try {
            await fetch(`https://api.spotify.com/v1/me/player/repeat?state=${this.repeat}`, {
                method: 'PUT',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            const repeatBtn = document.getElementById('repeatBtn');
            repeatBtn.classList.toggle('active', this.repeat !== 'off');
        } catch (error) {
            console.error('Repeat toggle failed:', error);
        }
    }

    async toggleLike() {
        if (!this.currentTrack) return;
        
        const likeBtn = document.getElementById('likeBtn');
        const isLiked = likeBtn.classList.contains('liked');
        
        try {
            await fetch(`https://api.spotify.com/v1/me/tracks?ids=${this.currentTrack.id}`, {
                method: isLiked ? 'DELETE' : 'PUT',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            likeBtn.classList.toggle('liked');
        } catch (error) {
            console.error('Like toggle failed:', error);
        }
    }

    async seek(position) {
        try {
            await fetch(`https://api.spotify.com/v1/me/player/seek?position_ms=${Math.floor(position * 1000)}`, {
                method: 'PUT',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            this.position = position;
        } catch (error) {
            console.error('Seek failed:', error);
        }
    }

    async setVolume(percent) {
        this.volume = percent;
        
        try {
            await fetch(`https://api.spotify.com/v1/me/player/volume?volume_percent=${Math.floor(percent * 100)}`, {
                method: 'PUT',
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            document.getElementById('volumeFill').style.width = `${percent * 100}%`;
        } catch (error) {
            console.error('Volume change failed:', error);
        }
    }

    async updateNowPlaying() {
        try {
            const response = await fetch('https://api.spotify.com/v1/me/player/currently-playing', {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            
            if (response.status === 204) {
                // No track playing
                this.currentTrack = null;
                document.getElementById('currentTrack').textContent = 'No track playing';
                document.getElementById('currentArtist').textContent = 'Select something to play';
                document.getElementById('currentAlbumArt').src = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"%3E%3Crect fill="%23333" width="100" height="100"/%3E%3C/svg%3E';
                return;
            }
            
            const data = await response.json();
            this.currentTrack = data.item;
            this.isPlaying = data.is_playing;
            this.position = data.progress_ms / 1000;
            this.duration = data.item.duration_ms / 1000;
            
            // Update UI
            document.getElementById('currentTrack').textContent = data.item.name;
            document.getElementById('currentArtist').textContent = data.item.artists.map(a => a.name).join(', ');
            document.getElementById('currentAlbumArt').src = data.item.album.images[0]?.url || 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"%3E%3Crect fill="%23333" width="100" height="100"/%3E%3C/svg%3E';
            
            this.updatePlayPauseButton();
            this.updateProgress();
            
            // Check if liked
            const likeResponse = await fetch(`https://api.spotify.com/v1/me/tracks/contains?ids=${data.item.id}`, {
                headers: { 'Authorization': `Bearer ${this.accessToken}` }
            });
            const [isLiked] = await likeResponse.json();
            document.getElementById('likeBtn').classList.toggle('liked', isLiked);
        } catch (error) {
            console.error('Update now playing failed:', error);
        }
    }

    updatePlayPauseButton() {
        const playIcon = document.getElementById('playIcon');
        const pauseIcon = document.getElementById('pauseIcon');
        
        if (this.isPlaying) {
            playIcon.style.display = 'none';
            pauseIcon.style.display = 'block';
        } else {
            playIcon.style.display = 'block';
            pauseIcon.style.display = 'none';
        }
    }

    updateProgress() {
        if (this.isPlaying) {
            this.position += 1;
        }
        
        const percent = this.duration > 0 ? (this.position / this.duration) * 100 : 0;
        document.getElementById('progressFill').style.width = `${percent}%`;
        document.getElementById('currentTime').textContent = this.formatTime(this.position);
        document.getElementById('totalTime').textContent = this.formatTime(this.duration);
    }

    formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }

    showTouchKeyboard() {
        // On touch devices, the system keyboard should appear automatically
        // This is a placeholder for custom keyboard implementation if needed
        const keyboard = document.getElementById('touchKeyboard');
        keyboard.classList.add('active');
    }

    hideTouchKeyboard() {
        const keyboard = document.getElementById('touchKeyboard');
        keyboard.classList.remove('active');
    }

    showAuthPrompt() {
        const content = document.getElementById('contentArea');
        content.innerHTML = `
            <div style="color: white; text-align: center; padding: 50px;">
                <h2>Authentication Required</h2>
                <p style="margin: 20px 0;">Please configure your Spotify credentials in the admin panel</p>
                <button class="search-btn" onclick="window.location.href='/admin'">
                    Open Admin Panel
                </button>
            </div>
        `;
    }
}

// Global functions for button onclick handlers
let player;

function togglePlayPause() { player.togglePlayPause(); }
function previousTrack() { player.previousTrack(); }
function nextTrack() { player.nextTrack(); }
function toggleShuffle() { player.toggleShuffle(); }
function toggleRepeat() { player.toggleRepeat(); }
function toggleLike() { player.toggleLike(); }
function performSearch() { player.performSearch(); }
function toggleMute() {
    const current = player.volume;
    player.setVolume(current > 0 ? 0 : 0.7);
}

// Initialize player when page loads
window.addEventListener('DOMContentLoaded', () => {
    player = new SpotifyPlayer();
    
    // Update now playing every 5 seconds
    setInterval(() => player.updateNowPlaying(), 5000);
});