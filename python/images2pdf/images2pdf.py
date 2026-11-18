#!/usr/bin/env python3
"""Convert the photos in a folder (HEIC, JPEG, PNG) into a single A4 PDF.

Each image is rotated according to its EXIF orientation, scaled down to fit an
A4 page at 150 DPI and centred on a white background. The PDF is written to the
parent directory of the input folder and named after it
(``photos/`` -> ``photos.pdf``).

Usage:
    python images2pdf.py /path/to/folder
"""

import sys
import argparse
from pathlib import Path
from PIL import Image, ImageOps
import pillow_heif


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

    # List the supported files and sort them alphabetically
    image_files = sorted([
        f for f in folder.iterdir()
        if f.suffix.lower() in valid_extensions and f.is_file()
    ])

    if not image_files:
        print("No supported images (HEIC, JPEG, PNG) found in the folder.")
        sys.exit(1)

    # A4 canvas at 150 DPI (a good balance between photo quality and PDF size)
    A4_W, A4_H = 1240, 1754
    pdf_pages = []

    for img_path in image_files:
        try:
            img = Image.open(img_path)

            # Essential for phone photos: rotate according to the EXIF orientation tag
            img = ImageOps.exif_transpose(img)

            # PDF pages cannot carry an alpha channel, so convert to RGB
            if img.mode in ('RGBA', 'P'):
                img = img.convert('RGB')

            # Scale down, keeping the aspect ratio, so the image fits the A4 page
            img.thumbnail((A4_W, A4_H), Image.Resampling.LANCZOS)

            # Create a white background and centre the image on it
            canvas = Image.new('RGB', (A4_W, A4_H), (255, 255, 255))
            offset_x = (A4_W - img.width) // 2
            offset_y = (A4_H - img.height) // 2
            canvas.paste(img, (offset_x, offset_y))

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
