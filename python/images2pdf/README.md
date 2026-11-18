# images2pdf

Converts every photo in a folder (HEIC, JPEG, PNG) into a single A4 PDF, one
photo per page.

- Photos are rotated according to their EXIF orientation, so phone pictures
  are not sideways.
- Each photo is scaled down to fit an A4 page at 150 DPI (1240×1754 px),
  keeping its proportions, and centred on a white background. Smaller photos
  are not enlarged.
- Transparent areas (PNG) are filled with white.
- Pages follow the file names in natural, case-insensitive order
  (`IMG_2` comes before `IMG_10`).
- Hidden files (names starting with `.`, such as macOS `._*` files) and
  subfolders are ignored.

## Requirements

- Python 3.10 or later (required by Pillow 12)
- [Pillow](https://pypi.org/project/pillow/) and
  [pillow-heif](https://pypi.org/project/pillow-heif/), pinned in
  `requirements.txt`

## Installation

Create a virtual environment inside this folder and install the dependencies.
The `.venv/` folder is ignored by git.

macOS / Linux:

```bash
cd python/images2pdf
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Windows (PowerShell):

```powershell
cd python\images2pdf
py -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Usage

```bash
python images2pdf.py /path/to/photo_folder
```

The PDF is written to the **parent** directory of the folder and takes the
folder's name. For example, `~/Pictures/holidays/` produces
`~/Pictures/holidays.pdf`.

> An existing PDF with the same name is overwritten without asking.

Progress messages go to stdout; warnings for images that cannot be read and
errors go to stderr.

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | PDF created (some images may have been skipped with a warning) |
| `1`  | The path is not a folder, it has no supported images, or none of them could be read |
| `2`  | Invalid command-line arguments |

## Limitations

- Page size (A4), resolution (150 DPI) and JPEG quality are fixed.
- All pages are kept in memory until the PDF is written (about 6.5 MB per
  page), so very large folders need a lot of RAM.
