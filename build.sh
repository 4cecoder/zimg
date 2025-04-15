#!/bin/bash
set -e

# Version information
VERSION="1.0.0"
BUILD_DATE=$(date "+%Y-%m-%d")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default options
OPTIMIZE="ReleaseSafe"
INSTALL=true
CLEAN=false
VERBOSE=false
BUILD_TESTS=false
PARALLEL=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "1")

# Function to play success sound
play_sound() {
    local sound_type=$1
    if [[ "$OS" == "macos" ]]; then
        # macOS - use afplay
        if [[ "$sound_type" == "success" ]]; then
            afplay /System/Library/Sounds/Glass.aiff &>/dev/null &
        elif [[ "$sound_type" == "error" ]]; then
            afplay /System/Library/Sounds/Basso.aiff &>/dev/null &
        fi
    elif [[ "$OS" == "linux" ]]; then
        # Try different sound players available on Linux
        if command -v paplay &>/dev/null; then
            if [[ "$sound_type" == "success" ]]; then
                paplay /usr/share/sounds/freedesktop/stereo/complete.oga &>/dev/null || true
            elif [[ "$sound_type" == "error" ]]; then
                paplay /usr/share/sounds/freedesktop/stereo/dialog-error.oga &>/dev/null || true
            fi
        elif command -v aplay &>/dev/null; then
            if [[ "$sound_type" == "success" ]]; then
                aplay -q /usr/share/sounds/sound-icons/glass-water-1.wav &>/dev/null || true
            elif [[ "$sound_type" == "error" ]]; then
                aplay -q /usr/share/sounds/sound-icons/percussion-50.wav &>/dev/null || true
            fi
        fi
    fi
}

# Function to display errors
error() {
    echo -e "${RED}${BOLD}ERROR:${NC} $1"
    play_sound "error"
    exit 1
}

# Function to display warnings
warning() {
    echo -e "${YELLOW}${BOLD}WARNING:${NC} $1"
}

# Function to display success messages
success() {
    echo -e "${GREEN}${BOLD}SUCCESS:${NC} $1"
    play_sound "success"
}

# Function to display info messages
info() {
    echo -e "${BLUE}${BOLD}INFO:${NC} $1"
}

# Function to display step messages
step() {
    echo -e "${CYAN}${BOLD}==> ${NC}${BOLD}$1${NC}"
}

# Function to display help
show_help() {
    echo -e "${BOLD}ZIMG Build Script ${VERSION}${NC}"
    echo
    echo "Usage: ./build.sh [options]"
    echo
    echo "Options:"
    echo "  -h, --help             Show this help message"
    echo "  -d, --debug            Build with debug symbols (Debug)"
    echo "  -r, --release-safe     Build with safety checks (ReleaseSafe, default)"
    echo "  -f, --release-fast     Build with speed optimizations (ReleaseFast)"
    echo "  -s, --release-small    Build with size optimizations (ReleaseSmall)"
    echo "  -c, --clean            Clean build artifacts before building"
    echo "  -n, --no-install       Build only, skip installation"
    echo "  -v, --verbose          Show verbose build output"
    echo "  -t, --test             Build and run tests"
    echo "  -j, --jobs N           Set number of parallel build jobs (default: auto)"
    echo
    echo "Examples:"
    echo "  ./build.sh             Build with default options (ReleaseSafe)"
    echo "  ./build.sh --debug     Build with debug symbols"
    echo "  ./build.sh -f -c       Build for speed and clean first"
    echo "  ./build.sh -n          Build without installing"
    echo
}

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--debug)
            OPTIMIZE="Debug"
            shift
            ;;
        -r|--release-safe)
            OPTIMIZE="ReleaseSafe"
            shift
            ;;
        -f|--release-fast)
            OPTIMIZE="ReleaseFast"
            shift
            ;;
        -s|--release-small)
            OPTIMIZE="ReleaseSmall"
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -n|--no-install)
            INSTALL=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--test)
            BUILD_TESTS=true
            shift
            ;;
        -j|--jobs)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                PARALLEL="$2"
                shift 2
            else
                error "Option --jobs requires a numeric argument"
            fi
            ;;
        *)
            warning "Unknown option: $1"
            shift
            ;;
    esac
done

# Print banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║                 zimg build script                 ║"
echo "║                 version ${VERSION}                    ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${NC}"

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    info "Detected macOS system"
    INSTALL_DIR="/usr/local/bin"
    SHARE_DIR="/usr/local/share/zimg"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    info "Detected Linux system"
    INSTALL_DIR="/usr/local/bin"
    SHARE_DIR="/usr/local/share/zimg"
else
    error "Unsupported OS: $OSTYPE (This build script supports macOS and Linux only)"
fi

# Display build configuration
echo "Build configuration:"
echo "  - OS: $OS"
echo "  - Optimization: $OPTIMIZE"
echo "  - Install: $INSTALL"
echo "  - Parallel jobs: $PARALLEL"
echo "  - Clean build: $CLEAN"
echo "  - Build tests: $BUILD_TESTS"
echo "  - Verbose: $VERBOSE"
echo

# Check for Zig compiler and get version
if ! command -v zig &>/dev/null; then
    warning "Zig compiler not found, attempting to install..."
    
    if [[ "$OS" == "macos" ]]; then
        if ! command -v brew &>/dev/null; then
            error "Homebrew not found. Please install it first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        fi
        
        step "Installing Zig using Homebrew..."
        brew install zig || error "Failed to install Zig"
    elif [[ "$OS" == "linux" ]]; then
        error "Please install Zig manually: visit https://ziglang.org/download/ or use your distribution's package manager"
    fi
fi

# Check Zig version
ZIG_VERSION=$(zig version)
info "Using Zig version: $ZIG_VERSION"

# Check for dependencies
step "Checking dependencies..."

# SDL2 and SDL2_image
if [[ "$OS" == "macos" ]]; then
    if ! brew list SDL2 &>/dev/null || ! brew list SDL2_image &>/dev/null; then
        step "Installing SDL2 and SDL2_image using Homebrew..."
        brew install sdl2 sdl2_image || error "Failed to install SDL2 dependencies"
    else
        info "SDL2 and SDL2_image already installed"
    fi
elif [[ "$OS" == "linux" ]]; then
    if command -v apt-get &>/dev/null; then
        if ! dpkg -s libsdl2-dev libsdl2-image-dev &>/dev/null; then
            step "Installing dependencies with apt..."
            sudo apt-get update
            sudo apt-get install -y libsdl2-dev libsdl2-image-dev || error "Failed to install SDL2 dependencies"
        else
            info "SDL2 and SDL2_image already installed"
        fi
    elif command -v dnf &>/dev/null; then
        step "Installing dependencies with dnf..."
        sudo dnf install -y SDL2-devel SDL2_image-devel || error "Failed to install SDL2 dependencies"
    elif command -v pacman &>/dev/null; then
        step "Installing dependencies with pacman..."
        sudo pacman -S --needed sdl2 sdl2_image || error "Failed to install SDL2 dependencies"
    else
        warning "Unsupported package manager. Please install SDL2 and SDL2_image development packages manually."
    fi
fi

# Check for Python 3
step "Checking for Python 3..."
if ! command -v python3 &>/dev/null; then
    warning "Python 3 not found. Trying to install..."
    if [[ "$OS" == "macos" ]]; then
        brew install python || error "Failed to install Python 3"
    elif [[ "$OS" == "linux" ]]; then
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip python3-venv || error "Failed to install Python 3"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y python3 python3-pip python3-venv || error "Failed to install Python 3"
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --needed python python-pip || error "Failed to install Python 3"
        else
            error "Couldn't install Python 3. Please install it manually."
        fi
    fi
fi

# Check again for Python 3
if ! command -v python3 &>/dev/null; then
    # Some systems use 'python' instead of 'python3' for Python 3
    if command -v python &>/dev/null; then
        PYTHON_CMD="python"
        info "Using 'python' command (ensure it's Python 3)"
    else
        error "Python 3 installation failed or not found. Please install Python 3 manually and run this script again."
    fi
else
    PYTHON_CMD="python3"
    PYTHON_VERSION=$($PYTHON_CMD --version)
    info "Using $PYTHON_VERSION"
fi

# Clean build artifacts if requested
if [[ "$CLEAN" == true ]]; then
    step "Cleaning build artifacts..."
    rm -rf zig-cache zig-out
    info "Build directory cleaned"
fi

# Create version info
step "Creating build information..."
mkdir -p src
cat > src/version.zig << EOF
// Auto-generated by build.sh, do not edit manually
pub const VERSION = "${VERSION}";
pub const BUILD_DATE = "${BUILD_DATE}";
pub const OPTIMIZE = "${OPTIMIZE}";
pub const OS = "${OS}";
EOF

# Build zimg
step "Building zimg with ${OPTIMIZE} optimization..."

# Collect build flags
BUILD_FLAGS=("-Doptimize=${OPTIMIZE}")

if [[ "$BUILD_TESTS" == true ]]; then
    BUILD_FLAGS+=("-Dtest")
fi

# Set verbosity
if [[ "$VERBOSE" == true ]]; then
    BUILD_FLAGS+=("--verbose")
fi

# Build command
BUILD_CMD="zig build ${BUILD_FLAGS[*]}"
if [[ "$PARALLEL" -gt 1 ]]; then
    BUILD_CMD="$BUILD_CMD -j$PARALLEL"
fi

if [[ "$VERBOSE" == true ]]; then
    info "Build command: $BUILD_CMD"
fi

# Run the build
eval $BUILD_CMD

# Check if the build was successful
if [ $? -ne 0 ]; then
    error "Build failed!"
fi

success "Build completed successfully"

# Run tests if requested
if [[ "$BUILD_TESTS" == true ]]; then
    step "Running tests..."
    zig test src/main.zig || warning "Some tests failed"
fi

# Install if requested
if [[ "$INSTALL" == true ]]; then
    step "Installing zimg to $INSTALL_DIR..."
    if [ ! -d "$INSTALL_DIR" ]; then
        sudo mkdir -p "$INSTALL_DIR" || error "Failed to create installation directory"
    fi

    # Create share directory for upscaler
    step "Setting up upscaler in $SHARE_DIR..."
    sudo mkdir -p "$SHARE_DIR/upscale" || error "Failed to create upscaler directory"

    # Copy binary to installation directory
    sudo cp zig-out/bin/zimg "$INSTALL_DIR" || error "Failed to copy binary"

    # Make executable
    sudo chmod +x "$INSTALL_DIR/zimg" || error "Failed to set executable permissions"

    # Copy upscaler files
    step "Installing upscaler component..."
    sudo cp -r upscale/* "$SHARE_DIR/upscale/" || error "Failed to copy upscaler files"

    # Create wrapper script to run zimg from the correct directory
    step "Creating wrapper script..."
    cat > zimg_wrapper.sh << EOF
#!/bin/bash
# ZIMG Launcher v${VERSION}
# Generated on ${BUILD_DATE}
cd $SHARE_DIR
$INSTALL_DIR/zimg.bin "\$@"
EOF

    # Make wrapper executable and move the original binary
    sudo chmod +x zimg_wrapper.sh || error "Failed to set wrapper permissions"
    sudo mv "$INSTALL_DIR/zimg" "$INSTALL_DIR/zimg.bin" || error "Failed to rename binary"
    sudo cp zimg_wrapper.sh "$INSTALL_DIR/zimg" || error "Failed to install wrapper"
    rm zimg_wrapper.sh

    # Set up virtual environment for upscaler
    step "Setting up Python virtual environment for upscaler..."
    cd "$SHARE_DIR"
    sudo $PYTHON_CMD -m venv upscale/venv || error "Failed to create Python virtual environment"

    # Activate virtual environment and install dependencies
    if [[ "$OS" == "macos" || "$OS" == "linux" ]]; then
        step "Installing Python dependencies..."
        sudo bash -c "source $SHARE_DIR/upscale/venv/bin/activate && pip install -r $SHARE_DIR/upscale/requirements.txt" || warning "Failed to install some Python dependencies"
    fi

    success "Installation complete"
    echo 
    echo -e "You can now run zimg by typing ${YELLOW}zimg${NC} in your terminal."
    echo -e "Usage examples:"
    echo -e "  ${YELLOW}zimg${NC}                     # View images in current directory"
    echo -e "  ${YELLOW}zimg /path/to/images${NC}     # View images in specified directory"
    echo -e ""
    echo -e "Upscaler features:"
    echo -e "  Press ${YELLOW}u${NC} to upscale the current image (2x)"
    echo -e "  Press ${YELLOW}2${NC}, ${YELLOW}3${NC}, or ${YELLOW}4${NC} to upscale with specific factors"
else
    echo 
    echo -e "${YELLOW}Note:${NC} Installation was skipped. The compiled binary is available at:"
    echo -e "  ${YELLOW}./zig-out/bin/zimg${NC}"
    echo
fi 