# zimg

A simple, lightweight image viewer written in Zig using SDL2.

## Features

- View images from a specified directory
- Navigate between images using keyboard controls
- Automatic window resizing to fit image dimensions
- Preserves aspect ratio when displaying images
- Supports multiple image formats (PNG, JPG, JPEG, GIF, BMP, TIFF, WEBP)
- AI-powered image upscaling using EDSR super-resolution

## Dependencies

- [Zig](https://ziglang.org/) compiler
- SDL2
- SDL2_image
- Python 3.6+ (for upscaling feature)
- OpenCV Python package (for upscaling feature)

## Easy Installation

Use the provided build script to install zimg on macOS or Linux:

```bash
# Make the script executable (if it's not already)
chmod +x build.sh

# Build and install zimg
./build.sh

# Install Python dependencies (Option 1: System-wide)
pip install -r upscale/requirements.txt

# OR Install Python dependencies (Option 2: Virtual Environment - Recommended)
cd upscale
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows
pip install -r requirements.txt
```

The script will:
1. Detect your operating system
2. Install dependencies if needed (requires Homebrew on macOS, apt/dnf/pacman on Linux)
3. Build zimg with optimizations
4. Install the binary to `/usr/local/bin`

## Manual Building

If you prefer to build manually:

```bash
# Build the project
zig build

# Run with a specific directory
zig build run -- /path/to/images

# Install Python dependencies (see above for options)
```

## Usage

```bash
# View images in the current directory
zimg

# View images in a specific directory
zimg /path/to/images
```

## Controls

- `j` or `Down` or `Right`: Next image
- `k` or `Up` or `Left`: Previous image
- `u`: Upscale current image (2x)
- `2`: Upscale current image with 2x scale
- `3`: Upscale current image with 3x scale
- `4`: Upscale current image with 4x scale
- `q`: Quit

## Image Upscaling

The upscaling feature uses OpenCV's deep learning-based super-resolution with the EDSR model, which is particularly effective for manga/comic images with sharp lines and high contrast.

When you use the upscaling feature:
1. The first time you upscale at a specific scale (2x, 3x, or 4x), the necessary model will be downloaded
2. Upscaled images are saved with a suffix "_upscaledx2", "_upscaledx3", or "_upscaledx4" added to the filename
3. The upscaled image is automatically added to your viewing queue and displayed

### Virtual Environment Support

The application will automatically detect and use a Python virtual environment if it exists in any of these locations:
- `upscale/venv` (recommended)
- `upscale/.venv`
- `venv`
- `.venv`

Using a virtual environment is recommended to avoid conflicts with system Python packages.

## License

MIT 