#!/bin/bash
#
# Complete Spotify Kids Manager System Launcher
# Starts both the native player and the admin panel
#

# Kill any existing processes
echo "Stopping existing services..."
pkill -f "app.py" 2>/dev/null
pkill -f "spotify_server.py" 2>/dev/null
pkill -f "spotify_player.py" 2>/dev/null
pkill -f "python.*5001" 2>/dev/null
pkill -f "python.*8888" 2>/dev/null
pkill -f "chromium" 2>/dev/null

# Kill anything on relevant ports
lsof -ti:5001 | xargs kill -9 2>/dev/null  # Admin panel port
lsof -ti:8888 | xargs kill -9 2>/dev/null  # Player port

sleep 3

# Set environment variables
export DISPLAY=:0
export HOME=/home/spotify-kids
export USER=spotify-kids

# Ensure directories exist
mkdir -p /opt/spotify-terminal/config
mkdir -p /opt/spotify-terminal/data

# Set configuration base directory
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

# Check required files
if [ ! -f spotify_player.py ]; then
    echo "Error: spotify_player.py not found"
    exit 1
fi

if [ ! -f web/app.py ]; then
    echo "Error: web/app.py (admin panel) not found"
    exit 1
fi

echo "Starting Complete Spotify Kids Manager System..."
echo "Configuration directory: $SPOTIFY_BASE_DIR"

# Start the admin panel first (runs on port 5001)
echo "Starting Admin Panel on port 5001..."
cd web
python3 app.py > /tmp/spotify-admin-panel.log 2>&1 &
ADMIN_PID=$!
cd ..

# Wait for admin panel to start
sleep 3

# Check if admin panel started
if ps -p $ADMIN_PID > /dev/null; then
    echo "✓ Admin panel started with PID: $ADMIN_PID"
else
    echo "✗ Admin panel failed to start"
    cat /tmp/spotify-admin-panel.log
    exit 1
fi

# Check if X server is available for GUI player
if xset q &>/dev/null; then
    echo "X server detected - starting native GUI player..."
    
    # Check for touchscreen device
    if [ -e "/dev/input/touchscreen" ]; then
        echo "Touchscreen device detected - will run in fullscreen mode"
    else
        echo "No touchscreen device - will run in windowed mode"
    fi
    
    # Start the native player
    echo "Starting Native Spotify Player..."
    python3 spotify_player.py > /tmp/spotify-native-player.log 2>&1 &
    PLAYER_PID=$!
    
    # Wait for player to start
    sleep 5
    
    if ps -p $PLAYER_PID > /dev/null; then
        echo "✓ Native player started with PID: $PLAYER_PID"
    else
        echo "✗ Native player failed to start"
        cat /tmp/spotify-native-player.log
        kill $ADMIN_PID 2>/dev/null
        exit 1
    fi
    
else
    echo "No X server detected - running admin panel only"
    echo "You can access the admin panel at: http://localhost:5001"
    PLAYER_PID=""
fi

# Display status
echo ""
echo "🎉 Spotify Kids Manager System Started Successfully!"
echo "======================================================"
echo "Admin Panel: http://localhost:5001"
if [ -n "$PLAYER_PID" ]; then
    echo "Native Player: Running with GUI"
else
    echo "Native Player: Not started (no display)"
fi
echo ""
echo "Log files:"
echo "  Admin Panel: /tmp/spotify-admin-panel.log"
if [ -n "$PLAYER_PID" ]; then
    echo "  Native Player: /tmp/spotify-native-player.log"
fi
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "Shutting down Spotify Kids Manager..."
    if [ -n "$PLAYER_PID" ]; then
        kill $PLAYER_PID 2>/dev/null
        echo "  Native player stopped"
    fi
    kill $ADMIN_PID 2>/dev/null
    echo "  Admin panel stopped"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Keep the script running and monitor processes
while true; do
    sleep 10
    
    # Check admin panel
    if ! ps -p $ADMIN_PID > /dev/null; then
        echo "⚠️  Admin panel has stopped unexpectedly"
        break
    fi
    
    # Check native player (if it was started)
    if [ -n "$PLAYER_PID" ] && ! ps -p $PLAYER_PID > /dev/null; then
        echo "⚠️  Native player has stopped unexpectedly"
        break
    fi
done

echo "One or more services have stopped. Shutting down..."
cleanup