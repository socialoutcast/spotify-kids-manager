#!/bin/bash

# Spotify Kids Player Kiosk Mode Launcher
# This script launches Chromium in kiosk mode displaying the web player

# Set PulseAudio environment FIRST (before any exec redirects)
APP_USER_UID=$(id -u spotify-kids)
export PULSE_RUNTIME_PATH=/run/user/$APP_USER_UID
export XDG_RUNTIME_DIR=/run/user/$APP_USER_UID
export PULSE_SERVER=/run/user/$APP_USER_UID/pulse/native
export HOME=/home/spotify-kids

# Redirect all output to /dev/null to prevent terminal flashing
exec > /dev/null 2>&1

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

# Hide mouse cursor immediately for touchscreen
unclutter -idle 0 -root &

# Remove any existing chromium preferences that might interfere
rm -rf /home/spotify-kids/.config/chromium/Singleton*

# Wait for the web player to be ready
until curl -s http://localhost:5000 > /dev/null 2>&1; do
    sleep 2
done

# Kill any existing chromium instances first
pkill -f "chromium.*kiosk" 2>/dev/null || true
sleep 2

# Launch chromium - systemd will restart if it crashes
exec chromium-browser \
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
    "http://localhost:5000"