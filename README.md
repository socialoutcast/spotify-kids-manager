# Spotify Kids Manager

A touchscreen-friendly Spotify player designed for Raspberry Pi, perfect for creating a kid-safe music device with parental controls and web-based administration.

## Features

- 🎵 **Full Spotify Web Player**: Beautiful web interface with album art and playlists
- 🔒 **Device Lock**: Prevents kids from exiting the player or accessing system
- 📱 **Touchscreen Optimized**: Designed for Raspberry Pi touchscreens
- 🎨 **Kid-Friendly Interface**: Clean, colorful design that's easy to navigate
- 👤 **Multi-user Support**: Each family member can have their own account
- 🔐 **Web Admin Panel**: Manage everything from any device on your network
- 🎧 **Bluetooth Support**: Connect wireless speakers and headphones
- 📶 **Spotify Connect**: Use as a Spotify Connect device from your phone
- 🚫 **No Video Content**: Music only - no podcasts or video content accessible

## Requirements

- Raspberry Pi (any model with 1GB+ RAM)
- Raspberry Pi OS 64-bit
- Spotify Premium account (required for ncspot)
- Internet connection
- Optional: Touchscreen display

## Installation

### Quick Install (One Command)

```bash
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/remote-install.sh | sudo bash
```

### Complete Reset (Fix 502 Errors)

If you're getting 502 errors or need to completely reset (no prompts, just resets):

```bash
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/remote-install.sh | sudo bash -s -- reset
```

### Other Commands

```bash
# Diagnose issues (including 502 errors)
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/remote-install.sh | sudo bash -s -- diagnose

# Repair existing installation
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/remote-install.sh | sudo bash -s -- repair

# Completely uninstall
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/remote-install.sh | sudo bash -s -- uninstall

# Show help
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/remote-install.sh | sudo bash -s -- help
```

### Local Installation

```bash
git clone https://github.com/socialoutcast/spotify-kids-manager.git
cd spotify-kids-manager
sudo ./install.sh           # Normal install
sudo ./install.sh --reset    # Complete reset
sudo ./install.sh --diagnose # Run diagnostics
```

## Setting Up Spotify (Required)

### Step 1: Create a Spotify App

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account
3. Click **"Create app"**
4. Fill in the app details:
   - **App name**: `Spotify Kids Player` (or any name you prefer)
   - **App description**: `Personal Spotify player for Raspberry Pi`
   - **Website**: Leave blank or use `http://localhost`
   - **Redirect URI**: Click "Add" and enter: `http://localhost:8888/callback`
   - ⚠️ **Important**: If accessing from another device, also add: `http://[your-pi-ip]:8888/callback`
5. Check **"Web API"** under "Which API/SDKs are you planning to use?"
6. Check the agreement checkbox
7. Click **"Save"**

### Step 2: Get Your Credentials

1. In your app's dashboard, you'll see your **Client ID** (a 32-character string)
2. Click **"View client secret"** to reveal your **Client Secret** (another 32-character string)
3. **Copy both values** - you'll need them for configuration

### Step 3: Configure in Admin Panel

After installation:

1. Access the web admin panel at: `http://[your-pi-ip]:8080`
2. Default login credentials:
   - Username: `admin` 
   - Password: `changeme`
3. **IMMEDIATELY change the admin password!**
4. Go to **Spotify Configuration** section
5. In **Step 1: Spotify API Credentials**:
   - Paste your **Client ID**
   - Paste your **Client Secret**  
   - Click **"Save API Credentials"**
6. In **Step 2: Spotify Account Login**:
   - **Option A (Recommended)**: Click **"Login with Spotify OAuth"**
     - You'll be redirected to Spotify
     - Authorize the app
     - You'll return to the player automatically
   - **Option B**: Enter username/password for backend authentication

## Using the Player

### Web Player Interface

The player automatically launches on boot at `http://localhost:8888` (or `http://[pi-ip]:8888` from another device)

**Main Features:**
- 🔍 **Search**: Tap search icon to find songs, artists, albums
- 📚 **Library**: Your playlists appear in the sidebar
- 🎵 **Now Playing**: Shows current track with large album art
- ⏯️ **Controls**: Play/pause, skip, shuffle, repeat, like
- ⌨️ **Touch Keyboard**: Automatically appears when searching (touchscreen only)

### Admin Panel Controls

Access at `http://[your-pi-ip]:8080`

**Device Control:**
- **Device Lock Toggle**:
  - **ON**: Locks screen, disables touchscreen input, blanks display
  - **OFF**: Unlocks screen, re-enables touch, restarts player
  
- **Spotify Access Toggle**:
  - **ON**: Launches Spotify player in kiosk mode
  - **OFF**: Closes player, shows desktop for admin tasks

**User Management:**
- Create non-admin users for each child
- Configure auto-login for selected user
- Each user can have separate Spotify settings

**Bluetooth Devices:**
- Scan for available devices
- Connect/disconnect speakers and headphones
- Manage paired devices

## Architecture

- **Terminal Client**: ncspot (Rust-based Spotify TUI)
- **Display Server**: X11 with Openbox and urxvt
- **Web Admin**: Flask + Python
- **Web Server**: Nginx reverse proxy
- **Service Manager**: systemd
- **Audio**: PulseAudio with Bluetooth support

## Uninstallation

To completely remove the system:

1. Via web interface: Login and click "Uninstall System"
2. Via command line: `sudo /opt/spotify-terminal/scripts/uninstall.sh`

This will:
- Remove all installed components
- Delete the spotify-kids user
- Restore system to original state
- Reboot the device

## Troubleshooting

### "Authentication Required" or Blank Player Screen

This means Spotify API credentials haven't been configured:
1. Go to admin panel (`http://[pi-ip]:8080`)
2. Follow the Spotify setup steps above
3. Make sure to save both Client ID and Secret
4. Use OAuth login for best results

### "INVALID_CLIENT: Invalid redirect URI"

The redirect URI doesn't match what's in your Spotify app:
1. Go to [Spotify App Settings](https://developer.spotify.com/dashboard)
2. Add these redirect URIs:
   - `http://localhost:8888/callback`
   - `http://[your-pi-ip]:8888/callback` (replace with actual IP)
3. Save changes and try again

### Cannot Find Spotify Username

Your username is NOT your email. To find it:
1. Open Spotify (app or web)
2. Click your profile → Account
3. Your username is shown in account overview
4. It's usually a random string like "31xyzabc123"

### Player Works But No Sound

```bash
# Test audio output
speaker-test -c 2

# Check selected audio device
amixer
alsamixer  # Use F6 to select sound card

# For Bluetooth speakers, check connection
bluetoothctl info [device-mac]
```

### 502 Bad Gateway Error

```bash
# Restart services
sudo systemctl restart spotify-web
sudo systemctl restart spotify-terminal-admin
sudo systemctl restart nginx

# Check logs
sudo journalctl -u spotify-web -f
```

### Device Lock Not Working

Touchscreen might not be detected properly:
```bash
# List input devices
xinput list

# Test touchscreen manually
xinput disable [device-id]
xinput enable [device-id]
```

### Bluetooth Issues
```bash
# Check Bluetooth service
sudo systemctl status bluetooth

# Scan manually
bluetoothctl scan on
```

## Security Notes

- The spotify-kids user has no sudo access
- Web admin runs as root for system management
- Session-based authentication for web panel
- Device lock prevents terminal exit
- No access to system settings when locked

## Development

### File Structure
```
/opt/spotify-terminal/
├── scripts/           # Bash scripts
│   ├── spotify-client.sh
│   ├── start-x.sh
│   └── uninstall.sh
├── web/              # Flask web admin
│   └── app.py
├── config/           # Configuration files
│   ├── admin.json
│   └── client.conf
└── data/            # Runtime data
    ├── device.lock
    └── client.log
```

### Customization

Edit display settings in `/opt/spotify-terminal/scripts/start-x.sh`
Modify ncspot config in `/home/spotify-kids/.config/ncspot/config.toml`

## Support

Create an issue on GitHub for bugs or feature requests.

## License

MIT License - See LICENSE file for details