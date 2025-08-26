#!/bin/bash

# Spotify Kids Manager - Troubleshooting Script

echo "================================================"
echo "   Spotify Kids Manager - Troubleshooting      "
echo "================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run as root (use sudo)"
   exit 1
fi

echo "1. Checking Docker service..."
if systemctl is-active docker >/dev/null 2>&1; then
    echo "   ✓ Docker is running"
else
    echo "   ✗ Docker is not running"
    echo "   Fix: sudo systemctl start docker"
fi

echo ""
echo "2. Checking container status..."
if docker ps | grep -q spotify-kids-manager; then
    echo "   ✓ Container is running"
    CONTAINER_ID=$(docker ps -q -f name=spotify-kids-manager)
    echo "   Container ID: $CONTAINER_ID"
else
    echo "   ✗ Container is not running"
    echo "   Fix: cd /opt/spotify-kids-manager && sudo docker-compose up -d"
fi

echo ""
echo "3. Checking port 80..."
if netstat -tuln | grep -q ":80 "; then
    echo "   ✓ Port 80 is listening"
    netstat -tuln | grep ":80 "
else
    echo "   ✗ Port 80 is not listening"
    echo "   Checking inside container..."
    docker exec spotify-kids-manager netstat -tuln | grep ":80 " || echo "   Port 80 not listening in container"
fi

echo ""
echo "4. Checking firewall..."
if command -v ufw &> /dev/null; then
    echo "   UFW Status:"
    ufw status | grep 80 || echo "   ✗ Port 80 not allowed in UFW"
    echo ""
    echo "   Fix: sudo ufw allow 80/tcp"
elif command -v firewall-cmd &> /dev/null; then
    echo "   Firewalld Status:"
    firewall-cmd --list-ports | grep 80 || echo "   ✗ Port 80 not allowed in firewalld"
    echo ""
    echo "   Fix: sudo firewall-cmd --permanent --add-port=80/tcp && sudo firewall-cmd --reload"
fi

# Check iptables
echo ""
echo "5. Checking iptables..."
if iptables -L INPUT -n | grep -q "dpt:80"; then
    echo "   ✓ Port 80 rule exists in iptables"
else
    echo "   ✗ No iptables rule for port 80"
    echo "   Fix: sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT"
fi

echo ""
echo "6. Checking container logs..."
echo "   Last 10 lines from container:"
docker logs spotify-kids-manager --tail 10 2>&1 | sed 's/^/   /'

echo ""
echo "7. Testing web service..."
if curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200\|301\|302"; then
    echo "   ✓ Web service is responding"
else
    echo "   ✗ Web service is not responding"
    echo "   Testing from inside container..."
    docker exec spotify-kids-manager curl -s http://localhost || echo "   Service not responding inside container"
fi

echo ""
echo "8. Network information..."
echo "   IP Address: $(hostname -I | cut -d' ' -f1)"
echo "   Hostname: $(hostname)"

echo ""
echo "9. Quick fixes to try:"
echo "   a) Allow port 80 in firewall:"
echo "      sudo ufw allow 80/tcp"
echo "      sudo ufw reload"
echo ""
echo "   b) Restart the container:"
echo "      cd /opt/spotify-kids-manager"
echo "      sudo docker-compose down"
echo "      sudo docker-compose up -d"
echo ""
echo "   c) Check container is using host network:"
echo "      docker inspect spotify-kids-manager | grep NetworkMode"
echo ""
echo "   d) Manually add iptables rule:"
echo "      sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT"
echo "      sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT"
echo ""
echo "================================================"