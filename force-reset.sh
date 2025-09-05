#!/bin/bash

# Force reset without confirmation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Spotify Kids Manager - Force Reset${NC}"
echo "================================"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}"
   exit 1
fi

echo -e "${YELLOW}Force removing ALL Spotify installations...${NC}"

# Stop ANY service with spotify in the name
echo -e "${YELLOW}Stopping ALL Spotify services...${NC}"
systemctl list-units --all --type=service | grep -i spotify | awk '{print $1}' | while read service; do
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
done

echo -e "${YELLOW}Removing ALL Spotify files...${NC}"
# Remove ALL spotify-related directories
rm -rf /opt/spotify*
rm -rf /opt/spotify-terminal
rm -rf /opt/spotify-kids

# Remove ALL service files
rm -f /etc/systemd/system/spotify*.service
rm -f /lib/systemd/system/spotify*.service
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf

# Remove ALL nginx configs
rm -f /etc/nginx/sites-available/spotify*
rm -f /etc/nginx/sites-enabled/spotify*

# Restore default nginx site if needed
if [ ! -f /etc/nginx/sites-enabled/default ] && [ -f /etc/nginx/sites-available/default ]; then
    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi

# Remove ALL sudoers entries
rm -f /etc/sudoers.d/spotify*

# Remove ALL uninstall scripts
rm -f /usr/local/bin/spotify*

# Remove X11 configs we may have added
rm -f /etc/X11/xorg.conf.d/99-calibration.conf

echo -e "${YELLOW}Removing ALL Spotify users and groups...${NC}"
# Remove ANY user with spotify in the name
for user in spotify-kids spotify-admin spotify-terminal; do
    if id "$user" &>/dev/null; then
        # Kill all processes for this user
        pkill -9 -u "$user" 2>/dev/null || true
        sleep 2
        # Force remove user without removing home (we'll do that manually)
        userdel "$user" 2>/dev/null || true
    fi
done

# Remove groups (after users are removed)
for group in spotify-kids spotify-admin spotify-terminal; do
    if getent group "$group" >/dev/null 2>&1; then
        echo "Removing group: $group"
        groupdel "$group" 2>/dev/null || true
    fi
done

# Force clean up home directories
rm -rf /home/spotify-kids 2>/dev/null || true
rm -rf /home/spotify-admin 2>/dev/null || true
rm -rf /home/spotify-terminal 2>/dev/null || true
rm -rf /home/spotify* 2>/dev/null || true

# Clean up logs
rm -rf /var/log/spotify*

# Reload everything
systemctl daemon-reload
systemctl restart nginx 2>/dev/null || true

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}COMPLETE RESET DONE!${NC}"
echo -e "${GREEN}All Spotify installations removed.${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "${GREEN}Running fresh installation...${NC}"
sleep 2

# Now run the installer automatically
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | bash