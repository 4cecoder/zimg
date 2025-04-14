import sys
import platform

try:
    import cv2
    import cv2.dnn_superres
    import numpy as np
except ImportError:
    print("ERROR: OpenCV package not found.")
    print("Please install required dependencies with:")
    print("  pip install -r upscale/requirements.txt")
    print("Or if using a virtual environment:")
    print("  source upscale/venv/bin/activate")
    print("  pip install -r upscale/requirements.txt")
    sys.exit(1)

import os
import urllib.request
import argparse
import tempfile
import zipfile
import shutil
import time
import multiprocessing
from concurrent.futures import ThreadPoolExecutor
import datetime

# Check for Apple Silicon
IS_APPLE_SILICON = platform.system() == 'Darwin' and platform.machine().startswith('arm')

# Path to store models
MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models")

# Progress tracking
class ProgressTracker:
    def __init__(self, total, description="Processing"):
        self.total = total
        self.current = 0
        self.start_time = time.time()
        self.description = description
        self.last_update_time = 0
        self.update_interval = 0.5  # Update every 0.5 seconds
        
    def update(self, amount=1):
        self.current += amount
        
        # Only update display if enough time has passed (to avoid flickering)
        current_time = time.time()
        if current_time - self.last_update_time >= self.update_interval:
            self.display()
            self.last_update_time = current_time
            
    def display(self):
        if self.total <= 0:
            return
            
        percent = min(100, self.current * 100 / self.total)
        
        # Calculate ETA
        elapsed = time.time() - self.start_time
        if self.current > 0:
            eta_seconds = elapsed * (self.total - self.current) / self.current
            eta = str(datetime.timedelta(seconds=int(eta_seconds)))
        else:
            eta = "Unknown"
            
        # Create progress bar
        bar_length = 30
        filled_length = int(bar_length * self.current / self.total)
        bar = '█' * filled_length + '░' * (bar_length - filled_length)
        
        # Print progress
        sys.stdout.write(f"\r{self.description}: [{bar}] {percent:.1f}% | {self.current}/{self.total} | ETA: {eta}    ")
        sys.stdout.flush()
        
    def complete(self):
        self.current = self.total
        self.display()
        sys.stdout.write("\n")
        sys.stdout.flush()
        
        elapsed = time.time() - self.start_time
        print(f"Completed in {str(datetime.timedelta(seconds=int(elapsed)))}")

def ensure_models_directory():
    """Create the models directory if it doesn't exist."""
    if not os.path.exists(MODELS_DIR):
        os.makedirs(MODELS_DIR)

def download_edsr_models():
    """
    Download EDSR models from OpenCV's GitHub releases.
    """
    # Models repo URL
    models_url = "https://github.com/Saafke/EDSR_Tensorflow/archive/master.zip"
    
    ensure_models_directory()
    
    # Check if models are already downloaded
    if (os.path.exists(os.path.join(MODELS_DIR, "EDSR_x2.pb")) and
        os.path.exists(os.path.join(MODELS_DIR, "EDSR_x3.pb")) and
        os.path.exists(os.path.join(MODELS_DIR, "EDSR_x4.pb"))):
        print("All EDSR models already downloaded.")
        return
    
    # Create a temporary directory
    with tempfile.TemporaryDirectory() as temp_dir:
        zip_path = os.path.join(temp_dir, "edsr_models.zip")
        
        # Download the zip file
        print(f"Downloading EDSR models from {models_url}...")
        download_tracker = ProgressTracker(100, "Downloading")
        
        try:
            def download_progress(block_num, block_size, total_size):
                if total_size > 0:
                    downloaded = min(block_num * block_size, total_size)
                    percent = int(downloaded * 100 / total_size)
                    download_tracker.current = percent
                    download_tracker.display()
                    
            urllib.request.urlretrieve(models_url, zip_path, reporthook=download_progress)
            download_tracker.complete()
        except Exception as e:
            print(f"\nError downloading models: {e}")
            print("Please download the models manually and place them in the 'models' directory.")
            sys.exit(1)
        
        # Extract the zip file
        print("Extracting models...")
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(temp_dir)
            
            # Move the model files to our models directory
            models_source_dir = os.path.join(temp_dir, "EDSR_Tensorflow-master", "models")
            
            for scale in [2, 3, 4]:
                model_name = f"EDSR_x{scale}.pb"
                source_path = os.path.join(models_source_dir, model_name)
                dest_path = os.path.join(MODELS_DIR, model_name)
                
                if os.path.exists(source_path):
                    shutil.copy2(source_path, dest_path)
                    print(f"Model {model_name} copied to {dest_path}")
                else:
                    print(f"Warning: Could not find {model_name} in the downloaded package")
                    
            print("Models extraction complete.")
            
        except Exception as e:
            print(f"Error extracting models: {e}")
            print("Please download the models manually and place them in the 'models' directory.")
            sys.exit(1)

def process_tile(args):
    """Process a single image tile using the super-resolution model."""
    sr, tile, tracker = args
    result = sr.upsample(tile)
    if tracker:
        tracker.update()
    return result

def upscale_image(input_path, output_path, scale=2, use_gpu=True, tile_size=1024):
    """
    Upscale a manga image using OpenCV's super-resolution with the EDSR model.
    
    Args:
        input_path (str): Path to the input manga image.
        output_path (str): Path where the upscaled image will be saved.
        scale (int): Scale factor for upscaling (e.g., 2, 3, 4). Default is 2.
        use_gpu (bool): Whether to use GPU acceleration if available.
        tile_size (int): Size of tiles for processing large images. Set to 0 to disable tiling.
    
    Raises:
        ValueError: If the scale factor is not supported.
        FileNotFoundError: If the input image cannot be found or loaded.
    """
    # Define supported scale factors
    supported_scales = [2, 3, 4]
    if scale not in supported_scales:
        raise ValueError(f"Scale {scale} is not supported. Supported scales are {supported_scales}.")
    
    # Set up model file details
    model_name = f'EDSR_x{scale}.pb'
    model_path = os.path.join(MODELS_DIR, model_name)
    
    # Download the models if necessary
    if not os.path.exists(model_path):
        download_edsr_models()
    
    # Check if model exists after download attempt
    if not os.path.exists(model_path):
        print(f"Error: Model file {model_path} not found even after download attempt.")
        print("Please ensure you have an internet connection or download the model manually.")
        sys.exit(1)
    
    # Read the input image
    try:
        image = cv2.imread(input_path)
        if image is None:
            raise FileNotFoundError(f"Input image not found or could not be read: {input_path}")
    except Exception as e:
        print(f"Error reading input image: {e}")
        sys.exit(1)
    
    print(f"Input image size: {image.shape[1]}x{image.shape[0]} pixels")
    
    # Initialize the super-resolution object
    sr = cv2.dnn_superres.DnnSuperResImpl_create()
    
    # Load the model
    try:
        print(f"Loading model {model_path}...")
        sr.readModel(model_path)
        print("Model loaded successfully.")
    except Exception as e:
        print(f"Error loading model: {e}")
        print(f"The model file may be corrupted. Try deleting {model_path} and running the script again.")
        sys.exit(1)
    
    # Set the model type and scale factor
    sr.setModel('edsr', scale)
    
    # Attempt to use GPU acceleration
    if use_gpu:
        # Check if CUDA is available
        cuda_devices = cv2.cuda.getCudaEnabledDeviceCount() if hasattr(cv2, 'cuda') else 0
        
        if cuda_devices > 0:
            print(f"CUDA acceleration enabled with {cuda_devices} device(s)")
            sr.setPreferableBackend(cv2.dnn.DNN_BACKEND_CUDA)
            sr.setPreferableTarget(cv2.dnn.DNN_TARGET_CUDA)
        elif IS_APPLE_SILICON:
            # For Apple Silicon (M1/M2), try to use Metal
            print("Attempting to use Metal acceleration on Apple Silicon")
            try:
                sr.setPreferableBackend(cv2.dnn.DNN_BACKEND_OPENCV)
                cv2.ocl.setUseOpenCL(True)  # Enable OpenCL which can use Metal on macOS
                if cv2.ocl.useOpenCL():
                    print("OpenCL acceleration enabled (using Metal on Apple Silicon)")
                else:
                    print("OpenCL acceleration not available, using CPU")
            except Exception as e:
                print(f"Failed to enable Metal acceleration: {e}")
                print("Falling back to CPU processing")
        else:
            print("GPU acceleration not available, using CPU")
    
    # Perform upscaling with timing
    print("\nStarting upscaling process...")
    start_time = time.time()
    
    try:
        # Check if we need to use tiling (for large images)
        height, width = image.shape[:2]
        if tile_size > 0 and (width > tile_size or height > tile_size) and width * height > 1000000:
            print(f"Large image detected ({width}x{height}), using tiled processing")
            
            # Calculate tile dimensions
            upscaled = None
            tiles = []
            tile_positions = []
            
            # Create tiles with overlap
            overlap = 16  # Overlap pixels to avoid seam artifacts
            
            # Calculate number of tiles needed
            num_tiles_x = max(1, (width + tile_size - 1) // tile_size)
            num_tiles_y = max(1, (height + tile_size - 1) // tile_size)
            total_tiles = num_tiles_x * num_tiles_y
            
            print(f"Dividing image into {num_tiles_x}x{num_tiles_y} = {total_tiles} tiles...")
            
            # Create tiles
            for y in range(num_tiles_y):
                for x in range(num_tiles_x):
                    # Calculate tile coordinates with overlap
                    x_start = max(0, x * tile_size - overlap)
                    y_start = max(0, y * tile_size - overlap)
                    x_end = min(width, (x + 1) * tile_size + overlap)
                    y_end = min(height, (y + 1) * tile_size + overlap)
                    
                    # Extract tile
                    tile = image[y_start:y_end, x_start:x_end]
                    tiles.append(tile)
                    tile_positions.append((x_start, y_start, x_end, y_end))
            
            # Process tiles in parallel
            upscaled_tiles = []
            
            # Use multiprocessing to parallelize tile processing
            cpu_count = multiprocessing.cpu_count()
            print(f"Using {cpu_count} CPU cores for parallel processing")
            
            # Create progress tracker for tiles
            tile_tracker = ProgressTracker(total_tiles, "Processing tiles")
            
            with ThreadPoolExecutor(max_workers=cpu_count) as executor:
                # Pass the tracker to each tile processing job
                upscaled_tiles = list(executor.map(process_tile, [(sr, tile, tile_tracker) for tile in tiles]))
                
            tile_tracker.complete()
            
            # Create the final image
            print("Combining tiles into final image...")
            output_height = height * scale
            output_width = width * scale
            upscaled = np.zeros((output_height, output_width, 3), dtype=np.uint8)
            
            # Combine tiles, removing overlap
            combine_tracker = ProgressTracker(total_tiles, "Combining tiles")
            for i, ((x_start, y_start, x_end, y_end), tile) in enumerate(zip(tile_positions, upscaled_tiles)):
                # Calculate output tile position (scaled)
                out_x_start = max(0, x_start * scale)
                out_y_start = max(0, y_start * scale)
                out_x_end = min(output_width, x_end * scale)
                out_y_end = min(output_height, y_end * scale)
                
                # Calculate tile dimensions
                tile_height, tile_width = tile.shape[:2]
                
                # Calculate the portion of the tile to use (to match the output dimensions)
                tile_portion = tile[
                    0:min(tile_height, out_y_end - out_y_start),
                    0:min(tile_width, out_x_end - out_x_start)
                ]
                
                # Place the tile portion in the output image
                try:
                    upscaled[out_y_start:out_y_start + tile_portion.shape[0], 
                            out_x_start:out_x_start + tile_portion.shape[1]] = tile_portion
                except ValueError as e:
                    print(f"Error combining tile {i}: {e}")
                    print(f"Tile shape: {tile_portion.shape}, Target shape: {(out_y_end - out_y_start, out_x_end - out_x_start)}")
                
                combine_tracker.update()
                
            combine_tracker.complete()
        else:
            # For smaller images, process the whole image at once
            print(f"Upscaling image with scale factor {scale}x...")
            print("This may take a while for larger images. Please wait...")
            
            # For single image upscaling, create a simple spinner to show activity
            upscaling_done = False
            
            def show_spinner():
                spinner_chars = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
                i = 0
                start = time.time()
                while not upscaling_done:
                    elapsed = time.time() - start
                    minutes, seconds = divmod(int(elapsed), 60)
                    spinner = spinner_chars[i % len(spinner_chars)]
                    sys.stdout.write(f"\rUpscaling {spinner} Elapsed: {minutes:02d}:{seconds:02d}   ")
                    sys.stdout.flush()
                    time.sleep(0.1)
                    i += 1
                sys.stdout.write("\r" + " " * 50 + "\r")  # Clear the spinner line
                sys.stdout.flush()
            
            # Start spinner in a separate thread
            if width * height > 500000:  # Only show spinner for larger images
                from threading import Thread
                spinner_thread = Thread(target=show_spinner)
                spinner_thread.daemon = True
                spinner_thread.start()
            
            # Do the actual upscaling
            upscaled = sr.upsample(image)
            
            # Signal spinner to stop
            upscaling_done = True
            time.sleep(0.2)  # Give spinner time to exit
        
        # Calculate and display metrics
        end_time = time.time()
        elapsed_time = end_time - start_time
        original_megapixels = (width * height) / 1_000_000
        upscaled_megapixels = (upscaled.shape[1] * upscaled.shape[0]) / 1_000_000
        
        print(f"\nUpscaling completed in {elapsed_time:.2f} seconds")
        print(f"Processing speed: {original_megapixels / elapsed_time:.2f} MP/s input, {upscaled_megapixels / elapsed_time:.2f} MP/s output")
        print(f"Output image size: {upscaled.shape[1]}x{upscaled.shape[0]} pixels")
        
    except Exception as e:
        print(f"Error during upscaling: {e}")
        sys.exit(1)
    
    # Save the upscaled image
    try:
        print("Saving upscaled image...")
        cv2.imwrite(output_path, upscaled)
        print(f"Upscaled image saved to {output_path}")
    except Exception as e:
        print(f"Error saving output image: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Set up command-line argument parser
    parser = argparse.ArgumentParser(description="Upscale a manga image using OpenCV super-resolution.")
    parser.add_argument("input", help="Path to the input image")
    parser.add_argument("output", help="Path to the output image")
    parser.add_argument("--scale", type=int, default=2, choices=[2, 3, 4], 
                        help="Scale factor (2, 3, or 4). Default is 2.")
    parser.add_argument("--no-gpu", action="store_true", 
                        help="Disable GPU acceleration (use CPU only)")
    parser.add_argument("--tile-size", type=int, default=1024,
                        help="Size of tiles for processing large images. Set to 0 to disable tiling. Default is 1024.")
    
    # Parse arguments
    args = parser.parse_args()
    
    # Run the upscaling function
    upscale_image(
        args.input, 
        args.output, 
        scale=args.scale,
        use_gpu=not args.no_gpu,
        tile_size=args.tile_size
    )
