#!/bin/bash

# Spotify Kids Manager - Display Setup Instructions
# Shows setup instructions on the device's console/display

# Get the primary IP address
get_ip_address() {
    # Try multiple methods to get IP
    IP=$(hostname -I 2>/dev/null | cut -d' ' -f1)
    if [ -z "$IP" ]; then
        IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+')
    fi
    if [ -z "$IP" ]; then
        IP=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1 | cut -d: -f2 | awk '{print $1}')
    fi
    echo ${IP:-"Unable to detect IP"}
}

# Clear the screen
clear

# Get IP address
IP_ADDRESS=$(get_ip_address)

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Display the setup message
cat << EOF

${CYAN}================================================================================
${WHITE}${BOLD}                     SPOTIFY KIDS MANAGER - SETUP REQUIRED                     
${CYAN}================================================================================
${NC}

${GREEN}✓ Installation Complete!${NC}

${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${WHITE}${BOLD}To complete setup, please visit:${NC}

    ${CYAN}${BOLD}http://${IP_ADDRESS}:8080${NC}

${WHITE}From any device on your network (phone, tablet, or computer)${NC}

${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${WHITE}${BOLD}Default Login:${NC}
    Username: ${GREEN}admin${NC}
    Password: ${GREEN}changeme${NC}
    
${RED}${BOLD}⚠ IMPORTANT: Change the password immediately after first login!${NC}

${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${WHITE}${BOLD}Setup Steps:${NC}
    1. System Check     - Verify all components are ready
    2. Create Kid User  - Set up restricted account
    3. Configure Spotify - Enter your Premium credentials
    4. Apply Security   - Lock down the system
    5. Enable Auto-Start - Start music on boot

${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

${WHITE}${BOLD}Network Information:${NC}
    Device IP: ${CYAN}${IP_ADDRESS}${NC}
    Web Port:  ${CYAN}8080${NC}
    
${WHITE}If you cannot connect, try:${NC}
    - Ensure you're on the same network
    - Check firewall settings
    - Restart the service: ${YELLOW}sudo systemctl restart spotify-kids-manager${NC}

${CYAN}================================================================================
${WHITE}          This message will remain visible until setup is complete
${CYAN}================================================================================
${NC}

EOF

# If running on a TTY, also display a QR code if qrencode is available
if [ -t 1 ] && command -v qrencode &> /dev/null; then
    echo ""
    echo "${WHITE}${BOLD}Scan QR Code to access setup:${NC}"
    echo ""
    qrencode -t ANSIUTF8 "http://${IP_ADDRESS}:8080"
fi

# Keep the message displayed
if [ "$1" == "--wait" ]; then
    echo ""
    echo "${YELLOW}Press any key to continue...${NC}"
    read -n 1 -s
fi