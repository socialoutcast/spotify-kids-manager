#!/bin/bash
#
# Native Spotify Player Launcher
# Replaces web-based player with native Python tkinter application
#

# Kill any existing processes
echo "Stopping existing services..."
pkill -f "app.py" 2>/dev/null
pkill -f "spotify_server.py" 2>/dev/null
pkill -f "spotify_player.py" 2>/dev/null
pkill -f "python.*8888" 2>/dev/null
pkill -f "chromium" 2>/dev/null

# Kill anything on relevant ports
lsof -ti:5001 | xargs kill -9 2>/dev/null  # Admin panel port
lsof -ti:8888 | xargs kill -9 2>/dev/null  # Player port

sleep 2

# Set environment variables
export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Ensure directories exist
mkdir -p /opt/spotify-terminal/config
mkdir -p /opt/spotify-terminal/data

# Set configuration base directory (fallback to home if /opt not writable)
if [ ! -w "/opt" ]; then
    export SPOTIFY_BASE_DIR="$HOME/.spotify-terminal"
    mkdir -p "$HOME/.spotify-terminal/config"
    mkdir -p "$HOME/.spotify-terminal/data"
    echo "Using home directory for configuration: $SPOTIFY_BASE_DIR"
else
    export SPOTIFY_BASE_DIR="/opt/spotify-terminal"
    echo "Using system directory for configuration: $SPOTIFY_BASE_DIR"
fi

# Change to the application directory
cd /home/bkrause/Projects/spotify-kids-manager || {
    echo "Error: Could not find application directory"
    exit 1
}

# Check if the native player exists
if [ ! -f spotify_player.py ]; then
    echo "Error: spotify_player.py not found in $(pwd)"
    exit 1
fi

echo "Starting Native Spotify Player..."
echo "Configuration directory: $SPOTIFY_BASE_DIR"
echo "Display: $DISPLAY"

# Check if X server is available
if ! xset q &>/dev/null; then
    echo "Warning: No X server detected. Player requires a display."
    echo "The player will attempt to start but may fail without a GUI environment."
fi

# Check for touchscreen device (for fullscreen mode)
if [ -e "/dev/input/touchscreen" ]; then
    echo "Touchscreen device detected - will run in fullscreen mode"
else
    echo "No touchscreen device - will run in windowed mode"
fi

# Start the native player
echo "Launching spotify_player.py..."
python3 spotify_player.py 2>&1 | tee /tmp/spotify-native-player.log &
PLAYER_PID=$!

echo "Native Spotify Player started with PID: $PLAYER_PID"
echo "Log output: /tmp/spotify-native-player.log"

# Wait a bit to check if it started successfully
sleep 5

if ps -p $PLAYER_PID > /dev/null; then
    echo "✓ Native player is running successfully"
    echo "Access admin panel at: http://localhost:5001"
    
    # Keep the script running to monitor the player
    wait $PLAYER_PID
    echo "Native player has exited"
else
    echo "✗ Native player failed to start"
    echo "Check log file: /tmp/spotify-native-player.log"
    cat /tmp/spotify-native-player.log
    exit 1
fi