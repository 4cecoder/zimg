# Image Upscaler for ZIMG

This module provides image upscaling functionality using OpenCV's deep learning-based super-resolution with the EDSR model. It's specifically designed to enhance manga/comic images while preserving sharp lines and details.

## Installation

### Option 1: System-wide Installation

1. Ensure you have Python 3.6+ installed
2. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

### Option 2: Virtual Environment (Recommended)

1. Create a virtual environment in the upscale directory:
   ```bash
   # Navigate to the upscale directory
   cd upscale
   
   # Create the virtual environment
   python -m venv venv
   
   # Activate the virtual environment
   # On Windows:
   venv\Scripts\activate
   # On macOS/Linux:
   source venv/bin/activate
   
   # Install dependencies
   pip install -r requirements.txt
   ```

The Zig application will automatically detect and use the virtual environment if it exists in any of these locations:
- `upscale/venv`
- `upscale/.venv`
- `venv`
- `.venv`

## Usage

### From Command Line

```bash
python main.py input.png output.png --scale 2
```

Parameters:
- `input.png`: Path to your input image
- `output.png`: Path where the upscaled image will be saved
- `--scale`: Optional scale factor (2, 3, or 4). Default is 2

### From Zig

This script is designed to be called from the ZIMG editor. The first time you run it with a specific scale factor, it will download the corresponding EDSR model from the OpenCV repository.

## Notes

- Supports scale factors of 2x, 3x, or 4x
- The EDSR model preserves sharp lines and details better than traditional interpolation methods
- Models are downloaded automatically on first use 