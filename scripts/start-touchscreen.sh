#!/bin/bash
#
# Spotify Kids Touchscreen Startup Script
# Launches the web player interface in kiosk mode
#

LOG_FILE="/opt/spotify-terminal/data/login.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_message "Starting touchscreen interface..."

# Set environment
export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Wait for X to be ready
sleep 2

# Launch the web player
if [ -f /opt/spotify-terminal/scripts/start-web-player.sh ]; then
    log_message "Launching web player..."
    exec /opt/spotify-terminal/scripts/start-web-player.sh
else
    log_message "Web player script not found, launching directly..."
    
    # Start the web player directly
    cd /opt/spotify-terminal
    
    # Kill any existing instances
    pkill -f chromium 2>/dev/null
    pkill -f spotify_server.py 2>/dev/null
    sleep 1
    
    # Start the Spotify web server
    if [ -f /opt/spotify-terminal/web/spotify_server.py ]; then
        python3 /opt/spotify-terminal/web/spotify_server.py >> "$LOG_FILE" 2>&1 &
        SERVER_PID=$!
        log_message "Started Spotify server with PID: $SERVER_PID"
    elif [ -f /home/bkrause/Projects/spotify-kids-manager/web/spotify_server.py ]; then
        python3 /home/bkrause/Projects/spotify-kids-manager/web/spotify_server.py >> "$LOG_FILE" 2>&1 &
        SERVER_PID=$!
        log_message "Started Spotify server from project directory with PID: $SERVER_PID"
    else
        log_message "ERROR: spotify_server.py not found!"
        
        # Fallback: start admin panel
        if [ -f /opt/spotify-terminal/web/app.py ]; then
            python3 /opt/spotify-terminal/web/app.py >> "$LOG_FILE" 2>&1 &
            log_message "Started admin panel as fallback"
        fi
    fi
    
    # Wait for server to start
    sleep 5
    
    # Launch browser in kiosk mode
    chromium-browser \
        --kiosk \
        --no-first-run \
        --noerrdialogs \
        --disable-infobars \
        --disable-features=TranslateUI \
        --disable-pinch \
        --overscroll-history-navigation=disabled \
        --check-for-update-interval=31536000 \
        --autoplay-policy=no-user-gesture-required \
        --window-size=1920,1080 \
        --window-position=0,0 \
        --touch-events=enabled \
        --enable-touch-events \
        --enable-touch-drag-drop \
        --app=http://localhost:8888 \
        >> "$LOG_FILE" 2>&1 &
    
    BROWSER_PID=$!
    log_message "Browser launched with PID: $BROWSER_PID"
    
    # Keep running
    wait $BROWSER_PID
fi