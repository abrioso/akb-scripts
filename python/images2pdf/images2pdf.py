#!/usr/bin/env python3
"""Convert the photos in a folder (HEIC, JPEG, PNG) into a single A4 PDF.

Each image is rotated according to its EXIF orientation, scaled down to fit an
A4 page at 150 DPI and centred on a white background. The PDF is written to the
parent directory of the input folder and named after it
(``photos/`` -> ``photos.pdf``).

Usage:
    python images2pdf.py /path/to/folder
"""

import re
import sys
import argparse
from pathlib import Path
from PIL import Image, ImageOps
import pillow_heif


WHITE = (255, 255, 255)
HIGH_BIT_DEPTH_MODES = {'I', 'I;16', 'I;16L', 'I;16B', 'I;16N'}
ALPHA_MODES = {'RGBA', 'RGBa', 'LA', 'La', 'PA'}


def natural_sort_key(path):
    """Sort key that orders file names case-insensitively, with numbers by value."""
    return [
        (0, int(part), '') if part.isdigit() else (1, 0, part.casefold())
        for part in re.split(r'(\d+)', path.name)
    ]


def normalize_image(img):
    """Return ``img`` as an RGB or RGBA image that Pillow can paste onto an RGB page.

    16-bit (and 32-bit integer) greyscale images are rescaled to 8 bits, since a
    plain conversion clips them. Images with transparency are returned as RGBA
    so the alpha channel can be used as a paste mask over a white background.
    Every other mode (L, P, CMYK, YCbCr, ...) is converted to RGB.
    """
    if img.mode in HIGH_BIT_DEPTH_MODES:
        # Scale the 0-65535 range down to 0-255 before converting to 8 bits
        img = img.convert('I').point(lambda v: v / 256).convert('L')

    has_alpha = img.mode in ALPHA_MODES or (
        img.mode == 'P' and 'transparency' in img.info
    )
    return img.convert('RGBA' if has_alpha else 'RGB')


def create_pdf_from_photos(folder_path):
    """Build ``<folder>.pdf`` next to ``folder_path`` from the images it contains."""
    # Resolve to an absolute path so relative paths such as '.' get a real name
    folder = Path(folder_path).resolve()

    if not folder.is_dir():
        print(f"Error: '{folder_path}' is not a valid folder.")
        sys.exit(1)

    # Register HEIC/HEIF support with Pillow
    pillow_heif.register_heif_opener()

    # Supported extensions
    valid_extensions = {'.heic', '.jpeg', '.jpg', '.png'}

    # List the supported files, skipping hidden ones (e.g. macOS '._*' metadata
    # files), in natural, case-insensitive order (IMG_2 before IMG_10)
    image_files = sorted(
        (
            f for f in folder.iterdir()
            if f.suffix.lower() in valid_extensions
            and not f.name.startswith('.')
            and f.is_file()
        ),
        key=natural_sort_key,
    )

    if not image_files:
        print("No supported images (HEIC, JPEG, PNG) found in the folder.")
        sys.exit(1)

    # A4 canvas at 150 DPI (a good balance between photo quality and PDF size)
    A4_W, A4_H = 1240, 1754
    pdf_pages = []

    for img_path in image_files:
        try:
            with Image.open(img_path) as src:
                # Essential for phone photos: rotate according to the EXIF orientation tag
                img = ImageOps.exif_transpose(src)

                # Bring every image mode to RGB, or RGBA when it has transparency
                img = normalize_image(img)

            # Scale down, keeping the aspect ratio, so the image fits the A4 page
            img.thumbnail((A4_W, A4_H), Image.Resampling.LANCZOS)

            # Create a white background and centre the image on it. PDF pages
            # cannot carry an alpha channel, so transparent areas are flattened
            # onto the white background by using the alpha channel as mask.
            canvas = Image.new('RGB', (A4_W, A4_H), WHITE)
            offset_x = (A4_W - img.width) // 2
            offset_y = (A4_H - img.height) // 2
            mask = img if img.mode == 'RGBA' else None
            canvas.paste(img, (offset_x, offset_y), mask)

            pdf_pages.append(canvas)
            print(f"Processed: {img_path.name}")

        except Exception as e:
            print(f"Warning: could not process '{img_path.name}'. Error: {e}")

    if pdf_pages:
        # Save the PDF in the parent directory of the photo folder
        output_pdf = folder.parent / f"{folder.name}.pdf"

        print(f"\nWriting {len(pdf_pages)} pages to the PDF...")

        # Pillow writes a multi-page PDF by saving the first page and appending the rest
        pdf_pages[0].save(
            output_pdf,
            "PDF",
            resolution=150.0,
            save_all=True,
            append_images=pdf_pages[1:]
        )
        print(f"Done! PDF saved to: {output_pdf}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Convert the photos (HEIC, JPEG, PNG) in a folder into an A4 PDF "
                    "with centred images. The PDF is saved next to the folder, "
                    "named after it."
    )
    parser.add_argument("folder", help="Path to the folder containing the photos.")
    args = parser.parse_args()

    create_pdf_from_photos(args.folder)
