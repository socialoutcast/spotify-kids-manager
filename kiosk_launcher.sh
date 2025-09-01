#!/bin/bash

# Spotify Kids Player Kiosk Mode Launcher
# This script launches Chromium in kiosk mode displaying the web player

# Change to a directory the spotify-kids user has access to
cd /opt/spotify-kids || cd /tmp

# Wait for network to be ready
sleep 10

# Auto-detect the display
if [ -z "$DISPLAY" ]; then
    # Find the active X display
    for display in 0 1 2; do
        if [ -S /tmp/.X11-unix/X${display} ]; then
            export DISPLAY=:${display}
            echo "Using display $DISPLAY"
            break
        fi
    done
fi

# Try to get X authorization if needed
if [ -f /home/spotify-kids/.Xauthority ]; then
    export XAUTHORITY=/home/spotify-kids/.Xauthority
fi

# Disable screen blanking and power management
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true

# Hide mouse cursor after 0.1 seconds of inactivity
unclutter -idle 0.1 2>/dev/null &

# Remove any existing chromium preferences that might interfere
rm -rf /home/spotify-kids/.config/chromium/Singleton*

# Launch Chromium in kiosk mode
# --kiosk: Full screen mode, no browser UI
# --noerrdialogs: No error dialogs
# --disable-infobars: No info bars
# --disable-session-crashed-bubble: No crash restore bubble
# --disable-translate: No translation bar
# --no-first-run: Skip first run setup
# --fast: Fast startup
# --fast-start: Fast tab/window startup
# --disable-features=TranslateUI: Disable translate feature
# --app: Run as an app (removes navigation)
# --window-position=0,0: Position at top-left
# --window-size: Set to screen size (will be overridden by kiosk mode)
# --disable-pinch: Disable pinch zoom
# --overscroll-history-navigation=0: Disable swipe navigation

echo "Starting Chromium in kiosk mode on display $DISPLAY"

# Wait for the web player to be ready
until curl -s http://localhost:5000 > /dev/null 2>&1; do
    echo "Waiting for web player to be ready..."
    sleep 2
done

echo "Web player is ready, launching browser"

while true; do
    # Launch chromium - try with different options if it fails
    chromium-browser \
        --kiosk \
        --noerrdialogs \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-translate \
        --no-first-run \
        --fast \
        --fast-start \
        --disable-features=TranslateUI \
        --check-for-update-interval=31536000 \
        --disable-pinch \
        --overscroll-history-navigation=0 \
        --disable-component-update \
        --autoplay-policy=no-user-gesture-required \
        --window-position=0,0 \
        --user-data-dir=/home/spotify-kids/.config/chromium-kiosk \
        "http://localhost:5000" 2>/dev/null || \
    chromium-browser \
        --kiosk \
        --no-sandbox \
        --disable-dev-shm-usage \
        --disable-gpu \
        --disable-software-rasterizer \
        --user-data-dir=/home/spotify-kids/.config/chromium-kiosk \
        "http://localhost:5000" 2>/dev/null
    
    # If browser crashes or is somehow closed, wait and restart
    echo "Browser closed or crashed, restarting in 5 seconds..."
    sleep 5
done