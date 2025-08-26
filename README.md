# 🎵 Spotify Kids Manager

A complete, self-contained Docker solution for setting up a locked-down Spotify player for kids on Raspberry Pi or any Linux device.

## Features

### 🚀 One-Click Installation
- Fully automated setup via web interface
- Docker-based for consistency and portability
- Auto-starts on device boot
- No technical knowledge required

### 🔒 Complete Security Lockdown
- Dedicated restricted user account
- No keyboard/mouse access needed
- Network configuration locked
- WiFi settings unchangeable
- System commands disabled
- Auto-login with no shell access

### 🎮 Parental Controls
- Web-based control panel
- PIN-protected admin access
- Play/pause/skip controls from phone
- Volume control
- Playback scheduling
- Spotify blocking on demand
- Usage statistics

### 👶 Kid-Safe
- No video content access
- No YouTube or browser
- Terminal-only interface
- Cannot be closed or modified
- Explicit content filtering

## Quick Start

### Prerequisites
- Raspberry Pi (any model) or Linux computer
- Internet connection
- Spotify Premium account (for kids)

### Installation

1. **Download and run the installer:**
```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/install.sh | sudo bash
```

2. **Access the web interface:**
   - Open browser: `http://[device-ip-address]`
   - Default login: `admin` / `changeme`

3. **Follow the setup wizard:**
   - System checks
   - Create kid user account
   - Configure Spotify credentials
   - Apply security lockdown
   - Enable auto-start

## Web Interface

### Setup Wizard
The intuitive setup wizard guides you through:
1. **System Check** - Verifies all requirements
2. **User Creation** - Sets up restricted kid account
3. **Spotify Config** - Enters child's Spotify credentials
4. **Security** - Applies lockdown measures
5. **Auto-Start** - Enables boot-time startup

### Dashboard
After setup, access the dashboard to:
- View current playback status
- Control playback (play/pause/skip)
- Adjust volume
- View usage statistics
- Manage schedules

### Parental Controls
Advanced controls include:
- **Playback Scheduling** - Set allowed music hours
- **Spotify Blocking** - Temporarily disable access
- **Usage Monitoring** - Track listening habits
- **Remote Management** - Control from any device

## Security Features

### User Restrictions
- Custom restricted shell (no commands work)
- No sudo privileges
- No file system access
- No network modification ability

### System Lockdown
- Network config files immutable (`chattr +i`)
- TTY switching disabled
- Magic SysRq disabled
- All system commands return "Permission denied"

### Service Protection
- Auto-restarts if stopped
- Cannot be killed by user
- Monitored by systemd
- Health checks every 30 seconds

## Configuration

### Environment Variables
Set in `docker-compose.yml`:
```yaml
ADMIN_USER=admin          # Admin username
ADMIN_PASSWORD=changeme   # Admin password (CHANGE THIS!)
SECRET_KEY=your-secret    # Flask secret key
```

### Spotify Configuration
Located in `/app/config/spotifyd.conf`:
- Username (not email)
- Password
- Audio quality settings
- Device name

### Network Restrictions
Firewall rules automatically applied:
- Blocks router admin panels
- Allows only Spotify traffic
- Prevents network scanning

## Management

### Service Commands
```bash
# Status
sudo systemctl status spotify-kids-manager

# Restart
sudo systemctl restart spotify-kids-manager

# View logs
sudo journalctl -u spotify-kids-manager -f

# Stop service
sudo systemctl stop spotify-kids-manager
```

### Emergency Access
If needed to regain control:
1. SSH as admin user (not kid user)
2. Run: `sudo systemctl stop spotify-kids-manager`
3. Unlock files: `sudo chattr -i /path/to/file`

### Complete Removal
```bash
sudo systemctl stop spotify-kids-manager
sudo systemctl disable spotify-kids-manager
sudo rm -rf /opt/spotify-kids-manager
sudo rm /etc/systemd/system/spotify-kids-manager.service
sudo userdel -r kidmusic  # Or whatever username was created
```

## Spotify Setup

### Creating a Kid-Safe Account
1. Create a new Spotify account for your child
2. Consider Spotify Kids or Family plan
3. Enable explicit content filter:
   - Account Overview → Privacy Settings
   - Turn on "Block explicit content"

### Finding Your Username
Your Spotify username is NOT your email:
1. Log into spotify.com
2. Click profile → Account Overview
3. Find "Username" (usually numbers or custom name)

## Troubleshooting

### Can't Connect to Spotify
- Verify Premium subscription active
- Check username (not email) and password
- Ensure internet connection working
- View logs: `sudo docker-compose logs`

### No Sound
- Check volume in web interface
- Verify audio output: `aplay -l`
- Check ALSA mixer: `alsamixer`

### Web Interface Not Loading
- Check service running: `sudo systemctl status spotify-kids-manager`
- Verify port 80 not blocked
- Check Docker running: `sudo docker ps`

### Kid Can Access System
- Verify security applied in setup
- Check user restrictions: `sudo -u kidmusic whoami`
- Ensure files locked: `lsattr /etc/wpa_supplicant/wpa_supplicant.conf`

## Architecture

### Components
- **Backend**: Flask + Python for API and management
- **Frontend**: React with Material-UI
- **Audio**: Spotifyd for playback
- **Web Server**: Nginx reverse proxy
- **Process Manager**: Supervisord
- **Container**: Docker with host networking

### File Structure
```
/opt/spotify-kids-manager/
├── backend/           # Flask API
├── frontend/          # React UI
├── docker/           # Docker configs
├── scripts/          # Setup scripts
├── config/           # App configuration
└── data/            # Persistent data
```

## Development

### Building from Source
```bash
git clone https://github.com/yourusername/spotify-kids-manager.git
cd spotify-kids-manager
docker-compose build
docker-compose up
```

### Running Tests
```bash
# Backend tests
docker-compose run backend pytest

# Frontend tests
docker-compose run frontend npm test
```

## Support

### Common Issues
See [Troubleshooting](#troubleshooting) section above.

### Getting Help
- Create an issue on GitHub
- Check existing issues for solutions
- Include logs when reporting problems

## License

MIT License - See LICENSE file for details.

## Credits

Built with:
- [Spotifyd](https://github.com/Spotifyd/spotifyd) - Spotify daemon
- [Flask](https://flask.palletsprojects.com/) - Backend framework
- [React](https://reactjs.org/) - Frontend framework
- [Material-UI](https://mui.com/) - UI components
- [Docker](https://www.docker.com/) - Containerization

## Security Notice

This system is designed for home use with children. While it implements multiple security layers, it should not be considered bulletproof against a determined attacker with physical access. Always use in conjunction with appropriate supervision.

---

**⚠️ Important:** Change the default admin password immediately after installation!