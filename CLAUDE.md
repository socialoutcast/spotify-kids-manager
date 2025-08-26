# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Spotify Kids Manager is a Docker-based solution that transforms any Linux device (especially Raspberry Pi) into a locked-down, child-safe Spotify player with comprehensive web-based parental controls. The system provides multi-layer security to prevent kids from exiting the player or accessing other content while allowing parents full remote control.

## Architecture

### Tech Stack
- **Frontend**: React 18 + TypeScript + Material-UI
  - Location: `/frontend/src/`
  - Build system: Create React App
  - Key components: Dashboard, SetupWizard, ParentalControls, SystemUpdates
- **Backend**: Flask + Python 3.11
  - Location: `/backend/`
  - Main apps: `app.py` (full), `simple_app.py` (lightweight)
  - Update manager: `update_manager.py`
- **Infrastructure**: Docker + Docker Compose
  - Multiple Dockerfiles: `Dockerfile.interactive` (main), `Dockerfile.simple` (lightweight)
  - Supervisor for process management
  - Nginx reverse proxy on port 8080
- **Audio**: Spotifyd daemon for Spotify playback
  - Requires Spotify Premium account

### Key Directories
```
/opt/spotify-kids-manager/     # Production installation directory
/app/data/                      # Persistent data (configs, status)
/app/config/                    # Configuration files
/app/logs/                      # Application logs
```

## Common Development Commands

### Frontend Development
```bash
cd frontend
npm install                     # Install dependencies
npm start                       # Development server (port 3000)
npm run build                   # Production build
npm test                        # Run tests
```

### Backend Development
```bash
cd backend
pip install -r requirements.txt # Install Python dependencies
python app.py                   # Run Flask server (port 5000)
python simple_app.py            # Run lightweight version
```

### Docker Operations
```bash
# Build and run with Docker Compose
docker-compose build            # Build the container
docker-compose up -d            # Run in detached mode
docker-compose down             # Stop and remove containers
docker-compose logs -f          # View logs

# Build specific Dockerfile
docker build -f Dockerfile.interactive -t spotify-kids-manager:latest .
docker build -f Dockerfile.simple -t spotify-kids-manager:simple .

# Access running container
docker exec -it spotify-kids-manager bash
```

### Installation & Deployment
```bash
# One-line installation (production)
curl -fsSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash

# Quick install for testing
./quick-install.sh

# Troubleshooting
./troubleshoot.sh               # Diagnostic script
```

### Service Management (Production)
```bash
sudo systemctl status spotify-kids-manager
sudo systemctl restart spotify-kids-manager
sudo systemctl stop spotify-kids-manager
sudo systemctl enable spotify-kids-manager  # Auto-start on boot
journalctl -u spotify-kids-manager -f      # View service logs
```

## High-Level Architecture

### Security Model
The application implements multi-layer security:
1. **Container Level**: Docker isolation with limited privileges
2. **Network Level**: Host network mode for Spotifyd audio, reverse proxy on 8080
3. **Application Level**: Session-based authentication, login decorators
4. **System Level**: Supervisor ensures processes restart, health checks

### Component Flow
1. **User Access**: Browser → Port 8080 → Nginx → Flask Backend (5000)
2. **Frontend**: React SPA served from Flask static files after build
3. **Audio**: Spotifyd daemon controlled via backend subprocess commands
4. **Updates**: UpdateManager class handles automatic security updates
5. **Setup**: SetupManager tracks installation wizard progress

### Key Backend Classes
- `SetupManager`: Handles initial configuration wizard state
- `SystemManager`: Executes system commands safely
- `SpotifyManager`: Controls Spotifyd daemon and configuration
- `SecurityManager`: Applies system-level security restrictions
- `UpdateManager`: Manages automatic updates and patches
- `BluetoothManager`: Manages Bluetooth device discovery, pairing, and audio routing

### Authentication Flow
- Default credentials: admin/changeme (must be changed)
- Session-based auth with Flask sessions
- `@login_required` decorator protects endpoints
- Passwords hashed with Werkzeug security

### WebSocket Events (via Flask-SocketIO)
- `setup_status`: Setup wizard progress
- `system_status`: Real-time system health
- `spotify_status`: Playback state updates

## Bluetooth Audio Features

### Backend Bluetooth Manager (`bluetooth_manager.py`)
- Device discovery and scanning
- Pairing and connection management
- Audio output routing (PulseAudio/ALSA)
- Adapter control (discoverable/pairable modes)
- Paired device management

### Bluetooth API Endpoints
```
GET  /api/bluetooth/adapter         # Get adapter info
POST /api/bluetooth/scan            # Scan for devices
GET  /api/bluetooth/paired          # List paired devices
GET  /api/bluetooth/connected       # List connected devices
POST /api/bluetooth/pair/:mac       # Pair with device
POST /api/bluetooth/connect/:mac    # Connect to device
POST /api/bluetooth/disconnect/:mac # Disconnect device
DELETE /api/bluetooth/remove/:mac   # Remove paired device
POST /api/bluetooth/discoverable/on # Enable discovery
POST /api/bluetooth/discoverable/off # Disable discovery
```

### Frontend Bluetooth Component
- `BluetoothManager.tsx`: Full UI for Bluetooth management
- Device scanning with visual feedback
- Paired device management
- Connect/disconnect controls
- Audio output selection

## Configuration Files

### Environment Variables
```bash
SECRET_KEY          # Flask session secret
ADMIN_USER          # Admin username (default: admin)
ADMIN_PASSWORD      # Admin password (default: changeme)
HOST_OS            # Target OS (raspbian, ubuntu, etc.)
```

### Persistent Data
- `/app/data/config.json`: Main configuration
- `/app/data/setup_status.json`: Setup wizard state
- `/app/config/spotifyd.conf`: Spotify daemon config

## Important Notes

- **Spotify Premium Required**: Free accounts will NOT work due to API limitations
- **Default Port**: 8080 (changed from 80 for non-root operation)
- **Network Mode**: Uses host network for audio compatibility
- **Privileged Mode**: Required for system modifications during setup
- **Health Check**: Available at `/health` endpoint
- **Docker Group**: Installation script automatically adds user to docker group for non-root access
- **Bluetooth**: Requires bluez and pulseaudio-module-bluetooth for audio routing

## Testing Approach

### Frontend Tests
```bash
cd frontend
npm test                        # Run all tests
npm test -- --coverage         # With coverage report
```

### Backend Tests
```bash
cd backend
python -m pytest               # If tests exist
# Manual testing with curl:
curl http://localhost:8080/health
curl -X POST http://localhost:8080/api/login -d '{"username":"admin","password":"changeme"}'
```

### Docker Health Check
```bash
docker inspect spotify-kids-manager --format='{{.State.Health.Status}}'
```

## Common Issues & Solutions

1. **Port 8080 in use**: Check with `sudo lsof -i :8080`, kill process or change port
2. **Spotifyd fails**: Verify Premium account, check username (not email!)
3. **No audio**: Run `speaker-test -c 2`, check `aplay -l`, verify ALSA/PulseAudio
4. **Frontend not loading**: Ensure `npm run build` completed, check nginx logs
5. **Container won't start**: Check `docker logs spotify-kids-manager`, verify Docker daemon

## Development Workflow

1. **Frontend changes**: Edit in `/frontend/src/`, test with `npm start`, build for production
2. **Backend changes**: Edit `/backend/`, restart Flask or rebuild container
3. **Docker changes**: Modify Dockerfile, rebuild with `docker-compose build`
4. **Testing**: Use the web interface at `http://localhost:8080`
5. **Deployment**: Push changes, run install script on target device