#!/bin/bash
#
# Fix Plymouth to stay running until X starts
#

if [[ $EUID -ne 0 ]]; then 
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "============================================"
echo "Configuring Plymouth to run until X starts"
echo "============================================"
echo ""

# 1. Remove any force-quit services
echo "Removing force-quit services..."
systemctl disable plymouth-force-quit.service 2>/dev/null
systemctl disable plymouth-persist.service 2>/dev/null
rm -f /etc/systemd/system/plymouth-force-quit.service
rm -f /etc/systemd/system/plymouth-persist.service

# 2. Disable normal Plymouth quit
echo "Disabling early Plymouth quit..."
systemctl disable plymouth-quit.service 2>/dev/null
systemctl disable plymouth-quit-wait.service 2>/dev/null

# 3. Create X-triggered quit service
echo "Creating X-triggered quit service..."
cat > /etc/systemd/system/plymouth-quit-on-x.service <<EOF
[Unit]
Description=Quit Plymouth when X server starts
After=multi-user.target
Before=getty@tty1.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'while ! pgrep -x "Xorg" > /dev/null; do sleep 1; done; sleep 2; /usr/bin/plymouth quit'
RemainAfterExit=yes
TimeoutSec=60

[Install]
WantedBy=graphical.target
EOF

systemctl enable plymouth-quit-on-x.service

# 4. Configure getty to wait
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/plymouth.conf <<EOF
[Unit]
After=plymouth-quit-on-x.service

[Service]
ExecStartPre=-/bin/bash -c 'while [ -f /run/plymouth/pid ]; do sleep 1; done'
EOF

# 5. Update Plymouth config
cat > /etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=spotify-kids
ShowDelay=0
DeviceTimeout=30
EOF

# 6. Keep Plymouth quit commands in startup scripts
echo "Keeping Plymouth quit in startup scripts..."
# The scripts already have plymouth quit when X starts

# 7. Reload
systemctl daemon-reload

echo ""
echo "============================================"
echo "Plymouth configured successfully!"
echo ""
echo "Plymouth will now:"
echo "1. Show during entire boot process"
echo "2. Stay visible until X server starts"
echo "3. Quit automatically when GUI loads"
echo "4. Timeout after 60 seconds if X fails"
echo ""
echo "Please reboot to test."
echo "============================================"