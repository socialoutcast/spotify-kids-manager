#!/bin/bash
#
# Spotify Kids Web Player Launcher
# Starts the web server and opens browser in kiosk mode
#

export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Determine log directory - prefer system path but fallback to user directory
LOG_DIR="/opt/spotify-terminal/data"
if ! mkdir -p "$LOG_DIR" 2>/dev/null || ! touch "$LOG_DIR/test" 2>/dev/null; then
    # Fallback to user directory if system directory isn't writable
    LOG_DIR="$HOME/.spotify-terminal/data"
    mkdir -p "$LOG_DIR" 2>/dev/null || true
fi
rm -f "$LOG_DIR/test" 2>/dev/null || true

LOG_FILE="$LOG_DIR/web-player.log"

# Ensure log file exists and is writable
if ! touch "$LOG_FILE" 2>/dev/null; then
    # If still can't create log file, use /tmp as final fallback
    LOG_FILE="/tmp/spotify-web-player.log"
    touch "$LOG_FILE" 2>/dev/null || true
fi
chmod 666 "$LOG_FILE" 2>/dev/null || true

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting Spotify Kids Web Player..."

# Ensure Python dependencies are installed
if ! python3 -c "import flask; import spotipy" 2>/dev/null; then
    log "Installing missing Python dependencies..."
    pip3 install --break-system-packages flask flask-cors spotipy 2>/dev/null || \
    pip3 install flask flask-cors spotipy 2>/dev/null || \
    python3 -m pip install flask flask-cors spotipy 2>/dev/null || {
        log "ERROR: Failed to install Python dependencies"
        exit 1
    }
fi

# Check if device is locked
if [ -f /opt/spotify-terminal/data/device.lock ]; then
    LOCKED=true
    log "Device is locked - restricted mode"
else
    LOCKED=false
    log "Device is unlocked"
fi

# Kill any existing instances
pkill -f spotify_server.py 2>/dev/null
pkill -f app.py 2>/dev/null  # Kill admin panel if running
pkill -f chromium 2>/dev/null
sleep 2

# Make sure nothing is using port 8888
if lsof -Pi :8888 -sTCP:LISTEN -t >/dev/null ; then
    log "Port 8888 is in use, killing process..."
    lsof -Pi :8888 -sTCP:LISTEN -t | xargs kill -9 2>/dev/null
    sleep 1
fi

# Determine web directory - check production first, then development
WEB_DIR=""
if [ -d "/opt/spotify-terminal/web" ]; then
    WEB_DIR="/opt/spotify-terminal/web"
elif [ -f "$(dirname "$0")/../web/spotify_server.py" ]; then
    # Development environment - script is in scripts/ dir, web files in ../web/
    WEB_DIR="$(cd "$(dirname "$0")/../web" && pwd)"
else
    log "ERROR: Cannot find web directory with spotify_server.py"
    exit 1
fi

log "Using web directory: $WEB_DIR"

# Start the Spotify player server (not admin panel)
log "Starting Spotify web player server on port 8888..."
cd "$WEB_DIR" || {
    log "ERROR: Cannot change to web directory: $WEB_DIR"
    exit 1
}

# Check if web files exist, download if missing
if [ ! -f spotify_server.py ]; then
    log "Web player files missing, downloading from GitHub..."
    for file in spotify_server.py player.html player.js; do
        wget -q -O "$file" \
            "https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/web/$file" || {
            log "ERROR: Failed to download $file"
            exit 1
        }
    done
    chmod 644 *.py *.html *.js 2>/dev/null || true
fi

if [ -f spotify_server.py ]; then
    python3 spotify_server.py >> "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    log "Spotify player server started with PID: $SERVER_PID"
else
    log "ERROR: spotify_server.py not found!"
    exit 1
fi

# Wait for server to start
sleep 3

# Check if running with X server (graphical mode)
if [ -n "$DISPLAY" ] && xset q &>/dev/null; then
    log "X server detected, starting browser in kiosk mode..."
    
    # Configure touchscreen if available
    if xinput list 2>/dev/null | grep -qi touch; then
        log "Touchscreen detected, configuring input..."
        # Enable touch events
        xinput set-prop "$(xinput list --name-only | grep -i touch | head -1)" "libinput Tapping Enabled" 1 2>/dev/null || true
    fi
    
    # Hide mouse cursor
    unclutter -idle 0.1 -root &
    
    # Disable screen blanking
    xset s off
    xset -dpms
    xset s noblank
    
    # Start window manager (minimal)
    openbox &
    WM_PID=$!
    sleep 1
    
    # Launch Chromium in kiosk mode
    log "Launching Chromium in kiosk mode..."
    
    CHROME_ARGS=(
        --kiosk
        --no-first-run
        --noerrdialogs
        --disable-infobars
        --disable-features=TranslateUI
        --disable-pinch
        --overscroll-history-navigation=disabled
        --disable-dev-tools
        --check-for-update-interval=31536000
        --disable-component-update
        --autoplay-policy=no-user-gesture-required
        --window-size=1920,1080
        --window-position=0,0
        --disable-notifications
        --disable-cloud-import
        --disable-signin-promo
        --disable-translate
        --disable-background-timer-throttling
        --disable-backgrounding-occluded-windows
        --disable-renderer-backgrounding
        --force-color-profile=srgb
    )
    
    # Add touch-specific flags if touchscreen detected
    if xinput list 2>/dev/null | grep -qi touch; then
        CHROME_ARGS+=(
            --touch-events=enabled
            --enable-touch-events
            --enable-touch-drag-drop
            --enable-touchview
        )
    fi
    
    # Add the URL (Spotify player on non-standard port)
    CHROME_ARGS+=("http://localhost:8888")
    
    # Check if locked and add restrictions
    if [ "$LOCKED" = true ]; then
        CHROME_ARGS+=(
            --disable-context-menu
            --disable-dev-shm-usage
            --disable-keyboard
        )
    fi
    
    # Launch browser
    chromium-browser "${CHROME_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
    BROWSER_PID=$!
    log "Browser launched with PID: $BROWSER_PID"
    
    # Monitor processes (but don't restart browser to prevent flashing)
    while true; do
        # Check if server is still running
        if ! kill -0 $SERVER_PID 2>/dev/null; then
            log "Server died, restarting..."
            cd "$WEB_DIR" || {
                log "ERROR: Cannot change to web directory for restart: $WEB_DIR"
                break
            }
            python3 spotify_server.py >> "$LOG_FILE" 2>&1 &
            SERVER_PID=$!
        fi
        
        # Don't auto-restart browser to prevent flashing
        # Just check if it's still running
        if ! kill -0 $BROWSER_PID 2>/dev/null; then
            log "Browser closed"
            # If device is locked, restart it
            if [ "$LOCKED" = true ]; then
                log "Device locked, restarting browser..."
                sleep 2
                chromium-browser "${CHROME_ARGS[@]}" >> "$LOG_FILE" 2>&1 &
                BROWSER_PID=$!
            else
                # Exit cleanly if browser closes and device not locked
                break
            fi
        fi
        
        sleep 10
    done
    
else
    log "No X server detected, running in headless mode"
    log "Web interface available at http://$(hostname -I | awk '{print $1}'):8888"
    
    # Just keep the server running
    wait $SERVER_PID
fi