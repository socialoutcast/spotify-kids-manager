#!/bin/bash

# Spotify Kids Manager - Clear Setup Message
# Removes the setup instructions from the display after setup is complete

echo "Clearing setup message from display..."

# Kill any browsers showing the setup page
pkill -f "chromium.*spotify-setup-display" 2>/dev/null
pkill -f "firefox.*spotify-setup-display" 2>/dev/null
pkill -f "midori.*spotify-setup-display" 2>/dev/null
pkill -f "show-setup-display" 2>/dev/null

# Kill X server if it was started just for display
pkill -f "xinit.*spotify-xinitrc" 2>/dev/null

# Stop and disable the setup display service
systemctl stop spotify-setup-display.service 2>/dev/null || true
systemctl disable spotify-setup-display.service 2>/dev/null || true

# Remove the service file
rm -f /etc/systemd/system/spotify-setup-display.service
rm -f /etc/systemd/system/getty@tty1.service.d/spotify-setup.conf

# Remove temporary files
rm -f /tmp/spotify-setup-display.html
rm -f /tmp/spotify-xinitrc

# Reload systemd
systemctl daemon-reload

# If on console, show completion message
if [ -e /dev/tty1 ] && [ ! -n "$SSH_CONNECTION" ]; then
    # Create a simple completion HTML
    cat > /tmp/setup-complete.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {
            margin: 0;
            padding: 0;
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
        }
        .message {
            text-align: center;
            animation: fadeIn 1s ease-in;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: scale(0.9); }
            to { opacity: 1; transform: scale(1); }
        }
        h1 { font-size: 4em; margin-bottom: 20px; }
        p { font-size: 1.5em; opacity: 0.9; }
        .checkmark {
            width: 100px;
            height: 100px;
            margin: 0 auto 30px;
            background: white;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .checkmark svg {
            width: 60px;
            height: 60px;
            stroke: #4caf50;
            stroke-width: 3;
            fill: none;
            animation: draw 0.5s ease-in-out;
        }
        @keyframes draw {
            from { stroke-dasharray: 0 100; }
            to { stroke-dasharray: 100 0; }
        }
    </style>
</head>
<body>
    <div class="message">
        <div class="checkmark">
            <svg viewBox="0 0 52 52">
                <path d="M14 27l7 7 16-16" stroke-dasharray="100" stroke-dashoffset="0"/>
            </svg>
        </div>
        <h1>Setup Complete!</h1>
        <p>Spotify Kids Manager is ready to use</p>
    </div>
</body>
</html>
EOF
    
    # Try to display completion message
    if [ -n "$DISPLAY" ] || command -v xinit &> /dev/null; then
        # Show completion for 5 seconds then exit
        if command -v chromium-browser &> /dev/null; then
            timeout 5 chromium-browser --kiosk --app="file:///tmp/setup-complete.html" 2>/dev/null &
        elif command -v chromium &> /dev/null; then
            timeout 5 chromium --kiosk --app="file:///tmp/setup-complete.html" 2>/dev/null &
        fi
    else
        # Console message
        clear > /dev/tty1 2>/dev/null
        echo "" > /dev/tty1
        echo "  ✓ Setup Complete!" > /dev/tty1
        echo "" > /dev/tty1
        echo "  Spotify Kids Manager is ready to use" > /dev/tty1
    fi
fi

echo "Setup message cleared successfully"