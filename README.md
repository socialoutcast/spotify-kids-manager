# 🎵 Spotify Kids Manager

A complete, self-contained Docker solution for setting up a locked-down Spotify player for kids on Raspberry Pi or any Linux device. Transform any device into a secure, child-safe music player with web-based parental controls.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?logo=docker&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/-RaspberryPi-C51A4A?logo=Raspberry-Pi)
![Spotify](https://img.shields.io/badge/Spotify-1DB954?logo=spotify&logoColor=white)

## 🌟 Features

### For Kids
- 🎵 Simple music playback - no distractions
- 🚫 No access to videos or YouTube
- 🔒 Cannot exit or modify the player
- ⌨️ Works without keyboard/mouse
- 🎯 Kid-safe interface only

### For Parents  
- 📱 **Web Control Panel** - Control from any phone/tablet
- 🔐 **Complete Security** - Multi-layer protection system
- ⏰ **Scheduling** - Set allowed music hours
- 📊 **Usage Monitoring** - Track listening habits
- 🚨 **Instant Blocking** - Stop music immediately when needed
- 🔄 **Automatic Updates** - Security patches applied automatically

## 📋 Prerequisites

### Hardware Requirements

#### Minimum Requirements
- **Device**: Raspberry Pi 2/3/4/Zero W OR any Linux computer
- **RAM**: 1GB minimum
- **Storage**: 8GB SD card/disk minimum  
- **Network**: Ethernet or WiFi connection
- **Audio**: HDMI, 3.5mm jack, or USB audio output

#### Recommended Setup
- **Device**: Raspberry Pi 3B+ or newer
- **RAM**: 2GB or more
- **Storage**: 16GB+ SD card (Class 10)
- **Network**: Stable WiFi connection
- **Audio**: Quality speakers or sound system
- **Power**: Official Raspberry Pi power supply

### Software Requirements

#### Operating System (choose one)
- **Raspberry Pi OS** (Bullseye or newer) - Recommended
- **Ubuntu Server** 20.04 LTS or newer
- **Debian** 11 or newer
- **DietPi** (for minimal resource usage)

#### Spotify Account
- ✅ **Spotify Premium Required** (Individual or Family)
  - Free accounts will NOT work (API limitation)
  - Family plan recommended for separate kid accounts
- 📝 You'll need:
  - Spotify username (NOT email - see [Finding Your Username](#finding-your-spotify-username))
  - Spotify password

#### Network Requirements  
- Internet connection for streaming
- Local network access for parent controls
- Port 80 available (for web interface)

### Parent Device Requirements
- Any device with a web browser:
  - Smartphone (iOS/Android)
  - Tablet
  - Computer
  - Smart TV browser

## 🚀 Quick Start

### Prerequisites Checklist
Before starting, ensure you have:
- [ ] Raspberry Pi with OS installed and network connected
- [ ] Spotify Premium account
- [ ] Know your Pi's IP address
- [ ] SSH access to your Pi (or keyboard/monitor)

### One-Line Installation

SSH into your Raspberry Pi and run:

```bash
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash
```

This will:
1. Install Docker and dependencies
2. Download and build the application
3. Configure auto-start service
4. Launch the web interface

**Installation time**: 10-15 minutes on Pi 3/4, 15-20 minutes on older models

### First-Time Setup

1. **Access Web Interface**
   ```
   http://YOUR_PI_IP_ADDRESS
   ```
   Example: `http://192.168.1.100`

2. **Login with default credentials**
   - Username: `admin`  
   - Password: `changeme`
   - ⚠️ **CHANGE THESE IMMEDIATELY!**

3. **Follow Setup Wizard**
   - System checks
   - Create kid user account
   - Configure Spotify
   - Apply security settings
   - Enable auto-start

## 📖 Finding Your Spotify Username

Your Spotify username is **NOT your email address**! To find it:

1. Go to [spotify.com](https://www.spotify.com)
2. Log into your account
3. Click your profile icon → **Account Overview**
4. Find **"Username"** field
   - Format: Usually numbers like `1234567890` or a custom username
   - NOT your email address!

## 🛠️ Manual Installation

For users who prefer step-by-step installation:

### Step 1: Prepare Your Device

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install prerequisites
sudo apt install -y curl git wget
```

### Step 2: Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# Install Docker Compose
sudo apt install -y docker-compose
```

### Step 3: Install Spotify Kids Manager

```bash
# Create directory
sudo mkdir -p /opt/spotify-kids-manager
cd /opt/spotify-kids-manager

# Clone repository
sudo git clone https://github.com/socialoutcast/spotify-kids-manager.git .

# Build and start
sudo docker-compose build
sudo docker-compose up -d
```

### Step 4: Enable Auto-Start

```bash
# Create systemd service
sudo tee /etc/systemd/system/spotify-kids-manager.service << 'EOF'
[Unit]
Description=Spotify Kids Manager
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
WorkingDirectory=/opt/spotify-kids-manager
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable spotify-kids-manager
sudo systemctl start spotify-kids-manager
```

## 🔒 Security Features

### Multi-Layer Protection
- **User Level**: Restricted shell, no sudo access
- **Network Level**: WiFi settings locked, router access blocked
- **System Level**: Commands disabled, files immutable
- **Service Level**: Auto-restart, unkillable process
- **Container Level**: Docker isolation, limited privileges

### What Kids CANNOT Do
- ❌ Exit the music player
- ❌ Access terminal or settings
- ❌ Change WiFi configuration
- ❌ Browse internet or watch videos
- ❌ Install or modify software
- ❌ Access other accounts

### What Parents CAN Do
- ✅ Control playback remotely
- ✅ Block Spotify instantly
- ✅ Set time limits and schedules
- ✅ Monitor usage statistics
- ✅ Apply security updates
- ✅ Manage all settings via web

## 📱 Parent Dashboard

Access from any device at: `http://YOUR_PI_IP_ADDRESS`

### Features
- **Real-time Controls**: Play/pause, skip, volume
- **Instant Blocking**: Stop music immediately
- **Scheduling**: Set allowed hours for each day
- **Usage Stats**: Track listening time and favorites
- **System Updates**: Automatic security patches
- **Quick Actions**: Common tasks at your fingertips

## 🔧 Troubleshooting

### Common Issues

#### Cannot Access Web Interface
```bash
# Check service status
sudo systemctl status spotify-kids-manager

# Restart service
sudo systemctl restart spotify-kids-manager

# Check IP address
hostname -I
```

#### Spotify Won't Connect
- Verify Premium subscription is active
- Check username is correct (not email!)
- Ensure internet connection works
- Try resetting Spotify password

#### No Sound Output
```bash
# Test speakers
speaker-test -c 2

# Check volume
amixer set Master 75%

# List audio devices
aplay -l
```

## 📊 System Requirements Summary

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Device** | Raspberry Pi 2 | Raspberry Pi 3B+ or 4 |
| **RAM** | 1GB | 2GB+ |
| **Storage** | 8GB SD Card | 16GB+ SD Card |
| **Network** | Any connection | Stable WiFi/Ethernet |
| **Spotify** | Premium Required | Family Plan |
| **OS** | Raspbian Buster | Raspbian Bullseye |

## 🆘 Getting Help

### Documentation
- [Complete Setup Guide](COMPLETE-SETUP-GUIDE.md) - Detailed instructions
- [GitHub Issues](https://github.com/socialoutcast/spotify-kids-manager/issues) - Report problems

### Quick Commands
```bash
# View logs
sudo docker logs spotify-kids-manager

# Enter container
sudo docker exec -it spotify-kids-manager bash

# Check system health
curl http://localhost/health
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Spotifyd](https://github.com/Spotifyd/spotifyd) - Lightweight Spotify daemon
- [Docker](https://www.docker.com/) - Containerization
- [Flask](https://flask.palletsprojects.com/) - Backend framework
- [React](https://reactjs.org/) - Frontend framework
- [Material-UI](https://mui.com/) - UI components

## ⚠️ Important Notes

1. **Spotify Premium is REQUIRED** - Free accounts will not work
2. **Change default password** immediately after installation
3. **For kids under 13**, consider using Spotify Kids app where available
4. **This is for home use** - Not intended for commercial deployment

## 🚦 Project Status

![Version](https://img.shields.io/badge/version-1.0.0-green.svg)
![Maintenance](https://img.shields.io/badge/maintained-yes-green.svg)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)

---

**Made with ❤️ for parents who want safe music for their kids**

*If this project helps you, please consider giving it a ⭐ on GitHub!*