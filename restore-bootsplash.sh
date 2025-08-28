#!/bin/bash
#
# Spotify Kids Manager - Restore Original Boot Splash
# Removes custom boot splash and restores the original
#

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then 
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "Restoring original boot splash..."

# Backup directories to check
BACKUP_DIRS=(
    "/opt/spotify-terminal/config/bootsplash-backup"
    "/opt/spotify-terminal/config"
)

# Find backup directory
BACKUP_DIR=""
for dir in "${BACKUP_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        BACKUP_DIR="$dir"
        break
    fi
done

if [ -z "$BACKUP_DIR" ]; then
    echo "No backup directory found, using default theme..."
fi

# Restore original Plymouth theme
if [ -f "$BACKUP_DIR/original-theme.conf" ]; then
    ORIGINAL_THEME=$(cat "$BACKUP_DIR/original-theme.conf")
    echo "Restoring theme: $ORIGINAL_THEME"
    plymouth-set-default-theme "$ORIGINAL_THEME" 2>/dev/null || {
        echo "Could not restore $ORIGINAL_THEME, using default bgrt theme"
        plymouth-set-default-theme bgrt 2>/dev/null || true
    }
else
    echo "No theme backup found, setting default bgrt theme..."
    plymouth-set-default-theme bgrt 2>/dev/null || true
fi

# Remove our custom theme
echo "Removing Spotify Kids theme..."
rm -rf /usr/share/plymouth/themes/spotify-kids
update-alternatives --remove default.plymouth /usr/share/plymouth/themes/spotify-kids/spotify-kids.plymouth 2>/dev/null || true

# Restore boot configuration for Raspberry Pi
if [ -f "$BACKUP_DIR/cmdline.txt.backup" ]; then
    echo "Restoring Raspberry Pi boot configuration..."
    cp "$BACKUP_DIR/cmdline.txt.backup" /boot/cmdline.txt
elif [ -f /boot/cmdline.txt.backup ]; then
    cp /boot/cmdline.txt.backup /boot/cmdline.txt
elif [ -f /boot/cmdline.txt ]; then
    # Remove splash parameters if no backup exists
    sed -i 's/ quiet splash plymouth.ignore-serial-consoles//g' /boot/cmdline.txt
    sed -i 's/console=tty3/console=tty1/g' /boot/cmdline.txt
fi

# Restore GRUB configuration for standard systems
if [ -f "$BACKUP_DIR/grub.backup" ]; then
    echo "Restoring GRUB configuration..."
    cp "$BACKUP_DIR/grub.backup" /etc/default/grub
    update-grub
elif [ -f /etc/default/grub.backup ]; then
    cp /etc/default/grub.backup /etc/default/grub
    update-grub
elif [ -f /etc/default/grub ]; then
    # Remove splash parameters if no backup exists
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' /etc/default/grub
    update-grub 2>/dev/null || true
fi

# Update initramfs
echo "Updating boot image..."
update-initramfs -u

# Clean up backup directory
rm -rf "$BACKUP_DIR"

echo "============================================"
echo "Original boot splash restored!"
echo ""
echo "The system will now show the default boot"
echo "splash on next reboot."
echo ""
echo "Note: A reboot is required for changes to"
echo "take effect."
echo "============================================"