#!/bin/bash
#
# Fix Plymouth Boot Splash Issues
#

if [[ $EUID -ne 0 ]]; then 
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "============================================"
echo "Fixing Plymouth Boot Splash"
echo "============================================"
echo ""

# 1. Fix Plymouth service dependencies
echo "Fixing Plymouth services..."

# Disable early Plymouth quit
systemctl disable plymouth-quit.service 2>/dev/null
systemctl disable plymouth-quit-wait.service 2>/dev/null

# Create a custom Plymouth service that doesn't quit early
cat > /etc/systemd/system/plymouth-persist.service <<EOF
[Unit]
Description=Keep Plymouth running during boot
After=plymouth-start.service
Before=getty@tty1.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF

systemctl enable plymouth-persist.service

# 2. Fix the display manager conflict
echo "Configuring display manager..."

# Mask the display manager service that might be killing Plymouth
systemctl mask plymouth-quit.service 2>/dev/null
systemctl mask plymouth-quit-wait.service 2>/dev/null

# 3. Fix boot parameters for Raspberry Pi
echo "Updating boot parameters..."

if [ -f /boot/cmdline.txt ]; then
    cp /boot/cmdline.txt /boot/cmdline.txt.plymouth-backup
    
    # Remove existing splash parameters
    sed -i 's/ quiet//g; s/ splash//g; s/ plymouth[^ ]*//g; s/ logo[^ ]*//g; s/ vt[^ ]*//g' /boot/cmdline.txt
    
    # Add proper parameters for persistent splash
    sed -i 's/$/ quiet splash plymouth.enable=1 plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0 loglevel=0 rd.systemd.show_status=0 rd.udev.log_level=0 fsck.mode=skip/' /boot/cmdline.txt
    
    # Ensure console goes to tty3 not tty1
    sed -i 's/console=tty1/console=tty3/g' /boot/cmdline.txt
    
    echo "Boot parameters updated."
fi

# 4. Fix Plymouth configuration
echo "Configuring Plymouth..."

mkdir -p /etc/plymouth
cat > /etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=spotify-kids
ShowDelay=0
DeviceTimeout=30
DeviceScale=1
EOF

# 5. Create a script to manually handle Plymouth
cat > /usr/local/bin/plymouth-control <<'EOF'
#!/bin/bash
# Plymouth control script

case "$1" in
    start)
        /usr/bin/plymouthd --mode=boot --pid-file=/run/plymouth/pid
        /usr/bin/plymouth show-splash
        ;;
    stop)
        /usr/bin/plymouth quit --retain-splash
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        ;;
esac
EOF
chmod +x /usr/local/bin/plymouth-control

# 6. Create systemd override for getty to not kill Plymouth
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/plymouth.conf <<EOF
[Unit]
After=plymouth-persist.service
ConditionPathExists=!/var/run/plymouth/pid

[Service]
ExecStartPre=-/usr/bin/plymouth quit --retain-splash
EOF

# 7. Ensure initramfs has Plymouth
echo "Updating initramfs..."

# Add Plymouth modules to initramfs
if [ -f /etc/initramfs-tools/modules ]; then
    grep -q "drm" /etc/initramfs-tools/modules || echo "drm" >> /etc/initramfs-tools/modules
    grep -q "drm_kms_helper" /etc/initramfs-tools/modules || echo "drm_kms_helper" >> /etc/initramfs-tools/modules
fi

# Ensure Plymouth hook is enabled
if [ -f /usr/share/initramfs-tools/hooks/plymouth ]; then
    chmod +x /usr/share/initramfs-tools/hooks/plymouth
fi

# Force Plymouth into initramfs
cat > /etc/initramfs-tools/conf.d/plymouth <<EOF
FRAMEBUFFER=y
EOF

# 8. Set the Spotify Kids theme again
plymouth-set-default-theme spotify-kids

# 9. Rebuild initramfs
update-initramfs -u

# 10. Create a startup script that ensures Plymouth stays visible
cat > /etc/rc.local <<'EOF'
#!/bin/bash
# Keep Plymouth splash visible longer

# Check if Plymouth is running
if [ -f /run/plymouth/pid ]; then
    # Tell Plymouth we're still booting
    plymouth update --status="Starting Spotify Kids Manager..."
    sleep 2
    plymouth update --status="Loading..."
    
    # Don't quit Plymouth until X starts
    while ! pgrep -x "Xorg" > /dev/null; do
        sleep 1
    done
    
    # Fade out nicely
    plymouth quit --retain-splash
fi

exit 0
EOF
chmod +x /etc/rc.local

# Enable rc-local service
systemctl enable rc-local.service 2>/dev/null || true

echo ""
echo "============================================"
echo "Plymouth fixes applied!"
echo ""
echo "Changes made:"
echo "1. Disabled early Plymouth quit services"
echo "2. Created Plymouth persist service"
echo "3. Updated boot parameters for longer splash"
echo "4. Fixed Plymouth configuration"
echo "5. Created getty override to not kill Plymouth"
echo "6. Updated initramfs with Plymouth modules"
echo "7. Created rc.local to manage Plymouth lifecycle"
echo ""
echo "Please reboot to test the changes."
echo "============================================"