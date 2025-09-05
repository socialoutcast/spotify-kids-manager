# Spotify Kids Manager 🎵

**Transform any Raspberry Pi into a secure, parent-controlled Spotify music player designed specifically for children.**

![Spotify Kids Manager](https://img.shields.io/badge/Spotify-Kids%20Manager-1DB954?style=for-the-badge&logo=spotify&logoColor=white)
![License](https://img.shields.io/badge/License-Proprietary-red?style=for-the-badge)
![Release](https://img.shields.io/github/v/release/socialoutcast/spotify-kids-manager?style=for-the-badge)

## 🚀 Quick Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/setup.sh | sudo bash
```

## 🔄 Complete Uninstall/Reset

Remove all components and configurations:

```bash
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/setup.sh | sudo bash -s -- --reset
```


## 🌟 Features

### Kid-Friendly Spotify Web Player
- 🎵 **Full Spotify Web Playback SDK** - Complete Spotify streaming functionality
- 🎨 **Visual Interface** - Large album artwork and easy-to-read text
- 🎮 **Simple Controls** - Play, pause, skip, previous with large touch targets
- 🔊 **Volume Control** - Visual slider with easy adjustment
- ⏱️ **Progress Bar** - Shows song position with seek capability
- ❤️ **Like Songs** - Save favorite tracks
- 📱 **Responsive Design** - Optimized for touchscreens and tablets
- 🖼️ **Now Playing View** - Expandable view with album art and song info
- 📡 **Real-time Updates** - WebSocket connection for instant status updates

### Admin Dashboard
- 🔐 **Secure Login** - Password-protected admin panel (HTTPS)
- 📊 **System Monitoring** - CPU, memory, disk usage, and service status
- 🎧 **Spotify Integration** - Configure API credentials and authenticate
- 🔵 **Bluetooth Manager** - Scan, pair, connect, and manage audio devices
- 📝 **System Logs** - View and download logs for troubleshooting
- 📦 **Package Management** - Update system packages from the web interface
- 🔧 **Service Control** - Restart services and reboot/shutdown system
- 🛠️ **Diagnostics** - Built-in diagnostic tools and fixes

### Kiosk Mode
- 🖥️ **Full-Screen Browser** - Chromium in kiosk mode
- 🚀 **Auto-Start on Boot** - Launches automatically after system startup
- 🔒 **Locked Interface** - Prevents access to system functions
- 🍓 **Raspberry Pi Optimized** - Configured for Pi hardware

### Audio & Bluetooth
- 🔊 **PulseAudio Integration** - Professional audio management
- 🎧 **Bluetooth Audio** - A2DP high-quality audio only (no hands-free)
- 🔄 **Auto-Reconnect** - Reconnects paired devices on boot
- 🎯 **Auto-Switch** - Automatically switches to newly connected devices
- 📡 **Multiple Device Support** - Manage multiple Bluetooth speakers

## 📋 Prerequisites

- ✅ **Raspberry Pi 4 Model B** (2GB minimum, 4GB recommended)
- ✅ **MicroSD Card** (32GB minimum) with Raspberry Pi OS 64-bit
- ✅ **Spotify Premium Account** (required for web playback)
- ✅ **Internet Connection** for streaming
- ✅ **Optional: Touchscreen Display** for kiosk mode
- ✅ **Optional: Bluetooth Speakers** for wireless audio

## 📦 What Gets Installed

The installer automatically sets up:

### System Packages
- Chromium browser for kiosk mode
- Python 3 and Flask for admin panel
- Node.js for the player backend
- Nginx for reverse proxy
- PulseAudio for audio management
- Bluetooth packages for wireless audio
- SSL certificates for secure access

### System Services
- **spotify-player** - Web player backend (port 3000)
- **spotify-admin** - Admin panel (port 5001)
- **spotify-kiosk** - Kiosk browser service
- **pulseaudio-spotify-kids** - Dedicated audio service
- **bluetooth-autoconnect** - Auto-reconnect paired devices

### Users and Groups
- **spotify-kids** - Main application user
- **spotify-admin** - Admin panel user
- **spotify-config** - Configuration management group
- **spotify-pkgmgr** - Package management group

## 🎯 Spotify Developer Setup

### Step 1: Create Your Spotify App

1. **Go to Spotify Developer Dashboard**
   ```
   https://developer.spotify.com/dashboard
   ```
   - Log in with your Spotify account
   - Click the green **"Create app"** button

2. **Fill in the App Details**
   ```
   App name: Spotify Kids Manager
   App description: Parental control system for Spotify
   Website: (leave blank or add your website)
   Redirect URI: (we'll add this in Step 3)
   ```

3. **Select APIs**
   - Check: ✅ **Web API**
   - Check: ✅ **Web Playback SDK**
   
4. **Accept Terms and Create**
   - Check the terms of service box
   - Click **"Save"**

### Step 2: Get Your Credentials

1. **In your new app's dashboard:**
   - You'll see your **Client ID** displayed (copy this)
   - Click **"Settings"** button
   - Click **"View client secret"** (copy this too)
   - Keep these safe - you'll need them soon!

### Step 3: Configure Redirect URI

1. Access your Pi's admin panel:
   ```
   https://YOUR_PI_IP
   Username: admin
   Password: changeme
   ```

2. The admin panel will show your redirect URI at the top
3. Copy the exact URI (usually `http://YOUR_PI_IP:5001/callback`)
4. In Spotify Developer Dashboard:
   - Click **"Settings"**
   - Add your redirect URI
   - Click **"Save"**

### Step 4: Configure in Admin Panel

1. Go to **"Spotify Setup"** in the admin panel
2. Enter your Client ID and Client Secret
3. Click **"Save Configuration"**
4. Click **"Test Connection"**
5. Click **"Authenticate with Spotify"**
6. Log in and authorize the app

## ✅ Verification

After setup, verify everything works:

1. **Check Services** - All should show green in the dashboard:
   - Player Service
   - Admin Service  
   - Kiosk Mode
   - PulseAudio
   - Bluetooth

2. **Test Player**:
   - Navigate to `http://YOUR_PI_IP:3000`
   - Or wait for kiosk to auto-start
   - You should see your Spotify playlists

## 🎮 Usage

### Admin Panel (https://YOUR_PI_IP)

- **Dashboard** - System overview and quick actions
- **Spotify Setup** - Configure API and authentication
- **Bluetooth** - Manage audio devices
- **System Logs** - View application logs
- **System** - Reboot, shutdown, update packages

### Player Interface

- Browse playlists and albums
- Click songs to play
- Control playback with bottom bar
- Adjust volume on the right
- Click album art for expanded view

## 🛠️ System Architecture

### Services

| Service | Port | Description |
|---------|------|-------------|
| spotify-player | 3000 | Web player backend |
| spotify-admin | 5001 | Admin panel |
| spotify-kiosk | - | Chromium kiosk browser |
| nginx | 80/443 | Reverse proxy |

### Managing Services

```bash
# Check status
sudo systemctl status spotify-player
sudo systemctl status spotify-admin
sudo systemctl status spotify-kiosk

# Restart services
sudo systemctl restart spotify-player
sudo systemctl restart spotify-admin
sudo systemctl restart spotify-kiosk

# View logs
sudo journalctl -u spotify-player -f
sudo journalctl -u spotify-admin -f
sudo journalctl -u spotify-kiosk -f
```

## 🔧 Troubleshooting

### Spotify Not Working
1. Verify Premium account is active
2. Check redirect URI matches exactly
3. Re-authenticate in admin panel

### No Audio
1. Check Bluetooth connections in admin panel
2. Ensure PulseAudio service is running
3. Try reconnecting Bluetooth device

### Kiosk Not Starting
```bash
sudo systemctl status spotify-kiosk
sudo systemctl restart spotify-kiosk
```

### Service Issues
```bash
# Check all services
sudo systemctl status spotify-player
sudo systemctl status spotify-admin
sudo systemctl status pulseaudio-spotify-kids

# Restart a service
sudo systemctl restart [service-name]

# View logs
sudo journalctl -u [service-name] -f
```

## 📁 File Locations

```
/opt/spotify-kids/
├── player/               # Web player backend
│   ├── server.js        # Express/WebSocket server
│   └── client/
│       └── index.html   # Player interface
├── web/                 # Admin panel
│   └── app.py          # Flask application
├── config/             # Configuration files
│   ├── spotify_config.json
│   └── admin_config.json
└── ssl/                # SSL certificates
```

## 🔒 Security

- HTTPS encryption for admin panel
- Password-protected administration
- Secure session management
- System isolation with dedicated users
- No shell access in kiosk mode
- Encrypted configuration storage




## 📄 License

**PROPRIETARY SOFTWARE** - Copyright © 2025 SavageIndustries

This is proprietary software. Unauthorized copying, modification, distribution, or reverse engineering is strictly prohibited.

For commercial licensing inquiries, please contact the repository owner.

## ⚠️ Disclaimers

- NOT affiliated with Spotify AB
- Requires Spotify Premium subscription
- User responsible for Spotify Terms of Service compliance

---

**Made with ❤️ for parents who love music and want to share it safely with their kids**