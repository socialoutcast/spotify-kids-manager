#!/bin/bash
#
# Spotify Kids Manager - Quick Fix Script
# Diagnoses and fixes common startup issues
#

echo "============================================"
echo "Spotify Kids Manager - Quick Fix"
echo "============================================"
echo ""

# Check what's actually running
echo "Checking processes..."
echo ""

# Check for Python servers
echo "Python servers:"
ps aux | grep -E "spotify_server\.py|app\.py" | grep -v grep || echo "  None running - THIS IS THE PROBLEM!"
echo ""

# Check ports
echo "Port 8888 (Spotify player):"
ss -tln | grep :8888 || echo "  Not listening - Server not started!"
echo ""

# Check if files exist
echo "Checking critical files..."
if [ -f /opt/spotify-terminal/web/spotify_server.py ]; then
    echo "✓ spotify_server.py exists"
else
    echo "✗ spotify_server.py missing - copying from project..."
    sudo mkdir -p /opt/spotify-terminal/web
    sudo cp /home/bkrause/Projects/spotify-kids-manager/web/*.py /opt/spotify-terminal/web/
    sudo cp /home/bkrause/Projects/spotify-kids-manager/web/*.html /opt/spotify-terminal/web/
    sudo cp /home/bkrause/Projects/spotify-kids-manager/web/*.js /opt/spotify-terminal/web/
    sudo chown -R spotify-kids:spotify-kids /opt/spotify-terminal/web
fi
echo ""

# Check Python modules
echo "Checking Python modules..."
missing_modules=""
for module in flask flask_cors spotipy; do
    if ! python3 -c "import $module" 2>/dev/null; then
        echo "✗ Missing module: $module"
        missing_modules="$missing_modules $module"
    else
        echo "✓ $module installed"
    fi
done

if [ ! -z "$missing_modules" ]; then
    echo ""
    echo "Installing missing modules..."
    sudo pip3 install $missing_modules
fi
echo ""

# Try to start the server manually
echo "Starting Spotify server manually..."
cd /opt/spotify-terminal/web
if [ -f spotify_server.py ]; then
    # Kill any existing
    pkill -f spotify_server.py 2>/dev/null
    sleep 1
    
    # Start it
    echo "Starting on port 8888..."
    python3 spotify_server.py > /tmp/spotify-server.log 2>&1 &
    SERVER_PID=$!
    
    sleep 3
    
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo "✓ Server started successfully (PID: $SERVER_PID)"
        
        # Check if responding
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8888" | grep -q "200\|302"; then
            echo "✓ Server is responding on port 8888!"
        else
            echo "✗ Server not responding, checking logs..."
            tail -20 /tmp/spotify-server.log
        fi
    else
        echo "✗ Server failed to start, checking logs..."
        tail -20 /tmp/spotify-server.log
    fi
else
    echo "✗ spotify_server.py not found!"
fi
echo ""

# Launch browser if not running
if ! pgrep -f chromium > /dev/null; then
    echo "Launching browser..."
    export DISPLAY=:0
    chromium-browser \
        --kiosk \
        --no-first-run \
        --noerrdialogs \
        --disable-infobars \
        --app=http://localhost:8888 \
        2>/dev/null &
    echo "✓ Browser launched"
else
    echo "✓ Browser already running"
fi
echo ""

echo "============================================"
echo "Quick fix complete!"
echo ""
echo "If the server is running, the LCD should now"
echo "show the Spotify player interface."
echo ""
echo "Check /tmp/spotify-server.log for any errors"
echo "============================================"