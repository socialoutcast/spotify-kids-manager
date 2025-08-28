#!/bin/bash
#
# Hotfix to make LCD show Spotify player instead of admin panel
#

echo "Applying LCD hotfix..."

# Kill current browser showing admin panel
sudo pkill -f chromium

# Create the proper web player startup script
sudo cat > /opt/spotify-terminal/scripts/start-web-player.sh <<'EOF'
#!/bin/bash

export DISPLAY=:0
LOG_FILE="/opt/spotify-terminal/data/web-player.log"

echo "[$(date)] Starting Spotify player on port 8888..." >> "$LOG_FILE"

# Kill any admin panel that might be running
pkill -f "app.py"

# Start ONLY the Spotify player (NOT the admin panel)
cd /opt/spotify-terminal/web
if [ -f spotify_server.py ]; then
    python3 spotify_server.py >> "$LOG_FILE" 2>&1 &
else
    echo "[$(date)] ERROR: spotify_server.py not found, downloading..." >> "$LOG_FILE"
    wget -q -O spotify_server.py https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/spotify_server.py
    wget -q -O player.html https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/player.html
    wget -q -O player.js https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/player.js
    python3 spotify_server.py >> "$LOG_FILE" 2>&1 &
fi

sleep 3

# Launch browser pointing to PLAYER port, not admin port
chromium-browser \
    --kiosk \
    --no-first-run \
    --noerrdialogs \
    --disable-infobars \
    --app=http://localhost:8888 \
    2>/dev/null &

echo "[$(date)] Browser launched on port 8888" >> "$LOG_FILE"
EOF

sudo chmod +x /opt/spotify-terminal/scripts/start-web-player.sh

# Update the touchscreen startup to use correct script
sudo cat > /opt/spotify-terminal/scripts/start-touchscreen.sh <<'EOF'
#!/bin/bash
export DISPLAY=:0
# Just launch the web player, nothing else
exec /opt/spotify-terminal/scripts/start-web-player.sh
EOF

sudo chmod +x /opt/spotify-terminal/scripts/start-touchscreen.sh

# Restart the display
echo "Restarting display with Spotify player..."
sudo pkill -u spotify-kids
sleep 2

# The auto-login will restart it, or manually restart:
sudo su - spotify-kids -c "DISPLAY=:0 /opt/spotify-terminal/scripts/start-web-player.sh" &

echo "Hotfix applied! The LCD should now show the Spotify player on port 8888"
echo "Check logs at: /opt/spotify-terminal/data/web-player.log"