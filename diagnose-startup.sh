#!/bin/bash
#
# Spotify Kids Manager - Startup Diagnostics
# Checks why the web player isn't starting properly
#

echo "============================================"
echo "Spotify Kids Manager - Startup Diagnostics"
echo "============================================"
echo ""

# Check if scripts exist
echo "=== Checking Scripts ==="
for script in start-touchscreen.sh start-web-player.sh spotify-client.sh; do
    if [ -f "/opt/spotify-terminal/scripts/$script" ]; then
        echo "✓ /opt/spotify-terminal/scripts/$script exists"
        ls -la "/opt/spotify-terminal/scripts/$script"
    else
        echo "✗ /opt/spotify-terminal/scripts/$script missing!"
    fi
done
echo ""

# Check if web files exist
echo "=== Checking Web Files ==="
for file in spotify_server.py player.html player.js app.py; do
    if [ -f "/opt/spotify-terminal/web/$file" ]; then
        echo "✓ /opt/spotify-terminal/web/$file exists"
        ls -la "/opt/spotify-terminal/web/$file"
    else
        echo "✗ /opt/spotify-terminal/web/$file missing!"
    fi
done
echo ""

# Check if Python modules are installed
echo "=== Checking Python Modules ==="
for module in flask flask_cors spotipy; do
    if python3 -c "import $module" 2>/dev/null; then
        echo "✓ Python module $module is installed"
    else
        echo "✗ Python module $module is NOT installed!"
    fi
done
echo ""

# Check if processes are running
echo "=== Checking Running Processes ==="
echo "Chromium processes:"
ps aux | grep -i chromium | grep -v grep || echo "  None running"
echo ""
echo "Python web servers:"
ps aux | grep -E "spotify_server\.py|app\.py" | grep -v grep || echo "  None running"
echo ""
echo "X server:"
ps aux | grep Xorg | grep -v grep || echo "  Not running"
echo ""

# Check ports
echo "=== Checking Network Ports ==="
echo "Port 8888 (Spotify player):"
ss -tln | grep :8888 || echo "  Not listening"
echo "Port 8080 (Admin panel via nginx):"
ss -tln | grep :8080 || echo "  Not listening"
echo "Port 5001 (Admin panel direct):"
ss -tln | grep :5001 || echo "  Not listening"
echo ""

# Check recent errors
echo "=== Recent Errors in Logs ==="
if [ -f /opt/spotify-terminal/data/login.log ]; then
    echo "Last 10 lines of login.log:"
    tail -10 /opt/spotify-terminal/data/login.log
else
    echo "No login.log found"
fi
echo ""

if [ -f /opt/spotify-terminal/data/web-player.log ]; then
    echo "Last 10 lines of web-player.log:"
    tail -10 /opt/spotify-terminal/data/web-player.log
else
    echo "No web-player.log found"
fi
echo ""

# Check systemd service
echo "=== Systemd Service Status ==="
systemctl status spotify-web-admin --no-pager 2>/dev/null || echo "Service not found or not running"
echo ""

# Check display
echo "=== Display Configuration ==="
echo "DISPLAY variable: $DISPLAY"
echo "X authority: $XAUTHORITY"
if [ -n "$DISPLAY" ]; then
    xdpyinfo 2>/dev/null | head -5 || echo "Cannot get display info"
fi
echo ""

# Test Python scripts
echo "=== Testing Python Scripts ==="
if [ -f /opt/spotify-terminal/web/spotify_server.py ]; then
    echo "Testing spotify_server.py syntax..."
    python3 -m py_compile /opt/spotify-terminal/web/spotify_server.py 2>&1 && echo "  Syntax OK" || echo "  Syntax ERROR!"
fi

if [ -f /opt/spotify-terminal/web/app.py ]; then
    echo "Testing app.py syntax..."
    python3 -m py_compile /opt/spotify-terminal/web/app.py 2>&1 && echo "  Syntax OK" || echo "  Syntax ERROR!"
fi
echo ""

# Check for crash dumps
echo "=== Checking for Crash Information ==="
if [ -f /var/log/syslog ]; then
    echo "Recent crashes in syslog:"
    grep -i "segfault\|error\|crash" /var/log/syslog | tail -5 || echo "  No crashes found"
fi
echo ""

echo "============================================"
echo "Diagnostics complete!"
echo ""
echo "Common issues to check:"
echo "1. Missing Python modules - install with pip3"
echo "2. Scripts not executable - run chmod +x"
echo "3. Port already in use - kill existing processes"
echo "4. X server not started - check display settings"
echo "============================================"