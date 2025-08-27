# Spotify Kids Terminal Manager

A terminal-based Spotify client for Raspberry Pi with parental controls and web-based administration.

## Features

- **Terminal Spotify Client**: Full-screen ncspot client optimized for touchscreen
- **Parental Controls**: Lock device to prevent kids from exiting the player
- **Web Admin Panel**: Manage everything from any device on your network
- **Bluetooth Management**: Connect and manage Bluetooth speakers/headphones
- **Auto-start**: Dedicated user account that automatically starts Spotify on boot
- **Security**: No sudo access for the Spotify user, locked down environment
- **Easy Install**: Single command installation with web-based setup

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

## Post-Installation

After installation:

1. The device will reboot automatically
2. Access the web admin panel at: `http://[your-pi-ip]:8080`
3. Default credentials:
   - Username: `admin`
   - Password: `changeme`
4. **IMPORTANT**: Change the password immediately!
5. Configure your Spotify credentials through the terminal on first run

## Web Admin Features

- **Device Control**: Lock/unlock the device to prevent exit
- **Spotify Access**: Enable/disable Spotify completely
- **Bluetooth Management**: Scan, pair, and connect Bluetooth devices
- **Account Settings**: Change admin password
- **System Info**: View system status, logs, and restart services

## Usage

### For Kids
- Device boots directly into Spotify player
- Full touchscreen support
- Cannot exit when device is locked
- Only music content available (no video/podcasts)

### For Parents
- Access web panel from any device: `http://[pi-ip]:8080`
- Lock/unlock device remotely
- Disable Spotify access during homework time
- Manage Bluetooth speakers
- View system status and logs

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

### No Audio
```bash
# Test speakers
speaker-test -c 2

# Check audio devices
aplay -l

# Restart PulseAudio
pulseaudio -k && pulseaudio --start
```

### Cannot Access Web Panel
```bash
# Check service status
sudo systemctl status spotify-terminal-admin

# Check nginx
sudo systemctl status nginx

# View logs
sudo journalctl -u spotify-terminal-admin -f
```

### Spotify Not Working
- Verify you have a Premium account
- Check credentials (username, not email!)
- First-time setup requires configuration in terminal

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