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
        # macOS - use afplay for build success
        if [[ "$sound_type" == "success" ]]; then
            afplay /System/Library/Sounds/Glass.aiff
        elif [[ "$sound_type" == "error" ]]; then
            say "Build failed"
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
    play_sound "error"
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

    # Print OS-specific success message
    if [[ "$OS" == "macos" ]]; then
        success "Installation complete! View your images and manga with zimg my zigga!"
        # Array of Zig-related jokes in Rick and Morty style, fully uncensored crude rants with novel jabs at other languages, a ton of dirty, horrible rants with sexual refs and episode lore
        JOKES=(
            "Zig's so fucking fast, it makes C look like Jerry's shitty code after a damnn interdimensional bender, burp! I clocked it against Python and that slow-ass snake got left in the dust!"
            "Zig compiles so damn clean, I'd ditch Rust's bitchy, overbearing safety crap for this sweet-ass, no-bullshit ride any day—screw that orange crab!"
            "Zig's memory safety is tighter than Morty's ass when I drag him to a fucking Gazorpazorp fight club, no leaks here, bitch, unlike Java's garbage-ass collector!"
            "Coding in Zig is like portal-hopping with my drunk ass—pure fucking chaos, no crashes, just raw power, Wubba Lubba Dub Dub, while Go sits there like a boring-ass Morty with no balls!"
            "Zig's so fucking slick, it makes C++ look like a damnn clusterfuck of Summer's teenage drama—total shitshow, burp, while Zig just owns the multiverse!"
            "Zig runs so damn hard, I'd bet it could outcode Ruby's whiny-ass framework nonsense while I'm passed out in a fucking alien bar—screw that hipster trash!"
            "Zig's error handling is so fucking tight, it shames PHP's sloppy-ass, bug-ridden dumpster fire—hell, even Morty could code better than that shit, bitch!"
            "Zig's build speed is like me on a fucking rampage—unstoppable, unlike Swift's prissy-ass, overpriced Apple fanboy crap that takes forever to do jack shit!"
            "Zig's raw fucking power makes JavaScript look like Birdperson's sad-ass poetry—total garbage, burp, while Zig just rips through code like a portal gun blast!"
            "Zig's so damnn badass, it makes Haskell's nerdy-ass, math-wanking syntax look like a fucking snoozefest—screw that pretentious crap, let's code dirty!"
            "Zig cuts through memory bugs like my fucking laser through a Gromflomite army—no mercy, bitch, while C# sits there like a bloated-ass Microsoft turd!"
            "Zig's so fucking lean, it makes Perl look like a damnn ancient pile of unreadable shit—burp, even Rick Sanchez wouldn't touch that mess with a ten-foot pole!"
            "Zig gets me so fucking hard, it's like banging a Plumbus-powered sexbot—pure ecstasy, while TypeScript's limp-dick error checking just blue-balls the shit outta me!"
            "Zig's so fucking raw, it makes Kotlin look like Morty's incest-baby Naruto—fucked up and wrong, burp, while Zig just fucks shit up the right way, hardcore!"
            "Zig's performance gives me a raging hard-on, unlike Dart's flaccid-ass, Google-approved bullshit—couldn't get it up if it tried, bitch, while Zig pounds code like a Squanchy orgy!"
            "Zig's so fucking savage, it makes Scala look like Beth's horse-surgeon side gig—pretentious fuckin' garbage, burp, while Zig slices bugs like my portal gun through a Unity Tree!"
            "Zig's code is tighter than my grip on a Szechuan sauce stash—fuck yeah, while Lua's loose-ass scripting makes me wanna puke like after a night with Mr. Poopybutthole!"
            "Zig's so fucking brutal, it makes Groovy look like a damnn hippy circle-jerk—total shit, bitch, while Zig smashes bugs like I smashed that Federation prison!"
            "Zig gets my dick harder than a Vindicators mission gone wrong—pure fuckin' adrenaline, while Elixir's hipster-ass functional crap is softer than Morty's whiny bullshit!"
            "Zig's so fucking nasty, it makes Cobol look like the ancient-ass shit Jerry's dad would code—fuckin' relic, burp, while Zig's rawer than a Gazorpian mating ritual!"
        )
        # Pick a random joke
        JOKE_INDEX=$((RANDOM % ${#JOKES[@]}))
        SELECTED_JOKE="${JOKES[$JOKE_INDEX]}"
        echo -e "${CYAN}${BOLD}Rick's Zig Rant:${NC} $SELECTED_JOKE"
        # No censorship for spoken version, fully unfiltered audio as requested
        say "Installation complete! View your images and manga with zimg! $SELECTED_JOKE"
    else
        success "Installation complete"
    fi
    
    echo
    echo -e "You can now run zimg by typing zimg in your terminal."
    echo -e "Usage examples:"
    echo -e "  zimg /path/to/images     # View images in specified directory (absolute path recommended)"
    echo -e "  zimg \"\\$(pwd)\"           # View images in current directory"
    echo
    echo -e "Upscaler features:"
    echo -e "  Press u to upscale the current image (2x)"
    echo -e "  Press 2, 3, or 4 to upscale with specific factors"
else
    echo
    echo -e "${YELLOW}Note:${NC} Installation was skipped. The compiled binary is available at:"
    echo -e "  ${YELLOW}./zig-out/bin/zimg${NC}"
    echo
fi