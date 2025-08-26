#!/bin/bash

# Spotify Kids Manager - Show Setup Display
# Displays the setup instructions as a fullscreen webpage

INSTALL_DIR="/opt/spotify-kids-manager"
HTML_FILE="${INSTALL_DIR}/scripts/setup-display.html"
TEMP_HTML="/tmp/spotify-setup-display.html"

# Get IP address
get_ip_address() {
    IP=$(hostname -I 2>/dev/null | cut -d' ' -f1)
    if [ -z "$IP" ]; then
        IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+')
    fi
    if [ -z "$IP" ]; then
        IP=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 | cut -d: -f2 | awk '{print $1}')
    fi
    echo ${IP:-"Unable to detect IP"}
}

IP_ADDRESS=$(get_ip_address)

# Create temporary HTML with actual IP address
if [ -f "$HTML_FILE" ]; then
    cp "$HTML_FILE" "$TEMP_HTML"
else
    # Fallback to container path
    HTML_FILE="/app/scripts/setup-display.html"
    if [ -f "$HTML_FILE" ]; then
        cp "$HTML_FILE" "$TEMP_HTML"
    else
        echo "HTML file not found!"
        exit 1
    fi
fi

# Replace IP address placeholder
sed -i "s/IP_ADDRESS_PLACEHOLDER/${IP_ADDRESS}/g" "$TEMP_HTML"

# Function to kill any existing display
kill_display() {
    pkill -f chromium 2>/dev/null
    pkill -f chromium-browser 2>/dev/null
    pkill -f firefox 2>/dev/null
    pkill -f midori 2>/dev/null
    pkill -f surf 2>/dev/null
    pkill -f xinit 2>/dev/null
}

# Kill any existing display first
kill_display

# Check what's available and use it
if [ -n "$DISPLAY" ]; then
    # X11 is running, use a browser
    echo "X11 detected, launching browser..."
    
    # Try different browsers in order of preference
    if command -v chromium-browser &> /dev/null; then
        chromium-browser --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
            --disable-features=TranslateUI --disable-translate \
            --no-first-run --disable-features=Translate \
            --app="file://${TEMP_HTML}" &> /dev/null &
            
    elif command -v chromium &> /dev/null; then
        chromium --kiosk --noerrdialogs --disable-infobars --disable-session-crashed-bubble \
            --disable-features=TranslateUI --disable-translate \
            --no-first-run --disable-features=Translate \
            --app="file://${TEMP_HTML}" &> /dev/null &
            
    elif command -v firefox &> /dev/null; then
        firefox --kiosk "file://${TEMP_HTML}" &> /dev/null &
        
    elif command -v midori &> /dev/null; then
        midori -e Fullscreen -a "file://${TEMP_HTML}" &> /dev/null &
        
    else
        echo "No supported browser found"
    fi
    
elif [ -z "$SSH_CONNECTION" ]; then
    # No X11, we're on console - try to start minimal X with browser
    echo "No X11 detected, starting minimal display..."
    
    # Check if we can start X
    if command -v xinit &> /dev/null && command -v X &> /dev/null; then
        
        # Create a simple xinitrc
        cat > /tmp/spotify-xinitrc << 'EOF'
#!/bin/sh
xset s off
xset -dpms
xset s noblank

# Hide cursor after 1 second
unclutter -idle 1 &

# Try to launch browser
if command -v chromium-browser &> /dev/null; then
    exec chromium-browser --kiosk --noerrdialogs --disable-infobars \
        --disable-session-crashed-bubble --disable-features=TranslateUI \
        --disable-translate --no-first-run --disable-features=Translate \
        --app="file://TEMP_HTML_PLACEHOLDER"
elif command -v chromium &> /dev/null; then
    exec chromium --kiosk --noerrdialogs --disable-infobars \
        --disable-session-crashed-bubble --disable-features=TranslateUI \
        --disable-translate --no-first-run --disable-features=Translate \
        --app="file://TEMP_HTML_PLACEHOLDER"
elif command -v midori &> /dev/null; then
    exec midori -e Fullscreen -a "file://TEMP_HTML_PLACEHOLDER"
elif command -v surf &> /dev/null; then
    exec surf -F "file://TEMP_HTML_PLACEHOLDER"
else
    # Last resort - display with basic tools
    exec xmessage -center "Spotify Kids Manager Setup
    
Visit: http://IP_ADDRESS_PLACEHOLDER:8080

Username: admin
Password: changeme

Please change the password after first login!"
fi
EOF
        
        # Replace placeholders
        sed -i "s|TEMP_HTML_PLACEHOLDER|${TEMP_HTML}|g" /tmp/spotify-xinitrc
        sed -i "s|IP_ADDRESS_PLACEHOLDER|${IP_ADDRESS}|g" /tmp/spotify-xinitrc
        chmod +x /tmp/spotify-xinitrc
        
        # Try to start X on the first available VT
        if [ -w /dev/tty1 ]; then
            xinit /tmp/spotify-xinitrc -- :0 vt1 &> /dev/null &
        elif [ -w /dev/tty7 ]; then
            xinit /tmp/spotify-xinitrc -- :0 vt7 &> /dev/null &
        else
            xinit /tmp/spotify-xinitrc &> /dev/null &
        fi
        
    else
        echo "X server not available, falling back to console message"
        # Fall back to console display
        ${INSTALL_DIR}/scripts/display-setup-message.sh
    fi
else
    echo "SSH session detected, not starting display"
fi

# If running with --wait parameter, wait for input
if [ "$1" == "--wait" ]; then
    # Check if setup is complete periodically
    while true; do
        if [ -f "/app/data/setup_status.json" ] && grep -q '"setup_complete".*true' /app/data/setup_status.json 2>/dev/null; then
            echo "Setup complete, closing display"
            kill_display
            break
        elif [ -f "/opt/spotify-kids-manager/data/setup_status.json" ] && grep -q '"setup_complete".*true' /opt/spotify-kids-manager/data/setup_status.json 2>/dev/null; then
            echo "Setup complete, closing display"
            kill_display
            break
        fi
        sleep 10
    done
fi