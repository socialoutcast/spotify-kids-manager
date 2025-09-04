#!/bin/bash

# Build script for creating release packages
# This packages the source code into tar.gz files for GitHub releases

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get version from command line or use default
VERSION=${1:-"latest"}

echo -e "${GREEN}Building Spotify Kids Manager Release - Version: $VERSION${NC}"
echo "================================"

# Create build directory
BUILD_DIR="build"
RELEASE_DIR="release"
rm -rf $BUILD_DIR $RELEASE_DIR
mkdir -p $BUILD_DIR $RELEASE_DIR

# Package web application
echo -e "${YELLOW}Packaging web application...${NC}"
tar czf $RELEASE_DIR/spotify-kids-web.tar.gz \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.DS_Store' \
    web/

# Package player application  
echo -e "${YELLOW}Packaging player application...${NC}"
tar czf $RELEASE_DIR/spotify-kids-player.tar.gz \
    --exclude='node_modules' \
    --exclude='.DS_Store' \
    player/

# Copy kiosk launcher (single file, not archived)
echo -e "${YELLOW}Copying kiosk launcher...${NC}"
cp kiosk_launcher.sh $RELEASE_DIR/

# Create a combined package for convenience
echo -e "${YELLOW}Creating combined package...${NC}"
tar czf $RELEASE_DIR/spotify-kids-complete.tar.gz \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='node_modules' \
    --exclude='.DS_Store' \
    --exclude='.git' \
    --exclude='build' \
    --exclude='release' \
    --exclude='*.sh' \
    web/ player/ kiosk_launcher.sh

# Create checksums
echo -e "${YELLOW}Generating checksums...${NC}"
cd $RELEASE_DIR
sha256sum *.tar.gz *.sh > checksums.txt
cd ..

# Create release notes template
echo -e "${YELLOW}Creating release notes...${NC}"
cat > $RELEASE_DIR/release-notes.md << EOF
# Spotify Kids Manager - Release $VERSION

## Installation
\`\`\`bash
curl -sSL https://raw.githubusercontent.com/socialoutcast/spotify-kids-manager/main/install.sh | sudo bash
\`\`\`

## Files
- \`spotify-kids-web.tar.gz\` - Web admin interface
- \`spotify-kids-player.tar.gz\` - Player application  
- \`spotify-kids-complete.tar.gz\` - Complete package (all components)
- \`kiosk_launcher.sh\` - Kiosk mode launcher script
- \`checksums.txt\` - SHA256 checksums for verification

## Changes in this release
- [Add your changes here]

## Checksums
\`\`\`
$(cat $RELEASE_DIR/checksums.txt)
\`\`\`
EOF

echo ""
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}================================${NC}"
echo ""
echo -e "Release files created in: ${YELLOW}$RELEASE_DIR/${NC}"
echo ""
ls -lh $RELEASE_DIR/
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the files in the release directory"
echo "2. Create a new release on GitHub: https://github.com/socialoutcast/spotify-kids-manager/releases/new"
echo "3. Upload these files as release assets:"
cd $RELEASE_DIR
for file in *.tar.gz *.sh checksums.txt; do
    echo "   - $file"
done
cd ..
echo "4. Publish the release"
echo ""
echo -e "${YELLOW}The installer will automatically download from the latest release${NC}"