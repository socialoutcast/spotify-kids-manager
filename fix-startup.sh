#!/bin/bash
#
# Fix the startup scripts on remote system
#

echo "Fixing startup scripts..."

# Create proper start-web-player.sh
sudo cat > /opt/spotify-terminal/scripts/start-web-player.sh <<'EOF'
#!/bin/bash
export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

LOG_FILE="/opt/spotify-terminal/data/web-player.log"
mkdir -p /opt/spotify-terminal/data
touch "$LOG_FILE"
chmod 666 "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

log "Starting Spotify Kids Web Player..."

# Kill any existing instances
pkill -f spotify_server.py 2>/dev/null
pkill -f chromium 2>/dev/null
sleep 2

# Copy files if missing
if [ ! -f /opt/spotify-terminal/web/spotify_server.py ]; then
    log "Copying web files from project..."
    sudo mkdir -p /opt/spotify-terminal/web
    sudo cp /home/bkrause/Projects/spotify-kids-manager/web/*.py /opt/spotify-terminal/web/ 2>/dev/null
    sudo cp /home/bkrause/Projects/spotify-kids-manager/web/*.html /opt/spotify-terminal/web/ 2>/dev/null  
    sudo cp /home/bkrause/Projects/spotify-kids-manager/web/*.js /opt/spotify-terminal/web/ 2>/dev/null
    sudo chown -R spotify-kids:spotify-kids /opt/spotify-terminal/web
fi

# Install missing Python modules if needed
for module in flask flask_cors spotipy; do
    if ! python3 -c "import $module" 2>/dev/null; then
        log "Installing missing module: $module"
        sudo pip3 install $module
    fi
done

# Start the Spotify player server
cd /opt/spotify-terminal/web
if [ -f spotify_server.py ]; then
    log "Starting server on port 8888..."
    python3 spotify_server.py >> "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    log "Server PID: $SERVER_PID"
    
    # Wait for server to be ready
    for i in {1..10}; do
        if curl -s -o /dev/null "http://localhost:8888"; then
            log "Server is ready!"
            break
        fi
        log "Waiting for server... ($i/10)"
        sleep 1
    done
else
    log "ERROR: spotify_server.py not found!"
fi

# Launch browser if display is available
if [ -n "$DISPLAY" ] && xset q &>/dev/null; then
    log "Launching browser..."
    
    # Disable screen blanking
    xset s off
    xset -dpms
    xset s noblank
    
    # Launch browser
    chromium-browser \
        --kiosk \
        --no-first-run \
        --noerrdialogs \
        --disable-infobars \
        --app=http://localhost:8888 \
        >> "$LOG_FILE" 2>&1 &
    
    BROWSER_PID=$!
    log "Browser PID: $BROWSER_PID"
    
    # Keep running
    wait $BROWSER_PID
else
    log "No display available, running headless"
    # Keep the server running
    wait $SERVER_PID
fi
EOF

sudo chmod +x /opt/spotify-terminal/scripts/start-web-player.sh
sudo chown spotify-kids:spotify-kids /opt/spotify-terminal/scripts/start-web-player.sh

echo "Fixed! Now restart the system or run:"
echo "sudo su - spotify-kids -c '/opt/spotify-terminal/scripts/start-web-player.sh'"