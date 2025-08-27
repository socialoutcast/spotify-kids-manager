#!/bin/bash

# Spotify Kids Manager - Repair Script
# Run this if you're getting 502 errors or other issues

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
INSTALL_DIR="/opt/spotify-terminal"
WEB_PORT=8080
SERVICE_NAME="spotify-terminal-admin"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

echo "============================================"
echo "    Spotify Kids Manager - Repair Tool"
echo "============================================"
echo ""

# Step 1: Check if installed
log_info "Checking installation..."
if [ ! -d "$INSTALL_DIR" ]; then
    log_error "System not installed. Run: sudo ./install.sh"
    exit 1
fi
log_success "Installation found"

# Step 2: Check and fix Python dependencies
log_info "Checking Python dependencies..."
MISSING_DEPS=()
for dep in flask flask-cors flask-socketio werkzeug; do
    if ! python3 -c "import $dep" 2>/dev/null; then
        MISSING_DEPS+=($dep)
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    log_warning "Installing missing Python dependencies: ${MISSING_DEPS[*]}"
    pip3 install --break-system-packages ${MISSING_DEPS[*]} || \
    pip3 install ${MISSING_DEPS[*]} || \
    python3 -m pip install ${MISSING_DEPS[*]}
else
    log_success "All Python dependencies installed"
fi

# Step 3: Check Flask app
log_info "Testing Flask application..."
cd "$INSTALL_DIR/web"

# Kill any existing test instances
pkill -f "app.py" 2>/dev/null || true

# Test Flask app
timeout 5 python3 app.py > /tmp/flask_test.log 2>&1 &
FLASK_PID=$!
sleep 2

if kill -0 $FLASK_PID 2>/dev/null; then
    log_success "Flask app runs successfully"
    kill $FLASK_PID
else
    log_error "Flask app failed to start. Error log:"
    cat /tmp/flask_test.log
    
    # Try to fix
    log_info "Attempting to fix..."
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/data"
    touch "$INSTALL_DIR/config/admin.json"
    touch "$INSTALL_DIR/config/client.conf"
    chmod +x "$INSTALL_DIR/web/app.py"
fi

# Step 4: Check nginx
log_info "Checking nginx..."
if ! systemctl is-active --quiet nginx; then
    log_warning "Nginx not running - starting..."
    systemctl start nginx
fi

if [ ! -f /etc/nginx/sites-available/spotify-admin ]; then
    log_warning "Nginx config missing - recreating..."
    cat > /etc/nginx/sites-available/spotify-admin <<EOF
server {
    listen $WEB_PORT;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:5001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/spotify-admin /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
fi

# Test nginx config
if nginx -t 2>/dev/null; then
    log_success "Nginx configuration valid"
    systemctl reload nginx
else
    log_error "Nginx configuration error"
    nginx -t
fi

# Step 5: Fix systemd service
log_info "Checking systemd service..."
if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
    log_warning "Service file missing - recreating..."
    cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=Spotify Terminal Admin Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/web
ExecStart=/usr/bin/python3 $INSTALL_DIR/web/app.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
fi

# Step 6: Restart services
log_info "Restarting services..."
systemctl restart "$SERVICE_NAME"
systemctl restart nginx
sleep 3

# Step 7: Test access
log_info "Testing web panel..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$WEB_PORT")

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    log_success "Web panel is working! (HTTP $HTTP_CODE)"
elif [ "$HTTP_CODE" = "502" ]; then
    log_error "Still getting 502 error. Checking logs..."
    echo ""
    echo "=== Flask Service Logs ==="
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager
    echo ""
    echo "=== Nginx Error Logs ==="
    tail -20 /var/log/nginx/error.log
else
    log_warning "Web panel returned HTTP $HTTP_CODE"
fi

# Step 8: Show status
echo ""
echo "============================================"
echo "              System Status"
echo "============================================"
echo ""

# Check service status
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "Flask Service: ${GREEN}● Running${NC}"
else
    echo -e "Flask Service: ${RED}● Not Running${NC}"
fi

if systemctl is-active --quiet nginx; then
    echo -e "Nginx Service: ${GREEN}● Running${NC}"
else
    echo -e "Nginx Service: ${RED}● Not Running${NC}"
fi

# Check ports
if ss -tln | grep -q ":$WEB_PORT"; then
    echo -e "Port $WEB_PORT: ${GREEN}● Listening${NC}"
else
    echo -e "Port $WEB_PORT: ${RED}● Not Listening${NC}"
fi

if ss -tln | grep -q ":5001"; then
    echo -e "Port 5001: ${GREEN}● Listening${NC}"
else
    echo -e "Port 5001: ${RED}● Not Listening${NC}"
fi

# Show access info
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================"
echo "Access the admin panel at:"
echo "  http://$IP:$WEB_PORT"
echo ""
echo "Default credentials:"
echo "  Username: admin"
echo "  Password: changeme"
echo "============================================"
echo ""
echo "For more detailed logs, run:"
echo "  sudo journalctl -u $SERVICE_NAME -f"
echo ""