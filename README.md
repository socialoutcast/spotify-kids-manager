# Spotify Kids Manager

A professional web-based Spotify player that's an exact clone of the Spotify Web Player interface, optimized for touchscreen kiosks with comprehensive parental controls via a secure admin panel.

## Quick Install

Run this single command to install everything:

```bash
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash
```

Or if you want to review the script first:

```bash
wget https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## Reset/Reinstall

To completely reset and reinstall from scratch:

```bash
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/force-reset.sh | sudo bash
```

Or for a quick reinstall (keeps existing config):

```bash
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash -s -- --reset
```

## Features

### Web Player (Display/Touchscreen)
- 🎵 **Exact Spotify Web Player Clone** - Pixel-perfect interface
- 🎨 Three-panel layout: Sidebar, Main View, Now Playing Bar
- 👆 Touch-optimized with large hit targets
- 🔒 Kiosk mode - runs fullscreen, cannot be closed
- 🎵 Full playback controls (play, pause, next, previous, seek)
- 🔀 Smart shuffle and regular shuffle modes
- ❤️ Like/unlike tracks functionality
- 🔁 Repeat modes (off, context, track)
- 🔍 Spotify search for tracks, albums, artists, playlists
- 📚 All playlists including Liked Songs and DJ
- 🖼️ Full album artwork display
- 🚫 No video content - audio only
- 🌐 WebSocket real-time updates
- 🖱️ Hidden cursor for touchscreen
- ⏰ Parental time restrictions
- 🔊 Volume limiting

### For Parents (Web Admin Panel)
- 🌐 Secure HTTPS access at `https://pi-ip-address`
- 🔐 Password protected admin interface
- 🎮 Remote control of playback
- 📊 System monitoring (CPU, memory, disk)
- 🔄 One-click system updates with live progress
- ⚙️ Configure Spotify API credentials
- 🎛️ **Parental Controls**:
  - Set allowed playlists
  - Block explicit content
  - Block specific artists/songs
  - Set time restrictions
  - Configure maximum volume
  - Set play time limits
- 🎨 **Player Configuration**:
  - Theme selection (Spotify Dark/Light, Kids Colorful, Minimal)
  - Toggle visualizer
  - Enable/disable gestures
  - Configure touch targets
- 🎧 **Bluetooth Management**:
  - Scan for Bluetooth speakers/headphones
  - Pair and connect devices
  - Manage paired devices
  - Enable/disable Bluetooth

## Requirements

### Hardware
- Raspberry Pi (3B+ or newer recommended)
- LCD touchscreen display (optional but recommended)
- Optional: Bluetooth speakers/headphones
- SD card (8GB minimum, 16GB recommended)
- Internet connection (WiFi or Ethernet)

### Software
- Raspberry Pi OS (32-bit or 64-bit)
- Spotify Premium account (required for API)
- Spotify App registration (free developer account)

## Setting up Spotify API

1. Go to https://developer.spotify.com/dashboard
2. Log in with your Spotify account
3. Click "Create App"
4. Fill in:
   - App name: `Spotify Kids Player`
   - App description: `Personal kids player`
   - Redirect URI: `https://<your-pi-ip>/callback`
5. Save your Client ID and Client Secret
6. Enter these in the admin panel after installation

## Default Credentials

- **Admin Panel**: `admin` / `changeme`
- **URL**: `https://<your-pi-ip>`
- **Player**: `http://localhost:5000` (local display only)

⚠️ **Important**: Change the default password immediately after installation!

## System Architecture

```
spotify-kids-manager/
├── install.sh           # Complete installer with reset option
├── player/              # Node.js web player application
│   ├── server.js        # Express server with Spotify API
│   ├── package.json     # Node dependencies
│   └── client/          # Frontend files
│       └── index.html   # Spotify Web Player clone UI
├── web/                 # Admin web interface
│   ├── app.py          # Flask admin panel
│   └── static/         # Admin UI assets
│       └── admin.js    # Admin panel JavaScript
├── kiosk_launcher.sh   # Chromium kiosk mode launcher
└── README.md           # This file
```

### Services

- **spotify-player.service** - Node.js web server serving Spotify clone (port 5000)
- **spotify-admin.service** - Flask admin panel (port 5001)
- **nginx** - HTTPS reverse proxy (port 443) with SSL termination
- **lightdm** - Display manager for auto-login and kiosk mode
- **bluetooth.service** - Bluetooth audio support

### User Accounts

The installer creates two separate users for security:

**spotify-kids** (Player user)
- Auto-logs in via LightDM
- Runs Chromium in kiosk mode
- Owns the player service and files
- NO sudo privileges at all
- Member of audio, video, input groups
- Cannot access system settings

**spotify-admin** (Admin service user)
- Runs the web admin panel service
- Member of spotify-pkgmgr group for limited sudo
- Has sudo rights for system updates and service control only
- Cannot log in interactively
- Service account only

**spotify-config** (Shared group)
- Allows both users to access configuration files
- Ensures proper permission management

## Troubleshooting

### Player won't start
```bash
sudo systemctl status spotify-player
sudo journalctl -u spotify-player -f
```

### Admin panel not accessible
```bash
sudo systemctl status spotify-admin
sudo systemctl status nginx
sudo netstat -tlnp | grep 8080
```

### Reset everything
```bash
sudo spotify-kids-uninstall  # If installed
# Then reinstall with:
curl -sSL https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/install.sh | sudo bash -s -- --reset
```

### Manual uninstall
```bash
sudo systemctl stop spotify-player spotify-admin
sudo systemctl disable spotify-player spotify-admin
sudo rm -rf /opt/spotify-kids
sudo userdel -r spotify-kids
sudo userdel spotify-admin
sudo rm /etc/sudoers.d/spotify-admin
sudo rm /etc/nginx/sites-*/spotify-admin
sudo rm /etc/systemd/system/spotify-*.service
```

## Bluetooth Audio

The admin panel provides complete Bluetooth management:

### Setup Bluetooth Speakers
1. Open admin panel at `http://pi-ip:8080`
2. Navigate to "Bluetooth Devices" section
3. Click "Scan for Devices" 
4. Select your speaker/headphones and click "Pair"
5. Device will auto-connect when available

### Managing Devices
- **Connect/Disconnect** - Control active audio output
- **Remove** - Delete paired devices
- **Enable/Disable** - Turn Bluetooth on/off completely

All Bluetooth audio devices work seamlessly with the Spotify player. The `spotify-kids` user has audio permissions but NO admin access.

## System Updates

The admin panel includes a System Updates section where you can:
1. Check for available updates
2. Run system updates with live terminal output
3. All prompts are automatically answered (no interaction needed)

## Security Notes

- **Complete user separation**: Player user has NO sudo privileges
- **Admin panel** runs as separate service account with limited sudo
- **HTTPS encryption**: Self-signed SSL certificate for OAuth requirements
- **Network isolation**: Admin panel only accessible via HTTPS (port 443)
- **Player lockdown**: Chromium kiosk mode, cannot be closed
- **Credentials**: Stored locally in `/opt/spotify-kids/config/`
- **Token management**: Automatic refresh of Spotify access tokens
- **No remote access** to player interface (localhost only)

## License

MIT

## Support

For issues, feature requests, or questions, please open an issue on GitHub.