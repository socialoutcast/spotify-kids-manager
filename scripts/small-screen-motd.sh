#!/bin/bash

# Small Screen MOTD Display Script
# Compact version for small displays

clear

# Colors
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1;37m'
N='\033[0m'

IP=$(hostname -I | awk '{print $1}')

# Compact display
echo -e "${C}════════════════════════════${N}"
echo -e "${W}  SPOTIFY KIDS MANAGER${N}"
echo -e "${C}════════════════════════════${N}"
echo ""
echo -e "${W}Admin Panel:${N}"
echo -e "${B}http://$IP:8080${N}"
echo ""
echo -e "${W}Login:${N} ${G}admin / changeme${N}"
echo ""

# Status
if systemctl is-active --quiet spotify-terminal-admin; then
    echo -e "Status: ${G}● ONLINE${N}"
else
    echo -e "Status: ${R}● OFFLINE${N}"
fi

if [ -f /opt/spotify-terminal/data/device.lock ]; then
    echo -e "Device: 🔒 ${R}LOCKED${N}"
else
    echo -e "Device: 🔓 ${G}UNLOCKED${N}"
fi

echo -e "${C}════════════════════════════${N}"
echo -e "${Y}System ready!${N}"
echo ""