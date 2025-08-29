# Spotify Kids Manager

A Raspberry Pi-based Spotify player with parental controls.

## Project Structure

```
spotify-kids-manager/
├── install.sh           # Main installer script
├── spotify_player.py    # Native Python Spotify player
├── web/                 # Admin web panel
│   └── app.py          # Flask admin interface
└── README.md           # This file
```

## Installation

```bash
sudo ./install.sh
```

## Features

- Native Python Spotify player for the display
- Web-based admin panel for remote management (port 8080)
- Parental controls and device locking
- Auto-start on boot