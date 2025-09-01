#!/bin/bash

# Spotify Kids Player Kiosk Mode Launcher
# This script launches Chromium in kiosk mode displaying the web player

# Wait for network to be ready
sleep 10

# Disable screen blanking and power management
export DISPLAY=:0
xset s off
xset -dpms
xset s noblank

# Hide mouse cursor after 0.1 seconds of inactivity
unclutter -idle 0.1 &

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

while true; do
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
        --no-sandbox \
        --disable-dev-shm-usage \
        --disable-gpu \
        --disable-software-rasterizer \
        --disable-features=TouchpadOverscrollHistoryNavigation \
        --app="http://localhost:5000"
    
    # If browser crashes or is somehow closed, wait and restart
    sleep 5
done