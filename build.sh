#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════╗"
echo "║             zimg build             ║"
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
    echo "This build script supports macOS and Linux only."
    exit 1
fi

# Check for Zig compiler
if ! command -v zig &> /dev/null; then
    echo -e "${RED}Zig compiler not found!${NC}"
    
    if [[ "$OS" == "macos" ]]; then
        echo -e "${YELLOW}Installing Zig using Homebrew...${NC}"
        if ! command -v brew &> /dev/null; then
            echo -e "${RED}Homebrew not found. Please install it first:${NC}"
            echo "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            exit 1
        fi
        brew install zig
    elif [[ "$OS" == "linux" ]]; then
        echo -e "${RED}Please install Zig manually:${NC}"
        echo "Visit https://ziglang.org/download/ or use your distribution's package manager"
        exit 1
    fi
fi

# Check for dependencies
echo -e "${BLUE}Checking dependencies...${NC}"

# SDL2 and SDL2_image
if [[ "$OS" == "macos" ]]; then
    if ! brew list SDL2 &> /dev/null || ! brew list SDL2_image &> /dev/null; then
        echo -e "${YELLOW}Installing SDL2 and SDL2_image using Homebrew...${NC}"
        brew install sdl2 sdl2_image
    else
        echo -e "${GREEN}SDL2 and SDL2_image already installed${NC}"
    fi
elif [[ "$OS" == "linux" ]]; then
    if command -v apt-get &> /dev/null; then
        echo -e "${YELLOW}Checking/installing dependencies with apt...${NC}"
        if ! dpkg -s libsdl2-dev libsdl2-image-dev &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y libsdl2-dev libsdl2-image-dev
        else
            echo -e "${GREEN}SDL2 and SDL2_image already installed${NC}"
        fi
    elif command -v dnf &> /dev/null; then
        echo -e "${YELLOW}Checking/installing dependencies with dnf...${NC}"
        sudo dnf install -y SDL2-devel SDL2_image-devel
    elif command -v pacman &> /dev/null; then
        echo -e "${YELLOW}Checking/installing dependencies with pacman...${NC}"
        sudo pacman -S --needed sdl2 sdl2_image
    else
        echo -e "${RED}Unsupported package manager.${NC}"
        echo "Please install SDL2 and SDL2_image development packages manually."
        exit 1
    fi
fi

# Check for Python 3
echo -e "${BLUE}Checking for Python 3...${NC}"
if ! command -v python3 &> /dev/null; then
    echo -e "${YELLOW}Python 3 not found. Trying to install...${NC}"
    if [[ "$OS" == "macos" ]]; then
        brew install python
    elif [[ "$OS" == "linux" ]]; then
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip python3-venv
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y python3 python3-pip python3-venv
        elif command -v pacman &> /dev/null; then
            sudo pacman -S --needed python python-pip
        else
            echo -e "${RED}Couldn't install Python 3. Please install it manually.${NC}"
            exit 1
        fi
    fi
fi

# Check again for Python 3
if ! command -v python3 &> /dev/null; then
    # Some systems use 'python' instead of 'python3' for Python 3
    if command -v python &> /dev/null; then
        PYTHON_CMD="python"
    else
        echo -e "${RED}Python 3 installation failed or not found.${NC}"
        echo "Please install Python 3 manually and run this script again."
        exit 1
    fi
else
    PYTHON_CMD="python3"
fi

# Build zimg
echo -e "${BLUE}Building zimg...${NC}"
zig build -Doptimize=ReleaseSafe

# Check if the build was successful
if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}"

# Install
echo -e "${BLUE}Installing zimg to $INSTALL_DIR...${NC}"
if [ ! -d "$INSTALL_DIR" ]; then
    sudo mkdir -p "$INSTALL_DIR"
fi

# Create share directory for upscaler
echo -e "${BLUE}Setting up upscaler in $SHARE_DIR...${NC}"
sudo mkdir -p "$SHARE_DIR/upscale"

# Copy binary to installation directory
sudo cp zig-out/bin/zimg "$INSTALL_DIR"

# Make executable
sudo chmod +x "$INSTALL_DIR/zimg"

# Copy upscaler files
echo -e "${BLUE}Installing upscaler component...${NC}"
sudo cp -r upscale/* "$SHARE_DIR/upscale/"

# Create wrapper script to run zimg from the correct directory
echo -e "${BLUE}Creating wrapper script...${NC}"
cat > zimg_wrapper.sh << EOF
#!/bin/bash
cd $SHARE_DIR
$INSTALL_DIR/zimg.bin "\$@"
EOF

# Make wrapper executable and move the original binary
sudo chmod +x zimg_wrapper.sh
sudo mv "$INSTALL_DIR/zimg" "$INSTALL_DIR/zimg.bin"
sudo cp zimg_wrapper.sh "$INSTALL_DIR/zimg"
rm zimg_wrapper.sh

# Set up virtual environment for upscaler
echo -e "${BLUE}Setting up Python virtual environment for upscaler...${NC}"
cd "$SHARE_DIR"
sudo $PYTHON_CMD -m venv upscale/venv

# Activate virtual environment and install dependencies
if [[ "$OS" == "macos" || "$OS" == "linux" ]]; then
    echo -e "${BLUE}Installing Python dependencies...${NC}"
    sudo bash -c "source $SHARE_DIR/upscale/venv/bin/activate && pip install -r $SHARE_DIR/upscale/requirements.txt"
fi

echo -e "${GREEN}Installation complete!${NC}"
echo -e "You can now run zimg by typing ${YELLOW}zimg${NC} in your terminal."
echo -e "Usage examples:"
echo -e "  ${YELLOW}zimg${NC}                     # View images in current directory"
echo -e "  ${YELLOW}zimg /path/to/images${NC}     # View images in specified directory"
echo -e ""
echo -e "${BLUE}Upscaler features:${NC}"
echo -e "  Press ${YELLOW}u${NC} to upscale the current image (2x)"
echo -e "  Press ${YELLOW}2${NC}, ${YELLOW}3${NC}, or ${YELLOW}4${NC} to upscale with specific factors" 