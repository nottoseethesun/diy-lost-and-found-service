#!/usr/bin/env bash
#
# mint-slugs.sh — mint unguessable capability slugs for the found-tag system.
#
# Each slug is 20 random alphanumerics from a CSPRNG (~119 bits), one per line —
# the secret tokens your QR labels encode. Keep the output private; it is
# git-ignored. Default output: found-cgi/slugs.txt.
#
# Usage:
#   ./mint-slugs.sh                # 100 slugs -> found-cgi/slugs.txt
#   ./mint-slugs.sh -n 250         # mint a different count
#   ./mint-slugs.sh -o other.txt   # write somewhere else
#   ./mint-slugs.sh -a             # append instead of replacing
#   ./mint-slugs.sh -f             # overwrite even if the file already has slugs
#
# Existing slugs are never clobbered unless you pass -f (or -a to append): they
# are capability tokens for labels you may already have printed and applied, so
# regenerating them silently would orphan those tags.
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
mint-slugs.sh — mint capability slugs (20 CSPRNG alphanumerics each, one/line).

  ./mint-slugs.sh [-n COUNT] [-o OUTFILE] [-a] [-f]

  -n COUNT    how many to mint (default 100)
  -o OUTFILE  where to write (default found-cgi/slugs.txt)
  -a          append to OUTFILE instead of replacing it
  -f          overwrite OUTFILE even if it already contains slugs
  -h          show this help

Existing slugs are never clobbered unless you pass -f (or -a): they are
capability tokens for labels you may already have printed.
EOF
  exit "${1:-2}"
}

count=100
outfile=""
append=0
force=0

while getopts ':n:o:afh' opt; do
  case "$opt" in
    n) count=$OPTARG ;;
    o) outfile=$OPTARG ;;
    a) append=1 ;;
    f) force=1 ;;
    h) usage 0 ;;
    :)  echo "mint-slugs: option -$OPTARG requires a value" >&2; usage ;;
    \?) echo "mint-slugs: unknown option -$OPTARG" >&2; usage ;;
  esac
done
shift $((OPTIND - 1))
[[ $# -eq 0 ]] || { echo "mint-slugs: unexpected argument: $1 (did you mean -n $1?)" >&2; usage; }

[[ "$count" =~ ^[1-9][0-9]*$ ]] \
  || { echo "mint-slugs: -n COUNT must be a positive integer (got: $count)" >&2; exit 2; }

command -v python3 >/dev/null 2>&1 \
  || { echo "mint-slugs: python3 is required (it provides the CSPRNG)" >&2; exit 1; }

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${outfile:=$root/found-cgi/slugs.txt}"

# Never silently destroy existing capability tokens.
if [[ $append -eq 0 && $force -eq 0 && -f "$outfile" ]]; then
  existing=$(grep -cE '^[A-Za-z0-9]{20}$' "$outfile" 2>/dev/null || true)
  if [[ "${existing:-0}" -gt 0 ]]; then
    echo "mint-slugs: refusing to overwrite $outfile — it already holds $existing slug(s)." >&2
    echo "            those are capability tokens for labels you may have printed;" >&2
    echo "            pass -a to append more, or -f to overwrite anyway." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "$outfile")"

# 20 alphanumerics per slug from Python's CSPRNG (secrets). COUNT is passed via
# the environment, not string-interpolated, so it can't be injected.
new_slugs="$(COUNT="$count" python3 -c '
import os, secrets, string
alphabet = string.ascii_letters + string.digits
n = int(os.environ["COUNT"])
print("\n".join("".join(secrets.choice(alphabet) for _ in range(20)) for _ in range(n)))
')"

if [[ $append -eq 1 ]]; then
  printf '%s\n' "$new_slugs" >> "$outfile"
  verb=appended
else
  printf '%s\n' "$new_slugs" > "$outfile"
  verb=wrote
fi

total=$(grep -cE '^[A-Za-z0-9]{20}$' "$outfile" || true)
echo "$verb $count slugs -> $outfile ($total total)"
echo "keep it private — the slugs are capability tokens (git-ignored)."
