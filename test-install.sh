#!/bin/bash

# Test Installation Script
# Validates the installation components without actually installing

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Testing Spotify Kids Manager Installation Components..."
echo ""

# Check files exist
echo "Checking files..."
FILES=(
    "install.sh"
    "README.md"
    "scripts/terminal-motd.sh"
    "scripts/small-screen-motd.sh"
    "scripts/desktop-terminal-display.sh"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file exists"
    else
        echo -e "${RED}✗${NC} $file missing"
    fi
done

echo ""
echo "Checking installer script..."

# Check installer has proper structure
if grep -q "install_dependencies" install.sh; then
    echo -e "${GREEN}✓${NC} install_dependencies function found"
else
    echo -e "${RED}✗${NC} install_dependencies function missing"
fi

if grep -q "create_spotify_user" install.sh; then
    echo -e "${GREEN}✓${NC} create_spotify_user function found"
else
    echo -e "${RED}✗${NC} create_spotify_user function missing"
fi

if grep -q "setup_web_admin" install.sh; then
    echo -e "${GREEN}✓${NC} setup_web_admin function found"
else
    echo -e "${RED}✗${NC} setup_web_admin function missing"
fi

echo ""
echo "Checking Python code in installer..."

# Extract and test Python code syntax
sed -n '/cat > .*app.py.*EOF/,/^EOF/p' install.sh | sed '1d;$d' > /tmp/test_app.py
if python3 -m py_compile /tmp/test_app.py 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Python code syntax is valid"
else
    echo -e "${RED}✗${NC} Python code has syntax errors"
fi
rm -f /tmp/test_app.py

echo ""
echo -e "${GREEN}All tests completed!${NC}"
echo ""
echo "To test the display script, run:"
echo "  ./scripts/terminal-motd.sh"
echo ""
echo "To install on a Raspberry Pi, run:"
echo "  sudo ./install.sh"