# Spotify Kids Manager

A dedicated Spotify player for Raspberry Pi with parental controls, designed for kids' use with a touchscreen display.

## Quick Install

Run this single command to install everything:

```bash
curl -sSL https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/install.sh | sudo bash
```

Or if you want to review the script first:

```bash
wget https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## Reset/Reinstall

To completely reset and reinstall from scratch:

```bash
curl -sSL https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/install.sh | sudo bash -s -- --reset
```

## Features

### For Kids (Display/Touchscreen)
- 🎵 Native fullscreen Spotify player
- 👆 Touch-optimized interface with on-screen keyboard
- 🔒 Kiosk mode - cannot be closed or exited
- 🎨 Spotify-like interface with playlists, search, and album art
- 🚫 No video content - audio only
- ⏰ Time restrictions (configurable)
- 🔊 Volume limiting

### For Parents (Web Admin Panel)
- 🌐 Access from any device at `http://pi-ip-address:8080`
- 🔐 Password protected admin interface
- 🎮 Remote control of playback
- 📊 System monitoring (CPU, memory, disk)
- 🔄 One-click system updates
- ⚙️ Configure Spotify API credentials
- 🕒 Set time restrictions
- 🔊 Set maximum volume limits
- 🔒 Device lock to disable local controls

## Requirements

- Raspberry Pi (3B+ or newer recommended)
- Raspberry Pi OS (32-bit or 64-bit)
- LCD touchscreen display (optional but recommended)
- Internet connection
- Spotify Premium account
- Spotify App registration (for API credentials)

## Setting up Spotify API

1. Go to https://developer.spotify.com/dashboard
2. Log in with your Spotify account
3. Click "Create App"
4. Fill in:
   - App name: `Spotify Kids Player`
   - App description: `Personal kids player`
   - Redirect URI: `http://localhost:8888/callback`
5. Save your Client ID and Client Secret
6. Enter these in the admin panel after installation

## Default Credentials

- **Admin Panel**: `admin` / `changeme`
- **URL**: `http://<your-pi-ip>:8080`

⚠️ **Important**: Change the default password immediately after installation!

## System Architecture

```
spotify-kids-manager/
├── install.sh           # Installer with reset option
├── spotify_player.py    # Native Python/Tkinter player
├── web/                 # Admin web interface
│   └── app.py          # Flask admin panel
└── README.md           # This file
```

### Services

- **spotify-player.service** - Main player application (auto-starts on boot)
- **spotify-admin.service** - Web admin panel (port 5001, proxied through nginx on 8080)
- **nginx** - Reverse proxy for admin panel

### User Accounts

The installer creates two separate users for security:

**spotify-kids** (Player user)
- Auto-logs in on boot
- Starts X server with the player
- NO sudo privileges at all
- Can only run the player application
- Cannot access system settings

**spotify-admin** (Admin service user)
- Runs the web admin panel
- Has sudo rights for system updates and player control only
- Cannot log in interactively
- Service account only

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

## Updates

The admin panel includes a System Updates section where you can:
1. Check for available updates
2. Run system updates with live progress
3. All prompts are automatically answered (no interaction needed)

## Security Notes

- **Complete user separation**: Player user has NO sudo privileges
- **Admin panel** runs as separate service account with limited sudo
- **Network isolation**: Admin panel only accessible via network (port 8080)
- **Player lockdown**: Cannot be closed, no system access
- **Credentials**: Stored locally in `/opt/spotify-kids/config/`
- **No remote access** to player interface (display only)

## License

MIT

## Support

For issues, feature requests, or questions, please open an issue on GitHub.