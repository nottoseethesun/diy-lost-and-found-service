# Printing the found-tag labels

## Order (avery.com or Staples/Amazon)

- **Avery 94107-WMF10** — 2"x2" Durable Matte White Film, 10 sheets
  (the product you ordered; matte is fine -- scans with less glare).
  Need 9 sheets; the pack's 10th is your spare, so consider a second
  pack if you want test-print margin.
- **Avery 94103** (avery.com "blank labels by the sheet") — 1"x1",
  material: **Waterproof White Vinyl Film**. Order **5 sheets**
  (need 3 + spares).

## Print — NOT on your inkjet

Your dye inkjet will smear on this film when wet, voiding the
waterproofing. Take BOTH the blank sheets and the PDFs to
**FedEx Office** (or any print shop with a laser printer):

1. Ask them to print from your USB/emailed PDF onto **your provided
   label sheets**, via the **manual-feed/bypass tray**, at
   **100% scale ("Actual size" — never "Fit to page")**.
2. First: print **page 1 only** of each PDF on their **plain paper**.
   Hold it against a blank label sheet up to the light — printed
   squares must sit on the die-cuts.
3. If aligned: print the remaining pages onto the label sheets
   (94107 PDF -> 2" sheets; 94103 PDF -> 1" sheets).
4. If shifted: note direction + amount in inches; regenerate with
   `python3 gen-labels.py slugs.txt out.pdf --format 2x2
   --xshift 0.05 --yshift -0.03` (example values).

## Before stickering anything

Scan one printed label of EACH size with your phone; confirm the
contact page loads.

## Files

Generated label PDFs are written to the git-ignored top-level `output/`
directory. They are not committed; regenerate them any time with
`gen-labels.py` (see `README.md`):

- `../output/found-labels-2x2-avery94107.pdf`    (2", 1 calibration + 9 sheets)
- `../output/found-labels-avery94103-1inch.pdf`  (1", 1 calibration + 3 sheets)
- `gen-labels.py`  (regenerator, needs a slugs file; `pip install qrcode reportlab`)
