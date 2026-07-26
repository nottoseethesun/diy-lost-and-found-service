#!/usr/bin/env bash
#
# test/run.sh -- one-command test suite for the DIY Lost-and-Found Service.
#
#   ./test/run.sh                         # run everything (uses test/test-config.json)
#   BASE=https://your-site ./test/run.sh  # point the end-to-end test at a deployed site
#
# All settings live in test/test-config.json, not a pile of environment
# variables. The suite tallies its own pass/fail and exits non-zero if anything
# fails; the end-to-end section skips cleanly when no local data is present.
#
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
ROOT="$PWD"
PY="$ROOT/print-kit/.venv/bin/python"
[ -x "$PY" ] || PY="python3"

# --- settings from test/test-config.json (base "-" means: use the local server) ---
read -r PORT CGIDIR CFGBASE < <(python3 - <<'PYEOF'
import json
try:
    c = json.load(open("test/test-config.json"))
except Exception:
    c = {}
print(c.get("port", 8791), c.get("cgiDir", "found-cgi"), c.get("base") or "-")
PYEOF
)
[ "$CFGBASE" = "-" ] && CFGBASE=""
BASE_SEL="${BASE:-$CFGBASE}"   # the single env var BASE overrides the config's base

pass=0; fail=0
ok(){  printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
bad(){ printf 'FAIL  %s\n' "$1"; fail=$((fail+1)); }
run(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }

echo "== static =="
run "gen-labels.py compiles"       "$PY" -m py_compile print-kit/gen-labels.py
run "found.cgi parses"             python3 -c 'import ast; ast.parse(open("found-cgi/found.cgi").read())'
run "smoke-test.sh syntax"         bash -n found-cgi/smoke-test.sh
run "install.sh syntax"            bash -n found-cgi/install.sh
run "setup.sh syntax"              bash -n found-cgi/setup.sh
run "init-local-files.sh syntax"   bash -n init-local-files.sh
run "config.example.json valid"    python3 -m json.tool config.example.json
run "print-kit/config.json valid"  python3 -m json.tool print-kit/config.json
run "test/test-config.json valid"  python3 -m json.tool test/test-config.json

echo ""
echo "== dependencies + label generation =="
if "$PY" -c "import qrcode, reportlab, PIL" 2>/dev/null; then
  ok "qrcode / reportlab / Pillow import"
  TMP="$(mktemp -d)"
  printf 'AAAAAAAAAAAAAAAAAAAA\nBBBBBBBBBBBBBBBBBBBB\n' > "$TMP/slugs.txt"
  if "$PY" print-kit/gen-labels.py "$TMP/slugs.txt" "$TMP/a.pdf" --format 1x1 >/dev/null 2>&1 \
     && "$PY" print-kit/gen-labels.py "$TMP/slugs.txt" "$TMP/b.pdf" --format 2x2 >/dev/null 2>&1 \
     && [ -s "$TMP/a.pdf" ] && [ -s "$TMP/b.pdf" ]; then
    ok "gen-labels produces 1x1 + 2x2 PDFs"
  else
    bad "gen-labels PDF generation"
  fi
  rm -rf "$TMP"
else
  printf 'SKIP  qrcode/reportlab not installed (see print-kit/README.md)\n'
fi

echo ""
echo "== end-to-end: found-cgi/smoke-test.sh =="
SRV=""
if [ -n "$BASE_SEL" ]; then
  echo "   target: $BASE_SEL (from config/BASE)"
  BASE_USED="$BASE_SEL"
elif [ -r "$CGIDIR/config.json" ] && grep -qE '^[A-Za-z0-9]{20}$' "$CGIDIR/slugs.txt" 2>/dev/null; then
  echo "   target: local stand-in server on port $PORT"
  TESTPORT="$PORT" CGIDIR="$ROOT/$CGIDIR" python3 test/local_server.py &
  SRV=$!
  trap 'kill "$SRV" 2>/dev/null' EXIT
  curl --retry 20 --retry-connrefused --retry-delay 1 -s -o /dev/null "http://127.0.0.1:$PORT/probe" 2>/dev/null || true
  BASE_USED="http://127.0.0.1:$PORT"
else
  BASE_USED=""
fi
if [ -n "$BASE_USED" ]; then
  OUT="$(cd "$CGIDIR" && BASE="$BASE_USED" ./smoke-test.sh 2>&1)"; RC=$?
  [ -n "$SRV" ] && { kill "$SRV" 2>/dev/null; trap - EXIT; }
  printf '%s\n' "$OUT" | sed 's/^/    /'
  if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "0 failed"; then ok "smoke-test.sh (8/8)"; else bad "smoke-test.sh"; fi
else
  printf 'SKIP  no local found-cgi data and no base set (run ./init-local-files.sh, mint slugs, or set base)\n'
fi

echo ""
echo "===================================="
printf 'RESULT: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
