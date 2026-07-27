#!/usr/bin/env bash
#
# test/lint-markdown.sh -- lint every Markdown file in the repo, one command.
#
#   ./test/lint-markdown.sh
#
# Uses PyMarkdown (https://github.com/jackdewinter/pymarkdown), a Python
# Markdown linter that speaks the same MDxxx rule IDs as VSCode's markdownlint
# extension -- so no Node toolchain is needed. Rules live in .pymarkdown.json
# (the matching .markdownlint.jsonc keeps the VSCode extension in agreement).
#
# Install the linter once, kept out of the project:
#   pipx install pymarkdownlnt        # isolated, recommended
#   pip install --user pymarkdownlnt  # or into any environment
# (Package name is 'pymarkdownlnt'; the command it installs is 'pymarkdown'.)
#
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

# Find a PyMarkdown invocation: the installed console script, else the module.
if command -v pymarkdown >/dev/null 2>&1; then
  PYMD=(pymarkdown)
elif python3 -c 'import pymarkdown' >/dev/null 2>&1; then
  PYMD=(python3 -m pymarkdown)
else
  cat >&2 <<'MSG'
markdown lint: PyMarkdown is not installed.
  pipx install pymarkdownlnt        # isolated, recommended
  pip install --user pymarkdownlnt  # or into any environment
(The package is 'pymarkdownlnt'; the command it provides is 'pymarkdown'.)
MSG
  exit 2
fi

# Every tracked Markdown file (fall back to a filesystem scan outside git).
mapfile -t FILES < <(git ls-files '*.md' '*.markdown' 2>/dev/null)
if [ "${#FILES[@]}" -eq 0 ]; then
  mapfile -t FILES < <(
    find . \( -name .venv -o -name output -o -name node_modules \) -prune \
      -o -name '*.md' -print | sort
  )
fi
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "markdown lint: no Markdown files found."
  exit 0
fi

echo "== markdown lint: ${#FILES[@]} file(s) via PyMarkdown =="
"${PYMD[@]}" --config .pymarkdown.json scan "${FILES[@]}"
rc=$?
if [ "$rc" -eq 0 ]; then
  echo "PASS  no Markdown lint violations"
else
  echo "FAIL  Markdown lint violations reported above"
fi
exit "$rc"
