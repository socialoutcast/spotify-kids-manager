#!/bin/bash

# Terminal MOTD Display Script
# Shows a message on the terminal display

clear

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Get system info
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')
UPTIME=$(uptime -p)
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Display header
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                ${MAGENTA}SPOTIFY KIDS TERMINAL MANAGER${NC}               ${CYAN}║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"

# Display system info
echo -e "${CYAN}║${NC} ${WHITE}Hostname:${NC} ${GREEN}$HOSTNAME${NC}"
echo -e "${CYAN}║${NC} ${WHITE}IP Address:${NC} ${GREEN}$IP${NC}"
echo -e "${CYAN}║${NC} ${WHITE}Date/Time:${NC} ${GREEN}$DATE${NC}"
echo -e "${CYAN}║${NC} ${WHITE}Uptime:${NC} ${GREEN}$UPTIME${NC}"

echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"

# Display admin panel info
echo -e "${CYAN}║${NC}                      ${YELLOW}ADMIN PANEL ACCESS${NC}                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${WHITE}Web Interface:${NC} ${BLUE}http://$IP:8080${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${WHITE}Default Login:${NC}"
echo -e "${CYAN}║${NC}     Username: ${GREEN}admin${NC}"
echo -e "${CYAN}║${NC}     Password: ${GREEN}changeme${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${RED}⚠  CHANGE PASSWORD AFTER FIRST LOGIN!${NC}                    ${CYAN}║${NC}"

echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"

# Display current status
if systemctl is-active --quiet spotify-terminal-admin; then
    STATUS="${GREEN}● ONLINE${NC}"
else
    STATUS="${RED}● OFFLINE${NC}"
fi

if [ -f /opt/spotify-terminal/data/device.lock ]; then
    LOCK="${RED}🔒 LOCKED${NC}"
else
    LOCK="${GREEN}🔓 UNLOCKED${NC}"
fi

echo -e "${CYAN}║${NC}                        ${YELLOW}SYSTEM STATUS${NC}                        ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   Admin Panel: $STATUS"
echo -e "${CYAN}║${NC}   Device State: $LOCK"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"

echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"

# Display commands
echo -e "${CYAN}║${NC}                      ${YELLOW}USEFUL COMMANDS${NC}                        ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}   ${WHITE}View logs:${NC}      ${GREEN}sudo journalctl -u spotify-terminal-admin -f${NC}"
echo -e "${CYAN}║${NC}   ${WHITE}Restart service:${NC} ${GREEN}sudo systemctl restart spotify-terminal-admin${NC}"
echo -e "${CYAN}║${NC}   ${WHITE}Check status:${NC}    ${GREEN}sudo systemctl status spotify-terminal-admin${NC}"
echo -e "${CYAN}║${NC}   ${WHITE}Uninstall:${NC}       ${GREEN}sudo /opt/spotify-terminal/scripts/uninstall.sh${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"

echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Installation successful! The system will reboot shortly...${NC}"
echo ""