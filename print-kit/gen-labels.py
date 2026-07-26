#!/usr/bin/env python3
"""Generate a print-ready PDF of unique QR-code labels for Avery 64510.

Target stock: Avery 64510 -- Waterproof Glossy White polyester film,
2" x 2" square labels, 12 per US-letter sheet (3 columns x 4 rows).
Print on a LASER printer or pigment-based inkjet only; dye-based
inkjet smears on this film when wet.

Each label carries one unique QR code (error correction H), the
human-readable URL beneath it for finders who won't scan a stranger's
QR, and the tag number in a corner for your records.

Usage:
    python3 gen-labels.py slugs.txt labels.pdf
    python3 gen-labels.py slugs.txt labels.pdf --base https://other.example

Page 1 of the output is a calibration page: print it on PLAIN PAPER
first, hold it against a label sheet up to the light, and confirm the
cell outlines sit on the die-cut squares. If they're uniformly shifted,
re-run with --xshift / --yshift (in inches; positive = right / down).
"""

import argparse
import io
import json
import os
import re
import sys

import qrcode
from qrcode.constants import ERROR_CORRECT_H, ERROR_CORRECT_M
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

SLUG_PATTERN = re.compile(r"^[A-Za-z0-9]{20}$")

# Human-readable caption shared by both label formats (see draw_label).
CAPTION = "SCAN IF FOUND: REWARD."


def default_base():
    """Default QR base URL, read from the project-root config.json.

    Keeps the real domain out of this file; falls back to a placeholder
    if config.json is missing or has no baseUrl.
    """
    cfg = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir,
                       "config.json")
    try:
        with open(cfg, encoding="utf-8") as f:
            base = json.load(f).get("baseUrl")
        if base:
            return base
    except (OSError, ValueError):
        pass
    return "https://example.com"


# Per-format geometry. Sources:
#   2x2: Avery 94107/64510/22806 shared die, 12/sheet, 3 x 4.
#   1x1: Avery 94103 Presta spec: 48/sheet, 6 x 8, 0.625" margins
#        all around => 1.25" pitch both directions.
FORMATS = {
    # Avery-published Presta 94107 spec (shared die with 64510/22806):
    # 0.625" margins all around => hpitch 2.625", vpitch 2.583333".
    "2x2": dict(cols=3, rows=4, label=2.0, left=0.625, top=0.625,
                hpitch=2.625, vpitch=2.5833333,
                qr=1.45, header=True, url_text=True,
                ec=ERROR_CORRECT_H),
    "1x1": dict(cols=6, rows=8, label=1.0, left=0.625, top=0.625,
                hpitch=1.25, vpitch=1.25,
                qr=0.80, header=False, url_text=False,
                # EC level M: our 55-char URLs at level H force a dense
                # 41-module code that is marginal at 0.8"; M yields a
                # coarser, more scannable code with 15% damage tolerance.
                ec=ERROR_CORRECT_M),
}


def read_slugs(path):
    """Return the validated slug list from a one-per-line file."""
    with open(path, encoding="utf-8") as f:
        slugs = [line.strip() for line in f if line.strip()]
    bad = [s for s in slugs if not SLUG_PATTERN.fullmatch(s)]
    if bad:
        sys.exit(f"error: malformed slug(s) in {path}: {bad[:3]}")
    if not slugs:
        sys.exit(f"error: no slugs found in {path}")
    return slugs


def qr_image(url, ec=ERROR_CORRECT_H):
    """Render one QR code at the given error-correction level."""
    qr = qrcode.QRCode(error_correction=ec, box_size=12, border=0)
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return ImageReader(buf)


def cell_origin(fmt, index, xshift, yshift):
    """Top-left corner of the label cell for a 0-based on-page index."""
    col, row = index % fmt["cols"], index // fmt["cols"]
    x = (fmt["left"] + col * fmt["hpitch"] + xshift) * inch
    y_top = letter[1] - (fmt["top"] + row * fmt["vpitch"] + yshift) * inch
    return x, y_top


def draw_calibration_page(c, fmt, xshift, yshift):
    """Outline every cell so alignment can be checked on plain paper."""
    c.setFont("Helvetica", 11)
    c.drawCentredString(
        letter[0] / 2, letter[1] - 0.32 * inch,
        "CALIBRATION PAGE - print on PLAIN paper, hold against a label "
        "sheet up to the light")
    c.setLineWidth(0.5)
    for i in range(fmt["cols"] * fmt["rows"]):
        x, y_top = cell_origin(fmt, i, xshift, yshift)
        c.rect(x, y_top - fmt["label"] * inch, fmt["label"] * inch,
               fmt["label"] * inch)
    c.showPage()


def draw_label(c, fmt, x, y_top, tag_number, slug, base):
    """Draw one complete label with its cell's top-left at (x, y_top)."""
    url = f"{base}/found/{slug}"
    label = fmt["label"] * inch
    qr_size = fmt["qr"] * inch
    cx = x + label / 2

    if fmt["header"]:
        c.setFont("Helvetica-Bold", 8.5)
        c.drawCentredString(cx, y_top - 0.135 * inch, CAPTION)
        qr_y = y_top - 0.20 * inch - qr_size
    else:
        qr_y = y_top - 0.055 * inch - qr_size

    c.drawImage(qr_image(url, fmt["ec"]), cx - qr_size / 2, qr_y, qr_size, qr_size)

    if fmt["url_text"]:
        c.setFont("Helvetica", 5.4)
        c.drawCentredString(cx, qr_y - 0.085 * inch,
                            url.replace("https://", ""))
        c.setFont("Helvetica", 4.5)
        c.drawRightString(x + label - 0.05 * inch,
                          y_top - label + 0.045 * inch, f"#{tag_number:03d}")
    else:
        c.setFont("Helvetica-Bold", 4.3)
        c.drawCentredString(cx, y_top - label + 0.045 * inch,
                            f"{CAPTION} #{tag_number:03d}")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("slugs", help="slugs.txt, one slug per line")
    p.add_argument("output", help="output PDF path")
    p.add_argument("--base", default=default_base(),
                   help="URL base (default from ../config.json baseUrl: "
                        "%(default)s)")
    p.add_argument("--format", choices=sorted(FORMATS), default="2x2",
                   help="label stock: 2x2 = Avery 64510 (12/sheet), "
                        "1x1 = Avery 94103 (48/sheet)")
    p.add_argument("--xshift", type=float, default=0.0,
                   help="grid shift right, inches (from calibration)")
    p.add_argument("--yshift", type=float, default=0.0,
                   help="grid shift down, inches (from calibration)")
    args = p.parse_args()

    slugs = read_slugs(args.slugs)
    fmt = FORMATS[args.format]
    per_sheet = fmt["cols"] * fmt["rows"]
    out_dir = os.path.dirname(args.output)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    c = canvas.Canvas(args.output, pagesize=letter)
    draw_calibration_page(c, fmt, args.xshift, args.yshift)

    for i, slug in enumerate(slugs):
        if i and i % per_sheet == 0:
            c.showPage()
        x, y_top = cell_origin(fmt, i % per_sheet, args.xshift, args.yshift)
        draw_label(c, fmt, x, y_top, i + 1, slug, args.base)
    c.showPage()
    c.save()

    sheets = -(-len(slugs) // per_sheet)
    print(f"{args.output}: {len(slugs)} labels on {sheets} sheets "
          f"(+1 calibration page)")


if __name__ == "__main__":
    main()
