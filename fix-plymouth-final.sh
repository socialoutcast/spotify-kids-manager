#!/bin/bash
#
# Final fix for Plymouth - ensure it quits properly
#

if [[ $EUID -ne 0 ]]; then 
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "============================================"
echo "Final Plymouth Fix - Proper quit timing"
echo "============================================"
echo ""

# 1. Remove ALL Plymouth persistence services
echo "Removing all Plymouth persistence services..."
systemctl disable plymouth-persist.service 2>/dev/null
systemctl disable plymouth-quit-on-x.service 2>/dev/null
rm -f /etc/systemd/system/plymouth-persist.service
rm -f /etc/systemd/system/plymouth-quit-on-x.service
rm -f /etc/systemd/system/plymouth-quit-wait.service

# 2. Restore normal Plymouth behavior
echo "Restoring normal Plymouth services..."
systemctl unmask plymouth-quit.service 2>/dev/null
systemctl unmask plymouth-quit-wait.service 2>/dev/null
systemctl enable plymouth-quit.service 2>/dev/null
systemctl enable plymouth-quit-wait.service 2>/dev/null

# 3. Fix getty to work properly
rm -rf /etc/systemd/system/getty@tty1.service.d/

# 4. Add Plymouth quit to the auto-login script
echo "Updating startup scripts..."
if [ -f /home/spotify-kids/.bash_profile ]; then
    if ! grep -q "plymouth quit" /home/spotify-kids/.bash_profile; then
        sed -i '1a\
# Quit Plymouth when user logs in\
plymouth quit 2>/dev/null || true\
' /home/spotify-kids/.bash_profile
    fi
fi

# 5. Ensure X startup scripts quit Plymouth
for script in /opt/spotify-terminal/scripts/start-touchscreen.sh /opt/spotify-terminal/scripts/start-web-player.sh; do
    if [ -f "$script" ]; then
        if ! grep -q "plymouth quit" "$script"; then
            sed -i '/^#!/a\
\
# Force Plymouth to quit\
plymouth quit 2>/dev/null || true\
sleep 1\
pkill plymouthd 2>/dev/null || true' "$script"
        fi
    fi
done

# 6. Create a systemd service that force-quits Plymouth after boot
cat > /etc/systemd/system/plymouth-force-quit.service <<EOF
[Unit]
Description=Force quit Plymouth after boot
After=multi-user.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 10; plymouth quit 2>/dev/null; pkill plymouthd 2>/dev/null'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl enable plymouth-force-quit.service

# 7. Update Plymouth config for shorter timeout
cat > /etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=spotify-kids
ShowDelay=0
DeviceTimeout=5
EOF

# 8. Fix rc.local to quit Plymouth quickly
cat > /etc/rc.local <<'EOF'
#!/bin/bash
# Quick Plymouth quit

if [ -f /run/plymouth/pid ]; then
    # Wait just 5 seconds max
    sleep 5
    plymouth quit
    pkill plymouthd 2>/dev/null
fi

exit 0
EOF
chmod +x /etc/rc.local

# 9. Reload everything
systemctl daemon-reload

echo ""
echo "============================================"
echo "Plymouth timing fixed!"
echo ""
echo "Plymouth will now:"
echo "1. Show during early boot"
echo "2. Quit when user logs in"
echo "3. Force quit after 10 seconds max"
echo ""
echo "Please reboot to test."
echo "============================================"