#!/bin/bash

# Spotify Kids Terminal Manager - Remote Installation Script
# This can be run directly via curl

set -e

# Configuration
GITHUB_REPO="https://github.com/socialoutcast/spotify-kids-manager"
BRANCH="main"
TEMP_DIR="/tmp/spotify-kids-installer-$$"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Parse command line arguments
INSTALL_MODE="install"

if [[ "$1" == "--reset" ]] || [[ "$1" == "-r" ]] || [[ "$1" == "reset" ]]; then
    INSTALL_MODE="reset"
elif [[ "$1" == "--diagnose" ]] || [[ "$1" == "-d" ]] || [[ "$1" == "diagnose" ]]; then
    INSTALL_MODE="diagnose"
elif [[ "$1" == "--uninstall" ]] || [[ "$1" == "uninstall" ]]; then
    INSTALL_MODE="uninstall"
elif [[ "$1" == "--repair" ]] || [[ "$1" == "repair" ]]; then
    INSTALL_MODE="repair"
elif [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]] || [[ "$1" == "help" ]]; then
    echo "Spotify Kids Terminal Manager - Remote Installer"
    echo ""
    echo "Usage:"
    echo "  curl -fsSL [URL] | sudo bash -s -- [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (none)      Normal installation"
    echo "  reset       Complete reset and reinstall"
    echo "  diagnose    Run diagnostics"
    echo "  repair      Try to repair existing installation"
    echo "  uninstall   Remove everything"
    echo "  help        Show this help"
    echo ""
    echo "Examples:"
    echo "  # Normal install:"
    echo "  curl -fsSL [URL] | sudo bash"
    echo ""
    echo "  # Reset and reinstall:"
    echo "  curl -fsSL [URL] | sudo bash -s -- reset"
    echo ""
    echo "  # Diagnose issues:"
    echo "  curl -fsSL [URL] | sudo bash -s -- diagnose"
    echo ""
    exit 0
fi

clear
echo "============================================"
echo "    Spotify Kids Terminal Manager"
echo "    Remote Installer"
echo "    Mode: ${INSTALL_MODE^^}"
echo "============================================"
echo ""

# Create temp directory
log_info "Preparing installation..."
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download the repository
log_info "Downloading from GitHub..."
if command -v git &> /dev/null; then
    git clone --quiet --depth 1 --branch "$BRANCH" "$GITHUB_REPO" . 2>/dev/null || {
        log_error "Failed to clone repository"
        exit 1
    }
else
    # Fallback to wget/curl if git not available
    log_info "Git not found, downloading archive..."
    if command -v wget &> /dev/null; then
        wget -q -O master.tar.gz "${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz" || {
            log_error "Failed to download"
            exit 1
        }
    elif command -v curl &> /dev/null; then
        curl -sL -o master.tar.gz "${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz" || {
            log_error "Failed to download"
            exit 1
        }
    else
        log_error "Neither git, wget, nor curl found. Install one of them first."
        exit 1
    fi
    tar -xzf master.tar.gz --strip-components=1
fi

log_success "Download complete"

# Make scripts executable
chmod +x install.sh repair.sh 2>/dev/null || true

# Run the appropriate command
case "$INSTALL_MODE" in
    "reset")
        log_info "Running reset..."
        ./install.sh --reset
        ;;
    "diagnose")
        log_info "Running diagnostics..."
        ./install.sh --diagnose
        ;;
    "repair")
        if [ -f repair.sh ]; then
            log_info "Running repair..."
            ./repair.sh
        else
            log_error "Repair script not found"
            exit 1
        fi
        ;;
    "uninstall")
        log_info "Running uninstall..."
        ./install.sh --uninstall
        ;;
    *)
        log_info "Running installation..."
        ./install.sh
        ;;
esac

# Cleanup
cd /
rm -rf "$TEMP_DIR"

log_success "Operation complete!"