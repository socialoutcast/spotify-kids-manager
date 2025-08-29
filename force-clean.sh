#!/bin/bash

# Force clean ALL old installations

echo "Force cleaning ALL Spotify installations..."

# Stop ALL related services
sudo systemctl stop spotify-terminal-admin 2>/dev/null || true
sudo systemctl stop spotify-terminal 2>/dev/null || true
sudo systemctl stop spotify-player 2>/dev/null || true
sudo systemctl stop spotify-admin 2>/dev/null || true
sudo systemctl stop spotify-kids 2>/dev/null || true

# Disable ALL related services
sudo systemctl disable spotify-terminal-admin 2>/dev/null || true
sudo systemctl disable spotify-terminal 2>/dev/null || true
sudo systemctl disable spotify-player 2>/dev/null || true
sudo systemctl disable spotify-admin 2>/dev/null || true
sudo systemctl disable spotify-kids 2>/dev/null || true

# Remove ALL service files
sudo rm -f /etc/systemd/system/spotify*.service
sudo rm -f /lib/systemd/system/spotify*.service

# Remove ALL installation directories
sudo rm -rf /opt/spotify-terminal
sudo rm -rf /opt/spotify-kids
sudo rm -rf /opt/spotify*

# Remove ALL nginx configs
sudo rm -f /etc/nginx/sites-available/spotify*
sudo rm -f /etc/nginx/sites-enabled/spotify*
sudo rm -f /etc/nginx/sites-available/spotify-terminal*
sudo rm -f /etc/nginx/sites-enabled/spotify-terminal*
sudo rm -f /etc/nginx/sites-available/spotify-admin
sudo rm -f /etc/nginx/sites-enabled/spotify-admin

# Restore default nginx site if needed
if [ ! -f /etc/nginx/sites-enabled/default ] && [ -f /etc/nginx/sites-available/default ]; then
    sudo ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/
fi

# Remove sudoers entries
sudo rm -f /etc/sudoers.d/spotify*

# Remove users
sudo userdel spotify-kids 2>/dev/null || true
sudo userdel spotify-admin 2>/dev/null || true
sudo userdel spotify-terminal 2>/dev/null || true

# Remove groups (after users are removed)
sudo groupdel spotify-kids 2>/dev/null || true
sudo groupdel spotify-admin 2>/dev/null || true
sudo groupdel spotify-terminal 2>/dev/null || true

# Clean home directories
sudo rm -rf /home/spotify*

# Reload everything
sudo systemctl daemon-reload
sudo systemctl restart nginx

echo "==========================================="
echo "ALL old installations removed!"
echo "Now run the fresh install:"
echo ""
echo "curl -sSL https://github.com/socialoutcast/spotify-kids-manager/raw/main/install.sh | sudo bash"
echo "==========================================="