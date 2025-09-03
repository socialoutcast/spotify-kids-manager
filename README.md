# Spotify Kids Manager 🎵

A comprehensive parental control system for Spotify that provides a safe, managed music experience for children. Features a kid-friendly web player, parental controls, time limits, content filtering, and full kiosk mode support for Raspberry Pi deployment.

![Spotify Kids Manager](https://img.shields.io/badge/Spotify-Kids%20Manager-1DB954?style=for-the-badge&logo=spotify&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=nodedotjs&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-A22846?style=for-the-badge&logo=raspberry-pi&logoColor=white)

## 🌟 Features

### Kid-Friendly Web Player
- 🎵 **Exact Spotify Web Player Clone** - Familiar interface optimized for kids
- 👆 Touch-optimized with large, friendly controls
- 🎨 Visual playlist covers with easy navigation
- 🎵 Full playback controls (play, pause, next, previous, seek)
- 🔊 Volume control with visual feedback
- 🔀 Shuffle and repeat modes
- ❤️ Like/unlike tracks functionality
- 📱 Responsive design for tablets and touchscreens
- 🖼️ Full album artwork display
- 🌐 Real-time WebSocket updates

### Parental Controls & Admin Dashboard
- ⏰ **Time Limits**: Set daily listening limits and schedules
- 🚫 **Content Filtering**: Block explicit content automatically
- ⏭️ **Skip Limits**: Prevent excessive song skipping
- 📋 **Approved Playlists**: Curate which playlists kids can access
- 📊 **Usage Statistics**: Track listening time and habits
- 🎨 **Modern Spotify-themed dark interface**
- 📈 Real-time system monitoring
- 🔵 Bluetooth device management
- 📝 System logs viewer
- 🔄 One-click service restarts

### Kiosk Mode
- 🖥️ Full-screen browser mode for dedicated devices
- 🚀 Auto-start on boot
- 🔒 No system access for kids
- 🍓 Perfect for Raspberry Pi deployment
- 👆 Touch-optimized interface

## 📋 Prerequisites

Before you begin, ensure you have:

- ✅ **Spotify Premium Account** (required for web playback)
- ✅ **Raspberry Pi 4 Model B (4GB RAM recommended)**
- ✅ **MicroSD Card (32GB minimum)** with Raspberry Pi OS 64-bit
- ✅ **Touch Display** (recommended: [7" 1024x600 HDMI LCD](https://www.amazon.com/dp/B09B29T8YF) for optimal kiosk experience)

## 🚀 Quick Installation

### Option 1: One-Line Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash
```

> ⏳ **Please be patient!** This installation will take 10-20 minutes as it:
> - Removes unnecessary software to free up space
> - Updates all system packages to latest versions  
> - Installs all dependencies and configures services
> - Sets up audio, Bluetooth, and display systems
> - Configures SSL certificates and security

### Option 2: Download and Review First

```bash
wget https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

> ⏳ **Installation time:** Allow 10-20 minutes for complete setup

The installer will automatically:
- Install all dependencies
- Create system users and groups
- Set up systemd services
- Configure Nginx with SSL
- Initialize configuration files
- Start all services

## 🎯 Spotify Developer Setup (IMPORTANT!)

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

### Step 3: Configure Redirect URI (CRITICAL!)

1. **Access Your Admin Panel**
   ```
   https://YOUR_RASPBERRY_PI_IP
   
   Default login:
   Username: admin
   Password: changeme
   ```

2. **Get Your Callback URL**
   - When you first access the admin panel
   - Look at the top of the Spotify Setup section
   - You'll see a message showing your callback URL:
   ```
   Your Redirect URI: http://YOUR_IP:5001/callback
   ```
   - **COPY THIS EXACT URL**

3. **Add to Spotify App**
   - Go back to your Spotify app in the Developer Dashboard
   - Click **"Settings"**
   - Find **"Redirect URIs"** section
   - Click **"Add"**
   - Paste your callback URL EXACTLY as shown
   - Click **"Save"**

### Step 4: Configure in Admin Panel

1. **Navigate to Spotify Setup**
   - Click "Spotify Setup" in the sidebar

2. **Enter Your Credentials**
   - Paste your **Client ID**
   - Paste your **Client Secret**
   - Click **"Save Configuration"**

3. **Test Connection**
   - Click **"Test Connection"**
   - Should show "Connection successful!"

4. **Authenticate Your Account**
   - Click **"Authenticate with Spotify"**
   - Log in with your Spotify Premium account
   - Click **"Agree"** to authorize
   - You'll be redirected back to the admin panel

## ✅ Verification

After setup, verify everything is working:

1. **Check Service Status**
   - In admin panel, go to Dashboard
   - All services should show green checkmarks:
     - ✅ Player
     - ✅ Kiosk
     - ✅ Spotify
     - ✅ Bluetooth

2. **Test the Player**
   - The kiosk should auto-start showing the player
   - Or navigate to `http://YOUR_IP:3000` on any device
   - You should see your playlists
   - Try playing a song

## 🎮 Usage Guide

### For Parents/Administrators

1. **Access Admin Panel**
   ```
   https://YOUR_DEVICE_IP
   ```

2. **Dashboard Overview**
   - System resources (CPU, Memory, Disk)
   - Service status indicators
   - Quick action buttons
   - System control options

3. **Manage Settings**
   - **Spotify Setup**: Configure API credentials
   - **Bluetooth**: Connect speakers/headphones
   - **System Logs**: View and download logs
   - **Admin Settings**: Change password

### For Kids

The player runs automatically in kiosk mode:
- Browse playlists with visual covers
- Tap songs to play
- Use large, friendly control buttons
- Volume slider on the right
- Cannot exit or access system

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

### Common Issues and Solutions

#### "Spotify not configured" Error
1. Ensure Client ID and Secret are correct
2. Verify Redirect URI matches EXACTLY (including http/https and port)
3. Make sure you clicked "Save" in Spotify Dashboard after adding URI
4. Try re-authenticating

#### Player Not Loading
```bash
# Check if service is running
sudo systemctl status spotify-player

# Check for errors
sudo journalctl -u spotify-player -n 100

# Restart service
sudo systemctl restart spotify-player
```

#### No Sound / Bluetooth Issues
```bash
# Check Bluetooth status
sudo systemctl status bluetooth

# List paired devices
bluetoothctl paired-devices

# Connect to speaker (replace XX with your device MAC)
bluetoothctl connect XX:XX:XX:XX:XX:XX

# Set as default audio
pactl list sinks short
pactl set-default-sink bluez_sink.XX_XX_XX_XX_XX_XX.a2dp_sink
```

#### Kiosk Not Starting
```bash
# Check display
echo $DISPLAY

# Restart kiosk
sudo systemctl restart spotify-kiosk

# Manual test
DISPLAY=:0 chromium-browser --kiosk http://localhost:3000
```

#### Authentication Loop
1. Clear browser cookies
2. Check your Spotify account is Premium
3. Verify redirect URI includes correct port (:5001)
4. Try incognito/private browsing mode

## 📁 File Structure

```
/opt/spotify-kids/
├── player/
│   ├── server.js           # Express backend for player
│   ├── client/
│   │   └── index.html      # Player web interface
│   └── package.json
├── web/
│   ├── app.py              # Flask admin panel
│   └── static/
│       └── admin.js        # Admin panel JavaScript
├── config/
│   ├── config.json         # Main configuration
│   ├── schedule.json       # Time limits
│   ├── playlists.json      # Approved playlists
│   └── cache/              # Token cache
├── ssl/
│   ├── server.crt          # SSL certificate
│   └── server.key          # SSL private key
├── kiosk_launcher.sh       # Kiosk startup script
└── install.sh              # Installation script
```

## 🔒 Security Features

- **SSL/HTTPS**: All connections encrypted
- **Session Authentication**: Secure admin panel
- **Token Encryption**: Spotify tokens stored securely
- **System Isolation**: Separate users for each service
- **No Shell Access**: Kiosk mode prevents system access
- **Content Filtering**: Automatic explicit content blocking

## 🎨 Customization

### Change Player Theme

Edit `/opt/spotify-kids/player/client/index.html`:

```css
:root {
    --spotify-green: #1db954;
    --background: #000;
    --surface: #181818;
    --text-primary: #fff;
}
```

### Modify Time Limits

Edit `/opt/spotify-kids/config/schedule.json`:

```json
{
  "daily_limit_minutes": 120,
  "schedule": {
    "monday": {
      "enabled": true,
      "start": "15:00",
      "end": "19:00"
    }
  }
}
```

## 🔄 Updates

To update to the latest version:

```bash
cd /opt/spotify-kids
sudo git pull
sudo systemctl restart spotify-player spotify-admin
```

## 🆘 Reset/Reinstall

If you need to start fresh:

```bash
# Complete reset (removes all data)
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/force-reset.sh | sudo bash

# Reinstall (keeps config)
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash -s -- --reset
```

## 📝 Environment Variables

Create `/opt/spotify-kids/.env` for advanced configuration:

```env
# Spotify API
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
SPOTIFY_REDIRECT_URI=http://your_ip:5001/callback

# Admin Panel
ADMIN_USERNAME=admin
ADMIN_PASSWORD_HASH=your_bcrypt_hash

# Player Settings
PLAYER_PORT=3000
ADMIN_PORT=5001
SKIP_LIMIT=10
EXPLICIT_FILTER=true
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License & Commercial Use

**PROPRIETARY SOFTWARE** - This is proprietary, copyrighted software owned by SavageIndustries.

### Personal Use
- ✅ Install and use on your own devices for personal/family use
- ✅ Access through provided installation methods

### Prohibited
- ❌ **NO redistribution, modification, or commercial use without permission**
- ❌ **NO reverse engineering or code extraction**
- ❌ **NO selling or incorporating into commercial products**
- ❌ **NO creating derivative works or competing products**

### Commercial Licensing
Interested in:
- **Selling devices with this software pre-installed?**
- **Using in a business environment?**
- **Creating products based on this system?**

**Contact for commercial licensing:** [Your Email Here]

See the [LICENSE](LICENSE) file for complete terms and conditions.

## ⚠️ Important Disclaimers

- This project is **NOT affiliated with Spotify AB**
- Spotify is a registered trademark of Spotify AB  
- This is an independent project using official Spotify Web API
- **Requires Spotify Premium subscription**
- User assumes all responsibility for compliance with Spotify Terms of Service

## 📧 Support

For issues, questions, or suggestions:
- Open an issue on [GitHub](https://github.com/socialoutcast/spotify-kids-manager/issues)
- Check existing issues for solutions
- Include logs when reporting problems:
  ```bash
  sudo journalctl -u spotify-player -n 100 > player.log
  sudo journalctl -u spotify-admin -n 100 > admin.log
  ```

---

**Made with ❤️ for parents who love music and want to share it safely with their kids**