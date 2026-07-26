# print-kit — label generation

Everything needed to turn a list of tag slugs into print-ready PDF sheets of
unique QR-code labels for Avery blank stock.

## Contents

| Path | What it is |
|------|-----------|
| `gen-labels.py` | Generates the label PDFs (one unique QR per label). |
| `config.json` | Avery product metadata + verified sheet **geometry** (below). |
| `avery-templates/` | *Optional*, git-ignored. Where you save Avery's blank-sheet template PDFs if you want them (see [Avery templates](#avery-templates-optional)). |
| `PRINT.md` | The physical printing procedure (stock to order, print-shop steps, calibration). |
| `README.md` | This file. |

Generated PDFs are written to the git-ignored top-level `output/` directory and
are never committed — they embed your secret slugs. See
[Generating labels](#generating-labels).

## Requirements

- Python 3.8+
- Python packages: `qrcode`, `reportlab` (these also pull in Pillow).

Install into a virtualenv (recommended):

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install qrcode reportlab
```

> Always install with `python3 -m pip`, never bare `pip`. On some systems `pip`
> and `python3` resolve to different interpreters, so `pip install X` "succeeds"
> while `python3` still can't import `X`. Running pip as a module of the exact
> interpreter (`python3 -m pip`) makes that mismatch impossible. If you see
> `ModuleNotFoundError: No module named 'qrcode'` right after a successful-looking
> install, that mismatch just happened — reinstall with `python3 -m pip`.

## Generating labels

`gen-labels.py` needs a slug list — one 20-character slug (`[A-Za-z0-9]{20}`)
per line. In this project that is `../found-cgi/slugs.txt` (git-ignored;
bootstrap a blank one with `../init-local-files.sh`, then fill in real slugs —
see the root README's Install section for how to mint them).

```bash
# from print-kit/
python3 gen-labels.py ../found-cgi/slugs.txt ../output/found-labels-avery94103-1inch.pdf --format 1x1
python3 gen-labels.py ../found-cgi/slugs.txt ../output/found-labels-2x2-avery94107.pdf   --format 2x2
```

- **Output** goes wherever you point it; the convention is `../output/`
  (git-ignored). The parent directory is created automatically.
- **Page 1 of every PDF is a calibration page.** Print it on plain paper first
  and check it against an *unprinted* Avery sheet before running a batch — see
  `PRINT.md` and the root README's **Usage** section. Do not skip this.
- **Base URL** for the encoded QR (`<base>/found/<slug>`) defaults to `baseUrl`
  in the project-root `config.json`; override per run with `--base https://…`.
- **Alignment:** if the calibration page is uniformly shifted from the
  die-cuts, re-run with `--xshift` / `--yshift` (inches; positive = right/down).

```
positional:  SLUGS_FILE  OUTPUT_PDF
--format     2x2 (Avery 64510/94107, 12/sheet)  [default]
             1x1 (Avery 94103, 48/sheet)
--base       QR URL base (default: root config.json baseUrl)
--xshift / --yshift   grid shift in inches (from the calibration page)
```

The per-format drawing geometry lives in `gen-labels.py`'s `FORMATS` table;
`config.json` records the same sheet geometry as durable reference data.

## config.json

Avery product metadata and the authoritative sheet geometry, so the layout
never has to be re-derived. Shape:

```
labelTemplates
├── oneInchSquare[]      # 1"x1" products
└── twoInchSquare[]      # 2"x2" products
```

Each product entry:

| Field | Meaning |
|-------|---------|
| `brand` | Manufacturer (`avery`). |
| `modelName` | Avery's template/product name. |
| `productId` | Avery product number (e.g. `94103`). |
| `templateCompatibility[]` | Other Avery product numbers that share the same die/template. |
| `url` | Human-facing Avery template page for that product. |
| `geometry` | Sheet layout (below). |

`geometry` (all lengths in `units`, which is `"in"`):

| Field | Meaning |
|-------|---------|
| `sheet` | `{name, width, height}` of the paper (US Letter, 8.5 x 11). |
| `label` | `{width, height}` of one label. |
| `grid` | `{columns, rows, perSheet}`. |
| `pitch` | centre-to-centre `{horizontal, vertical}` spacing. |
| `margins` | `{top, right, bottom, left}` from sheet edge to the outermost die-cut. |
| `gap` | `{horizontal, vertical}` space between adjacent labels. |
| `provenance` | how the numbers were established, or why a field is unknown. |

**Completeness.** `oneInchSquare` / 94103 is fully verified. The
`twoInchSquare` entries (94107 and 64510 — the same physical die) have their
sheet size, label size, and per-sheet count confirmed, but their **`grid`,
`pitch`, `margins`, and `gap` are `null`**: those numbers are not established
and were deliberately not guessed. Complete them by measuring a physical 2"
sheet; see each entry's `provenance`.

### Adding a new Avery product

Add an object to the appropriate `…Square` array with `brand`, `modelName`,
`productId`, `templateCompatibility`, `url`, and a `geometry` block. Fill only
geometry values you have actually measured or that Avery documents; leave
anything unverified as `null` with a `provenance` note. A wrong number here is
worse than a missing one — the point of this file is that nobody has to
re-derive it later.

## Avery templates (optional)

**You do not need Avery's template PDFs to generate or print labels.** The
geometry is already in code (`FORMATS`) and in `config.json`; nothing in the
project reads a template PDF at runtime. The templates are only reference
material — a visual die-cut proof.

They are **not redistributed** with this project, for two reasons the ignore
rule encodes:

1. they are user-supplied inputs, not project source; and
2. they are likely Avery's protected property.

So everything under `avery-templates/` is git-ignored — never commit or
redistribute it.

If you want them, download them yourself and save them here:

```
avery-templates/
├── one-inch-square/AveryPresta94103SquareLabels.pdf
└── two-inch-square/Avery64510SquareLabels.pdf   (and/or AveryPresta94107SquareLabels.pdf)
```

1. Open the product's `url` from `config.json`
   (e.g. <https://www.avery.com/templates/presta-94103>).
2. Download the blank template PDF for that product from Avery's site.
3. Save it under `avery-templates/<size>/` with the filename shown above.

> Avery's *direct download* links are short-lived AWS presigned URLs — they
> expire in about seven days and embed a signature — so they can't be automated
> or committed to config. Always start from the product page and download fresh.
