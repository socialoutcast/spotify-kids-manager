#!/bin/bash
#
# Fix Plymouth to properly quit after boot completes
#

if [[ $EUID -ne 0 ]]; then 
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "============================================"
echo "Fixing Plymouth to quit after X starts"
echo "============================================"
echo ""

# Remove the overly aggressive masking
echo "Re-enabling Plymouth quit services..."
systemctl unmask plymouth-quit.service 2>/dev/null
systemctl unmask plymouth-quit-wait.service 2>/dev/null

# Remove the persist service
systemctl disable plymouth-persist.service 2>/dev/null
rm -f /etc/systemd/system/plymouth-persist.service

# Create a better Plymouth quit service that waits for X
cat > /etc/systemd/system/plymouth-quit-on-x.service <<EOF
[Unit]
Description=Quit Plymouth when X server starts
After=multi-user.target
Wants=plymouth-quit.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'while ! pgrep -x "Xorg" > /dev/null; do sleep 1; done; sleep 2; /usr/bin/plymouth quit'
RemainAfterExit=yes
TimeoutSec=60

[Install]
WantedBy=graphical.target
EOF

systemctl enable plymouth-quit-on-x.service

# Update the getty override to properly transition
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/plymouth.conf <<EOF
[Unit]
After=plymouth-quit-on-x.service

[Service]
ExecStartPre=-/bin/bash -c 'if [ -f /run/plymouth/pid ]; then /usr/bin/plymouth quit; fi'
EOF

# Add Plymouth quit to the touchscreen startup
echo "Updating touchscreen startup to quit Plymouth..."
if [ -f /opt/spotify-terminal/scripts/start-touchscreen.sh ]; then
    # Add Plymouth quit after X starts
    if ! grep -q "plymouth quit" /opt/spotify-terminal/scripts/start-touchscreen.sh; then
        sed -i '/^export DISPLAY=:0/a\
\
# Quit Plymouth splash now that X is starting\
plymouth quit 2>/dev/null || true' /opt/spotify-terminal/scripts/start-touchscreen.sh
    fi
fi

# Also add to start-web-player.sh
if [ -f /opt/spotify-terminal/scripts/start-web-player.sh ]; then
    if ! grep -q "plymouth quit" /opt/spotify-terminal/scripts/start-web-player.sh; then
        sed -i '/^export DISPLAY=:0/a\
\
# Quit Plymouth splash now that GUI is starting\
plymouth quit 2>/dev/null || true' /opt/spotify-terminal/scripts/start-web-player.sh
    fi
fi

# Update rc.local to quit Plymouth after X starts
cat > /etc/rc.local <<'EOF'
#!/bin/bash
# Manage Plymouth lifecycle

# Check if Plymouth is running
if [ -f /run/plymouth/pid ]; then
    # Update status
    plymouth update --status="Starting Spotify Kids Manager..."
    
    # Wait for X to start (max 30 seconds)
    count=0
    while [ $count -lt 30 ]; do
        if pgrep -x "Xorg" > /dev/null; then
            # X is running, wait a bit then quit Plymouth
            sleep 2
            plymouth quit
            break
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # Force quit after 30 seconds regardless
    if [ $count -ge 30 ]; then
        plymouth quit
    fi
fi

exit 0
EOF
chmod +x /etc/rc.local

# Ensure rc-local service is enabled
systemctl enable rc-local.service 2>/dev/null || true

echo ""
echo "============================================"
echo "Plymouth quit timing fixed!"
echo ""
echo "Plymouth will now:"
echo "1. Show during boot"
echo "2. Quit automatically when X server starts"
echo "3. Force quit after 30 seconds if X doesn't start"
echo ""
echo "Please reboot to test the changes."
echo "============================================"