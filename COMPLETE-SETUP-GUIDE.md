# 🎵 Spotify Kids Manager - Complete Setup Guide

## Table of Contents
1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Pre-Installation Setup](#pre-installation-setup)
4. [Installation Methods](#installation-methods)
5. [Initial Configuration](#initial-configuration)
6. [Setup Wizard Walkthrough](#setup-wizard-walkthrough)
7. [Parent Dashboard Guide](#parent-dashboard-guide)
8. [Security Features](#security-features)
9. [Troubleshooting](#troubleshooting)
10. [Advanced Configuration](#advanced-configuration)
11. [Maintenance](#maintenance)
12. [FAQ](#faq)

---

## Overview

**Spotify Kids Manager** is a complete, dockerized solution that transforms any Raspberry Pi or Linux device into a secure, child-safe music player. Once configured, the device:

- ✅ Auto-boots directly into music player (no login screen)
- ✅ Cannot be exited or modified by kids
- ✅ Blocks access to videos, YouTube, and web browsing
- ✅ Provides parent control via phone/tablet web interface
- ✅ Automatically installs security updates
- ✅ Works without keyboard or mouse

### What You Get

- **For Kids**: Simple music playback with no distractions
- **For Parents**: Complete control via web dashboard
- **Security**: Automatic updates, locked configuration, network protection
- **Peace of Mind**: Can't be broken or bypassed by curious kids

---

## Requirements

### Hardware Requirements

#### Minimum:
- **Raspberry Pi**: Any model (Pi 2, 3, 4, or Zero W)
- **Storage**: 8GB SD card minimum
- **RAM**: 1GB minimum
- **Network**: Ethernet or WiFi connection
- **Audio**: HDMI, 3.5mm jack, or USB audio device

#### Recommended:
- **Raspberry Pi 3B+** or newer
- **16GB SD card** or larger
- **2GB RAM** or more
- **Stable WiFi** connection
- **Quality speakers** or audio system

### Software Requirements
- **Operating System**: 
  - Raspberry Pi OS (Bullseye or newer)
  - Ubuntu Server 20.04 LTS or newer
  - Debian 11 or newer
- **Spotify Account**: Premium required (Family or Individual)
- **Network**: Internet connection for Spotify streaming

### Parent Requirements
- **Phone/Tablet/Computer** for web interface access
- **Basic network knowledge** (finding IP addresses)

---

## Pre-Installation Setup

### Step 1: Prepare Your Raspberry Pi

#### 1.1 Install Raspberry Pi OS

1. Download **Raspberry Pi Imager** from [raspberrypi.com/software](https://www.raspberrypi.com/software/)

2. Insert SD card into your computer

3. Open Raspberry Pi Imager and configure:
   ```
   Operating System: Raspberry Pi OS (64-bit) 
   Storage: Select your SD card
   ```

4. Click the gear icon ⚙️ for advanced options:
   - ✅ Enable SSH
   - ✅ Set username: `pi` (or your preference)
   - ✅ Set password: (choose a strong password)
   - ✅ Configure WiFi (if not using Ethernet)
   - ✅ Set locale settings

5. Click "Write" and wait for completion

#### 1.2 First Boot Setup

1. Insert SD card into Raspberry Pi
2. Connect to network (Ethernet or WiFi)
3. Power on and wait 2-3 minutes for first boot
4. Find your Pi's IP address:
   - Check router admin panel, OR
   - Use network scanner app on phone, OR
   - Connect monitor temporarily and run `hostname -I`

### Step 2: Connect to Your Raspberry Pi

#### From Windows:
1. Download **PuTTY** from [putty.org](https://www.putty.org/)
2. Enter your Pi's IP address
3. Click "Open"
4. Login with username/password from setup

#### From Mac/Linux:
```bash
ssh pi@YOUR_PI_IP_ADDRESS
# Enter password when prompted
```

### Step 3: Update System

Once connected via SSH:

```bash
# Update package lists
sudo apt update

# Upgrade existing packages
sudo apt upgrade -y

# Install required tools
sudo apt install -y curl git wget

# Reboot to apply updates
sudo reboot
```

Wait 2 minutes, then reconnect via SSH.

---

## Installation Methods

### Method 1: One-Click Installation (Recommended)

This is the easiest method for most users:

```bash
# Connect to your Pi via SSH, then run:
curl -fsSL https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/install.sh | sudo bash
```

**What this does:**
1. Installs Docker and Docker Compose
2. Downloads Spotify Kids Manager
3. Builds the Docker container
4. Sets up auto-start service
5. Starts the web interface

**Installation takes approximately:**
- 5-10 minutes on Pi 4
- 10-15 minutes on Pi 3
- 15-20 minutes on older models

### Method 2: Manual Installation

For users who prefer step-by-step control:

#### Step 1: Install Docker
```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Add current user to docker group
sudo usermod -aG docker $USER

# Enable Docker service
sudo systemctl enable docker
sudo systemctl start docker
```

#### Step 2: Install Docker Compose
```bash
# Install dependencies
sudo apt update
sudo apt install -y python3-pip libffi-dev

# Install Docker Compose
sudo pip3 install docker-compose
```

#### Step 3: Download Spotify Kids Manager
```bash
# Create installation directory
sudo mkdir -p /opt/spotify-kids-manager
cd /opt/spotify-kids-manager

# Clone the repository (or download release)
sudo git clone https://github.com/yourusername/spotify-kids-manager.git .
```

#### Step 4: Build and Start
```bash
# Build Docker image
sudo docker-compose build

# Start the service
sudo docker-compose up -d
```

#### Step 5: Create System Service
```bash
# Create systemd service
sudo tee /etc/systemd/system/spotify-kids-manager.service << 'EOF'
[Unit]
Description=Spotify Kids Manager
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=/opt/spotify-kids-manager
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable spotify-kids-manager
sudo systemctl start spotify-kids-manager
```

### Method 3: Development Installation

For developers or testing:

```bash
# Clone repository
git clone https://github.com/yourusername/spotify-kids-manager.git
cd spotify-kids-manager

# Install development dependencies
npm install --prefix frontend
pip install -r backend/requirements.txt

# Run in development mode
docker-compose -f docker-compose.dev.yml up
```

---

## Initial Configuration

### Step 1: Access Web Interface

1. Open web browser on your phone/tablet/computer
2. Navigate to: `http://YOUR_PI_IP_ADDRESS`
   - Example: `http://192.168.1.100`
3. You should see the Spotify Kids Manager login page

### Step 2: First Login

**Default Credentials:**
- Username: `admin`
- Password: `changeme`

⚠️ **IMPORTANT**: Change these immediately after first login!

### Step 3: Change Admin Password

1. After login, go to Settings
2. Click "Change Password"
3. Enter new secure password
4. Save changes

---

## Setup Wizard Walkthrough

The setup wizard guides you through 5 essential steps:

### Step 1: System Check

The wizard automatically verifies:
- ✅ Docker is running
- ✅ Network connectivity
- ✅ Audio system available
- ✅ Spotifyd installed

**What to do:**
- Review all checks are green
- If any are red, see [Troubleshooting](#troubleshooting)
- Click "Next" to continue

### Step 2: Create Kid User

This creates a restricted user account for auto-login.

**Settings to configure:**
- **Username**: Default is `kidmusic` (you can change it)
- **Restrictions applied**:
  - No shell access
  - No sudo privileges
  - Cannot modify system
  - Only audio group membership

**What happens:**
- System creates new user
- Sets up restricted environment
- Configures home directory
- Click "Next" when complete

### Step 3: Configure Spotify

This is the most important step!

#### Getting Spotify Credentials:

**Finding Your Username:**
1. Go to [spotify.com](https://www.spotify.com)
2. Log into your account
3. Click profile icon → Account Overview
4. Find "Username" (NOT email!)
   - Usually looks like: `1234567890` or `customname`

**Setting Up for Kids:**
1. Consider creating separate Spotify account for kids
2. Use Spotify Family plan for individual accounts
3. Enable explicit content filter:
   - Account Overview → Privacy Settings
   - Toggle "Block explicit content" ON

**Enter in Wizard:**
- Spotify Username: (from above)
- Spotify Password: (account password)
- Click "Test Connection"
- Only proceed if test succeeds

### Step 4: Apply Security

Choose security measures to apply:

**Recommended Settings (all ON):**
- ✅ **Lock network configuration** - Prevents WiFi changes
- ✅ **Disable TTY switching** - Blocks console access
- ✅ **Make files immutable** - Protects configurations
- ✅ **Restrict all commands** - Disables system commands

**What this does:**
- Makes system tamper-proof
- Prevents network modifications
- Blocks all system access
- Creates bulletproof environment

### Step 5: Enable Auto-Start

Final configuration step:

**What happens:**
- Configures auto-login for kid user
- Sets music player to start on boot
- Removes need for keyboard/mouse
- System will reboot after applying

**After this step:**
- Device auto-starts into music player
- No login screen shown
- Music begins playing automatically
- Parent control via web only

---

## Parent Dashboard Guide

### Accessing the Dashboard

After setup, access dashboard at:
```
http://YOUR_PI_IP_ADDRESS
```

Login with your admin credentials.

### Dashboard Overview

#### Main Screen Shows:
- **System Status**: Security, Music, Updates, Spotify status
- **Playback Controls**: Play/Pause, Skip, Volume
- **Usage Stats**: Today's playtime, songs played
- **Quick Actions**: Common tasks

### Navigation Menu

#### 📊 Overview
- System health at a glance
- Current playback status
- Quick controls
- Usage summary

#### 🔒 Parental Controls
- **Spotify Blocking**: Instantly disable/enable music
- **Time Limits**: Set daily usage limits
- **Scheduled Access**: Define allowed music hours
- **Content Filtering**: Additional restrictions

#### 🔄 System Updates
- **Update Status**: See available updates
- **Security Patches**: Priority security updates
- **Install Updates**: One-click installation
- **Auto-Update Settings**: Configure schedule
- **Update History**: View past updates

#### 📅 Schedule
- **Daily Schedule**: Set music hours for each day
- **Quiet Hours**: Auto-pause during bedtime
- **Weekend Rules**: Different weekend settings
- **Holiday Mode**: Special occasion overrides

#### 📈 Statistics
- **Usage Graphs**: Visual playtime tracking
- **Popular Songs**: Most played tracks
- **Listening Patterns**: Time-of-day analysis
- **Monthly Reports**: Long-term trends

#### ⚙️ Settings
- **Change Password**: Update admin credentials
- **Network Settings**: View network info
- **Audio Configuration**: Output device selection
- **Backup/Restore**: Configuration management

### Key Features

#### 1. Instant Spotify Blocking
- Red "Block Spotify" button
- Immediately stops all playback
- Prevents any music until unblocked
- Useful for discipline or quiet time

#### 2. Remote Playback Control
- Control from any device on network
- No need to physically access Pi
- Real-time status updates
- Volume control

#### 3. System Update Management
- **Automatic Security Updates**: Enable for hands-off security
- **Update Scheduling**: Choose when updates install (default 3 AM)
- **Safe Updates**: Music pauses during updates, resumes after
- **Update Notifications**: Badge shows available updates

#### 4. Usage Monitoring
- Track daily listening time
- See favorite playlists
- Monitor song choices
- Export usage reports

---

## Security Features

### Multi-Layer Security

#### Layer 1: User Restrictions
- Custom shell prevents command execution
- No sudo access whatsoever
- Limited to audio group only
- Cannot read/write system files

#### Layer 2: Network Lockdown
- WiFi configuration locked (`chattr +i`)
- Network manager access denied
- Router admin panels blocked
- DNS changes prevented

#### Layer 3: System Protection
- TTY switching disabled
- Magic SysRq keys disabled
- Boot parameters locked
- GRUB menu hidden

#### Layer 4: File Immutability
- Configuration files unchangeable
- System files protected
- User cannot modify own files
- Requires root to unlock

#### Layer 5: Service Protection
- Auto-restart on crash
- Systemd hardening
- Resource limits enforced
- Cannot be killed by user

#### Layer 6: Container Isolation
- Docker containerization
- Limited container privileges
- Restricted system calls
- Namespace isolation

### What Kids CANNOT Do:
- ❌ Exit music player
- ❌ Access terminal/console
- ❌ Change WiFi settings
- ❌ Install software
- ❌ Browse internet
- ❌ Watch videos
- ❌ Modify any settings
- ❌ Access other user accounts
- ❌ Change passwords
- ❌ Stop the service

### What Parents CAN Do:
- ✅ Control playback remotely
- ✅ Block Spotify instantly
- ✅ Set time limits
- ✅ Monitor usage
- ✅ Install updates
- ✅ Change settings
- ✅ Access via SSH (admin only)
- ✅ Modify restrictions
- ✅ View logs
- ✅ Backup configuration

---

## Troubleshooting

### Common Issues and Solutions

#### Problem: Cannot Access Web Interface

**Symptoms**: Browser shows "cannot connect" or timeout

**Solutions**:
1. Verify IP address:
   ```bash
   ssh pi@YOUR_PI_IP
   hostname -I
   ```

2. Check service status:
   ```bash
   sudo systemctl status spotify-kids-manager
   ```

3. Check Docker is running:
   ```bash
   sudo docker ps
   ```

4. Check firewall:
   ```bash
   sudo ufw status
   # If active, allow port 80:
   sudo ufw allow 80
   ```

5. Restart service:
   ```bash
   sudo systemctl restart spotify-kids-manager
   ```

#### Problem: Spotify Won't Connect

**Symptoms**: "Failed to connect to Spotify" error

**Solutions**:
1. Verify Premium subscription active
2. Check username is correct (not email!)
3. Reset Spotify password and retry
4. Check internet connection:
   ```bash
   ping spotify.com
   ```
5. Review Spotifyd logs:
   ```bash
   sudo docker logs spotify-kids-manager 2>&1 | grep spotifyd
   ```

#### Problem: No Sound Output

**Symptoms**: Music plays but no audio

**Solutions**:
1. Check volume not muted:
   ```bash
   amixer set Master 75%
   ```

2. List audio devices:
   ```bash
   aplay -l
   ```

3. Test audio:
   ```bash
   speaker-test -c 2
   ```

4. Set audio output (for HDMI):
   ```bash
   amixer cset numid=3 2
   ```

5. Edit Spotifyd config:
   ```bash
   sudo nano /opt/spotify-kids-manager/config/spotifyd.conf
   # Change: device = "default" 
   # To: device = "hw:0,0" or "hw:1,0"
   ```

#### Problem: System Not Auto-Starting

**Symptoms**: Requires manual start after reboot

**Solutions**:
1. Check service enabled:
   ```bash
   sudo systemctl is-enabled spotify-kids-manager
   ```

2. Enable if disabled:
   ```bash
   sudo systemctl enable spotify-kids-manager
   ```

3. Check auto-login configured:
   ```bash
   cat /etc/systemd/system/getty@tty1.service.d/autologin.conf
   ```

4. Verify kid user exists:
   ```bash
   id kidmusic
   ```

#### Problem: Updates Failing

**Symptoms**: "Update failed" errors

**Solutions**:
1. Check disk space:
   ```bash
   df -h
   ```

2. Clear apt cache:
   ```bash
   sudo apt clean
   sudo apt autoremove
   ```

3. Fix broken packages:
   ```bash
   sudo apt --fix-broken install
   ```

4. Manual update:
   ```bash
   sudo apt update
   sudo apt upgrade
   ```

### Getting Help

#### Log Files Location:
```bash
# Main service logs
sudo journalctl -u spotify-kids-manager -f

# Docker container logs
sudo docker logs spotify-kids-manager

# Spotifyd specific logs
sudo docker exec spotify-kids-manager cat /app/logs/spotifyd.log

# System logs
/var/log/syslog
```

#### Diagnostic Commands:
```bash
# Full system check
curl -fsSL https://raw.githubusercontent.com/yourusername/spotify-kids-manager/main/diagnostic.sh | bash

# Generate support bundle
sudo docker exec spotify-kids-manager /app/scripts/support-bundle.sh
```

---

## Advanced Configuration

### Custom Spotify Playlists

#### Setting Default Playlist:
1. Get playlist URI from Spotify
2. Edit configuration:
   ```bash
   sudo docker exec -it spotify-kids-manager bash
   nano /app/config/default_playlist.txt
   # Add: spotify:playlist:YOUR_PLAYLIST_ID
   ```

### Network Configuration

#### Static IP Assignment:

Edit `/etc/dhcpcd.conf`:
```bash
interface wlan0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8 8.8.4.4
```

#### WiFi Configuration:

Edit `/etc/wpa_supplicant/wpa_supplicant.conf`:
```bash
network={
    ssid="YourWiFiName"
    psk="YourWiFiPassword"
    key_mgmt=WPA-PSK
}
```

### Audio Configuration

#### USB Audio Device:
```bash
# List USB audio devices
lsusb
aplay -l

# Set as default
sudo nano /etc/asound.conf
```

Add:
```
pcm.!default {
    type hw
    card 1
}
ctl.!default {
    type hw
    card 1
}
```

#### Bluetooth Speaker:
```bash
# Install Bluetooth support
sudo apt install bluealsa

# Pair device
bluetoothctl
> scan on
> pair XX:XX:XX:XX:XX:XX
> connect XX:XX:XX:XX:XX:XX
> trust XX:XX:XX:XX:XX:XX
```

### Performance Tuning

#### For Older Raspberry Pi Models:

1. Reduce memory usage:
   ```bash
   sudo nano /boot/config.txt
   # Add:
   gpu_mem=16
   ```

2. Disable unnecessary services:
   ```bash
   sudo systemctl disable bluetooth
   sudo systemctl disable avahi-daemon
   ```

3. Optimize Docker:
   ```bash
   sudo nano /etc/docker/daemon.json
   ```
   Add:
   ```json
   {
     "storage-driver": "overlay2",
     "log-driver": "json-file",
     "log-opts": {
       "max-size": "10m",
       "max-file": "3"
     }
   }
   ```

### Backup and Restore

#### Creating Backup:
```bash
# Backup configuration
sudo docker exec spotify-kids-manager /app/scripts/backup.sh

# Download backup
scp pi@YOUR_PI_IP:/opt/spotify-kids-manager/backups/backup-*.tar.gz ./
```

#### Restoring Backup:
```bash
# Upload backup
scp backup-*.tar.gz pi@YOUR_PI_IP:/tmp/

# Restore
sudo docker exec spotify-kids-manager /app/scripts/restore.sh /tmp/backup-*.tar.gz
```

---

## Maintenance

### Regular Maintenance Tasks

#### Weekly:
- Check system health in dashboard
- Review usage statistics
- Verify updates installed

#### Monthly:
- Check disk space: `df -h`
- Clear old logs: `sudo journalctl --vacuum-time=30d`
- Review blocked packages
- Test backup procedure

#### Quarterly:
- Update admin password
- Review security settings
- Check Spotify account security
- Update parent documentation

### Updating Spotify Kids Manager

#### Method 1: Web Interface
1. Go to Settings → System
2. Click "Check for Updates"
3. Click "Update Application"

#### Method 2: Command Line
```bash
cd /opt/spotify-kids-manager
sudo git pull
sudo docker-compose build
sudo docker-compose down
sudo docker-compose up -d
```

### Monitoring System Health

#### Via Dashboard:
- Green shield = All systems healthy
- Yellow shield = Minor issues
- Red shield = Immediate attention needed

#### Via Command Line:
```bash
# Check all services
sudo docker exec spotify-kids-manager /app/scripts/health-check.sh

# Monitor resources
htop

# Check temperature (Pi only)
vcgencmd measure_temp
```

---

## FAQ

### General Questions

**Q: Do I need Spotify Premium?**
A: Yes, Spotify Premium is required for playback control and ad-free experience.

**Q: Can I use Spotify Free?**
A: No, the API requires Premium for playback control.

**Q: Will this work with Apple Music/YouTube Music?**
A: No, currently only Spotify is supported.

**Q: Can multiple kids share one device?**
A: Yes, but they'll share the same Spotify account and settings.

**Q: Can I install this on a regular computer?**
A: Yes, any Linux system with Docker support will work.

### Security Questions

**Q: Can kids bypass the restrictions?**
A: No, the multi-layer security prevents any bypass attempts.

**Q: What if kids unplug the device?**
A: It will resume locked state when powered back on.

**Q: Can kids access other users' music?**
A: No, they only have access to the configured Spotify account.

**Q: Is my Spotify password stored securely?**
A: It's stored in the Docker container, readable only by root.

**Q: Can this be hacked remotely?**
A: The system only exposes port 80 for the web interface, which requires authentication.

### Technical Questions

**Q: How much bandwidth does it use?**
A: Approximately 150-320 kbps for music streaming (Spotify's bitrate).

**Q: Can I use this without internet?**
A: No, Spotify requires internet for streaming.

**Q: Does it work with Spotify Connect?**
A: Yes, the device appears as "Kids Music Player" in Spotify Connect.

**Q: Can I change the device name?**
A: Yes, edit `/opt/spotify-kids-manager/config/spotifyd.conf`

**Q: How do I enable Bluetooth speakers?**
A: See [Advanced Configuration](#advanced-configuration) for Bluetooth setup.

### Troubleshooting Questions

**Q: Why does music stop after 4 hours?**
A: The service auto-restarts every 4 hours to prevent memory issues.

**Q: Can I disable auto-updates?**
A: Yes, in Dashboard → System Updates → Disable Automatic Updates

**Q: How do I completely remove this?**
A: Run: `sudo /opt/spotify-kids-manager/scripts/uninstall.sh`

**Q: Where are logs stored?**
A: In Docker: `/app/logs/`, on host: `journalctl -u spotify-kids-manager`

**Q: How do I reset to factory defaults?**
A: Run: `sudo docker exec spotify-kids-manager /app/scripts/factory-reset.sh`

---

## Support

### Getting Help

1. **Documentation**: Check this guide first
2. **GitHub Issues**: [github.com/yourusername/spotify-kids-manager/issues](https://github.com/yourusername/spotify-kids-manager/issues)
3. **Logs**: Include relevant log output with any support request
4. **System Info**: Run diagnostic script and include output

### Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### License

MIT License - See [LICENSE](LICENSE) file for details.

---

## Quick Reference Card

### Essential Commands

```bash
# Service Management
sudo systemctl status spotify-kids-manager    # Check status
sudo systemctl restart spotify-kids-manager   # Restart service
sudo systemctl stop spotify-kids-manager      # Stop service
sudo systemctl start spotify-kids-manager     # Start service

# Docker Commands
sudo docker ps                                # List containers
sudo docker logs spotify-kids-manager         # View logs
sudo docker exec -it spotify-kids-manager bash # Enter container

# Network Info
hostname -I                                   # Get IP address
ping spotify.com                             # Test internet

# Audio Testing
speaker-test -c 2                            # Test speakers
amixer set Master 75%                        # Set volume
aplay -l                                     # List audio devices

# Updates
sudo apt update && sudo apt upgrade -y       # System updates
cd /opt/spotify-kids-manager && git pull     # App updates
```

### Important URLs

- Web Interface: `http://YOUR_PI_IP_ADDRESS`
- Spotify Account: `https://www.spotify.com/account/overview/`
- Spotify Developer: `https://developer.spotify.com/dashboard/`
- Project GitHub: `https://github.com/yourusername/spotify-kids-manager`

### Default Paths

- Installation: `/opt/spotify-kids-manager`
- Configuration: `/opt/spotify-kids-manager/config`
- Logs: `/opt/spotify-kids-manager/logs`
- Backups: `/opt/spotify-kids-manager/backups`
- Kid User Home: `/home/kidmusic`

---

*Last Updated: 2024*
*Version: 1.0.0*