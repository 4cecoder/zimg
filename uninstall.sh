#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to play sound when uninstall completes
play_completion_sound() {
    if [[ "$OS" == "macos" ]]; then
        # macOS - use afplay
        afplay /System/Library/Sounds/Submarine.aiff &
    elif [[ "$OS" == "linux" ]]; then
        # Try different sound players available on Linux
        if command -v paplay &> /dev/null; then
            paplay /usr/share/sounds/freedesktop/stereo/trash-empty.oga &> /dev/null || true
        elif command -v aplay &> /dev/null; then
            aplay -q /usr/share/sounds/freedesktop/stereo/trash-empty.oga &> /dev/null || true
        elif command -v play &> /dev/null; then
            play -q /usr/share/sounds/freedesktop/stereo/trash-empty.oga &> /dev/null || true
        fi
    fi
}

# Print banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════╗"
echo "║           zimg uninstall           ║"
echo "╚═══════════════════════════════════╝"
echo -e "${NC}"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    echo -e "${GREEN}Detected macOS system${NC}"
    INSTALL_DIR="/usr/local/bin"
    SHARE_DIR="/usr/local/share/zimg"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    echo -e "${GREEN}Detected Linux system${NC}"
    INSTALL_DIR="/usr/local/bin"
    SHARE_DIR="/usr/local/share/zimg"
else
    echo -e "${RED}Unsupported OS: $OSTYPE${NC}"
    echo "This uninstall script supports macOS and Linux only."
    exit 1
fi

# Ask for confirmation
echo -e "${YELLOW}This will uninstall zimg from your system.${NC}"
echo -e "The following will be removed:"
echo -e "  - $INSTALL_DIR/zimg"
echo -e "  - $INSTALL_DIR/zimg.bin"
echo -e "  - $SHARE_DIR (including upscaler components)"
read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Uninstall cancelled.${NC}"
    exit 0
fi

# Check if files exist before removing
echo -e "${BLUE}Checking for installed files...${NC}"

ZIMG_FOUND=false
if [ -f "$INSTALL_DIR/zimg" ]; then
    ZIMG_FOUND=true
fi

ZIMG_BIN_FOUND=false
if [ -f "$INSTALL_DIR/zimg.bin" ]; then
    ZIMG_BIN_FOUND=true
fi

SHARE_DIR_FOUND=false
if [ -d "$SHARE_DIR" ]; then
    SHARE_DIR_FOUND=true
fi

if [ "$ZIMG_FOUND" = false ] && [ "$ZIMG_BIN_FOUND" = false ] && [ "$SHARE_DIR_FOUND" = false ]; then
    echo -e "${YELLOW}zimg does not appear to be installed. Nothing to remove.${NC}"
    exit 0
fi

# Removing files
echo -e "${BLUE}Uninstalling zimg...${NC}"

if [ "$ZIMG_FOUND" = true ]; then
    echo -e "Removing $INSTALL_DIR/zimg..."
    sudo rm -f "$INSTALL_DIR/zimg"
fi

if [ "$ZIMG_BIN_FOUND" = true ]; then
    echo -e "Removing $INSTALL_DIR/zimg.bin..."
    sudo rm -f "$INSTALL_DIR/zimg.bin"
fi

if [ "$SHARE_DIR_FOUND" = true ]; then
    echo -e "Removing $SHARE_DIR..."
    sudo rm -rf "$SHARE_DIR"
fi

# Completion
echo -e "${GREEN}zimg has been successfully uninstalled!${NC}"
play_completion_sound

exit 0
