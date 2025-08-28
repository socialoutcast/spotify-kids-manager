#!/bin/bash
#
# Simple Spotify Web Player Launcher
# Ensures only the player runs, not the admin panel
#

# Kill any existing web servers
pkill -f "app.py" 2>/dev/null
pkill -f "spotify_server.py" 2>/dev/null
pkill -f "python.*8888" 2>/dev/null
pkill -f "chromium" 2>/dev/null

# Kill anything on port 8888 (Spotify player port)
lsof -ti:8888 | xargs kill -9 2>/dev/null

sleep 2

# Set environment
export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Start ONLY the Spotify player server
cd /opt/spotify-terminal/web

# Make sure we have the player files
if [ ! -f player.html ] || [ ! -f spotify_server.py ]; then
    echo "Downloading player files..."
    wget -q -O player.html https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/player.html
    wget -q -O player.js https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/player.js
    wget -q -O spotify_server.py https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/spotify_server.py
    chmod +x spotify_server.py
fi

echo "Starting Spotify player server on port 8888..."
python3 spotify_server.py &
SERVER_PID=$!

# Wait for server to start
sleep 5

# Check if X server is available
if xset q &>/dev/null; then
    # Disable screen blanking
    xset s off
    xset -dpms
    xset s noblank
    
    # Hide cursor
    unclutter -idle 0.1 -root &
    
    # Launch browser in kiosk mode (single instance, no restart loop)
    chromium-browser \
        --kiosk \
        --no-first-run \
        --noerrdialogs \
        --disable-infobars \
        --disable-translate \
        --disable-features=TranslateUI \
        --check-for-update-interval=31536000 \
        --disable-component-update \
        --app=http://localhost:8888 \
        --window-position=0,0 \
        --disable-session-crashed-bubble \
        --disable-infobars \
        --disable-restore-session-state &
    
    BROWSER_PID=$!
    
    echo "Spotify player running on http://localhost:8888"
    echo "Browser PID: $BROWSER_PID, Server PID: $SERVER_PID"
    
    # Keep running
    wait $SERVER_PID
else
    echo "No display found, running in headless mode"
    echo "Access player at http://$(hostname -I | cut -d' ' -f1):8888"
    wait $SERVER_PID
fi