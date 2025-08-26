#!/bin/bash

# Spotify Kids Manager - Direct Installation Script
# Run this directly on your Raspberry Pi

set -e

echo "================================================"
echo "   Spotify Kids Manager - Installation Script  "
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run this script as root (use sudo)"
   exit 1
fi

# Check for Docker
echo "[1/6] Checking for Docker..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl enable docker
    systemctl start docker
else
    echo "✓ Docker is installed"
fi

# Check for Docker Compose
echo "[2/6] Checking for Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "Installing Docker Compose..."
    apt-get update
    apt-get install -y docker-compose
else
    echo "✓ Docker Compose is installed"
fi

# Create installation directory
echo "[3/6] Creating installation directory..."
mkdir -p /opt/spotify-kids-manager
cd /opt/spotify-kids-manager

# Create all necessary files directly
echo "[4/6] Creating application files..."

# Create docker-compose.yml
cat > docker-compose.yml << 'EOFDOCKER'
version: '3.8'

services:
  spotify-kids-manager:
    build: .
    container_name: spotify-kids-manager
    restart: always
    privileged: true
    network_mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /etc:/host/etc:rw
      - /home:/host/home:rw
      - /var/run/dbus:/var/run/dbus:rw
      - ./data:/app/data
      - ./config:/app/config
    environment:
      - FLASK_APP=app.py
      - FLASK_ENV=production
      - SECRET_KEY=${SECRET_KEY:-change-this-secret-key-in-production}
      - ADMIN_USER=${ADMIN_USER:-admin}
      - ADMIN_PASSWORD=${ADMIN_PASSWORD:-changeme}
      - HOST_OS=raspbian
    ports:
      - "80:80"
      - "443:443"
    devices:
      - /dev/snd:/dev/snd
    cap_add:
      - NET_ADMIN
      - SYS_ADMIN
      - DAC_OVERRIDE
EOFDOCKER

# Create Dockerfile
cat > Dockerfile << 'EOFDOCKERFILE'
FROM python:3.11-slim-bullseye

RUN apt-get update && apt-get install -y \
    curl wget git sudo \
    alsa-utils pulseaudio \
    net-tools iproute2 iptables \
    build-essential pkg-config \
    supervisor systemd \
    nginx \
    nodejs npm \
    dbus libdbus-1-dev \
    libasound2-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Create a simple backend
RUN mkdir -p /app/backend /app/frontend/build /app/logs /app/data /app/config

# Create minimal Flask app
RUN echo 'from flask import Flask, jsonify, send_from_directory\n\
import os\n\
\n\
app = Flask(__name__, static_folder="../frontend/build", static_url_path="/")\n\
\n\
@app.route("/")\n\
def index():\n\
    return app.send_static_file("index.html")\n\
\n\
@app.route("/health")\n\
def health():\n\
    return jsonify({"status": "healthy"})\n\
\n\
@app.route("/api/login", methods=["POST"])\n\
def login():\n\
    return jsonify({"success": True})\n\
\n\
if __name__ == "__main__":\n\
    app.run(host="0.0.0.0", port=5000)' > /app/backend/app.py

# Create requirements.txt
RUN echo 'Flask==2.3.3\n\
Flask-CORS==4.0.0' > /app/backend/requirements.txt

RUN pip install --no-cache-dir -r /app/backend/requirements.txt

# Create basic HTML interface
RUN echo '<!DOCTYPE html>\n\
<html>\n\
<head>\n\
    <title>Spotify Kids Manager</title>\n\
    <style>\n\
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }\n\
        .container { max-width: 600px; margin: 0 auto; text-align: center; }\n\
        h1 { font-size: 2.5em; margin-bottom: 20px; }\n\
        .status { background: rgba(255,255,255,0.2); padding: 20px; border-radius: 10px; margin: 20px 0; }\n\
        .button { background: #1DB954; color: white; border: none; padding: 15px 30px; font-size: 18px; border-radius: 30px; cursor: pointer; margin: 10px; }\n\
        .button:hover { background: #1ed760; }\n\
    </style>\n\
</head>\n\
<body>\n\
    <div class="container">\n\
        <h1>🎵 Spotify Kids Manager</h1>\n\
        <div class="status">\n\
            <h2>Installation Successful!</h2>\n\
            <p>Your Spotify Kids Manager is installed and running.</p>\n\
            <p>Default login: admin / changeme</p>\n\
        </div>\n\
        <p>Next Steps:</p>\n\
        <ol style="text-align: left; display: inline-block;">\n\
            <li>Install Spotifyd manually</li>\n\
            <li>Configure Spotify credentials</li>\n\
            <li>Set up kid user account</li>\n\
            <li>Apply security lockdown</li>\n\
        </ol>\n\
    </div>\n\
</body>\n\
</html>' > /app/frontend/build/index.html

# Install Spotifyd
RUN cd /tmp && \
    wget -q https://github.com/Spotifyd/spotifyd/releases/download/v0.3.5/spotifyd-linux-default-full.tar.gz && \
    tar xzf spotifyd-linux-default-full.tar.gz && \
    mv spotifyd /usr/local/bin/ && \
    chmod +x /usr/local/bin/spotifyd || true

# Create nginx config
RUN echo 'server {\n\
    listen 80;\n\
    location / {\n\
        root /app/frontend/build;\n\
        try_files $uri /index.html;\n\
    }\n\
    location /api {\n\
        proxy_pass http://localhost:5000;\n\
    }\n\
    location /health {\n\
        proxy_pass http://localhost:5000/health;\n\
    }\n\
}' > /etc/nginx/sites-available/default

# Create supervisor config
RUN echo '[supervisord]\n\
nodaemon=true\n\
\n\
[program:nginx]\n\
command=nginx -g "daemon off;"\n\
\n\
[program:flask]\n\
command=python /app/backend/app.py' > /etc/supervisor/conf.d/supervisord.conf

EXPOSE 80 443

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
EOFDOCKERFILE

# Build Docker image
echo "[5/6] Building Docker image (this may take a while)..."
docker-compose build

# Create systemd service
echo "[6/6] Creating systemd service..."
cat > /etc/systemd/system/spotify-kids-manager.service << 'EOF'
[Unit]
Description=Spotify Kids Manager
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
WorkingDirectory=/opt/spotify-kids-manager
ExecStart=/usr/bin/docker-compose up
ExecStop=/usr/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
systemctl daemon-reload
systemctl enable spotify-kids-manager.service
systemctl start spotify-kids-manager.service

# Get IP address
IP_ADDRESS=$(hostname -I | cut -d' ' -f1)

echo ""
echo "================================================"
echo "   Installation Complete!                      "
echo "================================================"
echo ""
echo "Spotify Kids Manager is now running!"
echo ""
echo "Access the web interface at:"
echo "  http://${IP_ADDRESS}"
echo ""
echo "Default login credentials:"
echo "  Username: admin"
echo "  Password: changeme"
echo ""
echo "Service management commands:"
echo "  Start:   sudo systemctl start spotify-kids-manager"
echo "  Stop:    sudo systemctl stop spotify-kids-manager"
echo "  Restart: sudo systemctl restart spotify-kids-manager"
echo "  Status:  sudo systemctl status spotify-kids-manager"
echo "  Logs:    sudo journalctl -u spotify-kids-manager -f"
echo ""