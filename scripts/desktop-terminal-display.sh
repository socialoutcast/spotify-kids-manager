#!/bin/bash

# Desktop Terminal Display Script
# Opens a graphical terminal to display installation info

# Check if we're in an X session
if [ -z "$DISPLAY" ]; then
    echo "No X display found. Setting DISPLAY=:0"
    export DISPLAY=:0
fi

# Try different terminal emulators in order of preference
if command -v gnome-terminal &> /dev/null; then
    gnome-terminal --geometry=80x35 --title="Spotify Kids Manager" -- bash -c "/home/bkrause/Projects/spotify-kids-manager/scripts/terminal-motd.sh; read -p 'Press Enter to close...'"
elif command -v konsole &> /dev/null; then
    konsole --geometry 800x600 -e bash -c "/home/bkrause/Projects/spotify-kids-manager/scripts/terminal-motd.sh; read -p 'Press Enter to close...'"
elif command -v xfce4-terminal &> /dev/null; then
    xfce4-terminal --geometry=80x35 --title="Spotify Kids Manager" -e "bash -c '/home/bkrause/Projects/spotify-kids-manager/scripts/terminal-motd.sh; read -p \"Press Enter to close...\"'"
elif command -v xterm &> /dev/null; then
    xterm -geometry 80x35 -title "Spotify Kids Manager" -e bash -c "/home/bkrause/Projects/spotify-kids-manager/scripts/terminal-motd.sh; read -p 'Press Enter to close...'"
elif command -v lxterminal &> /dev/null; then
    lxterminal --geometry=80x35 --title="Spotify Kids Manager" -e bash -c "/home/bkrause/Projects/spotify-kids-manager/scripts/terminal-motd.sh; read -p 'Press Enter to close...'"
else
    echo "No suitable terminal emulator found"
    echo "Install one of: gnome-terminal, konsole, xfce4-terminal, xterm, or lxterminal"
    exit 1
fi