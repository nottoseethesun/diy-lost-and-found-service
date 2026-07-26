#!/usr/bin/env bash
#
# init-local-files.sh — recreate the git-ignored local data files from their
# committed *.example.* templates.
#
# The real files below hold contact PII and secret capability slugs, so they are
# git-ignored and never committed. On a fresh clone they are absent; this script
# seeds them from the committed example templates so you have working files to
# fill in.
#
#   found-cgi/config.example.json   ->  found-cgi/config.json
#   found-cgi/slugs.example.txt     ->  found-cgi/slugs.txt
#   tag-manifest.example.csv        ->  tag-manifest.csv
#
# Existing real files are left untouched (your data is never clobbered) unless
# you pass --force.
#
# Usage:
#   ./init-local-files.sh            # create any missing real files
#   ./init-local-files.sh --force    # overwrite existing real files too
#
set -euo pipefail

force=0
if [[ "${1:-}" == "--force" ]]; then
  force=1
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--force]" >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# "template|real file it seeds"
mappings=(
  "config.example.json|config.json"
  "found-cgi/config.example.json|found-cgi/config.json"
  "found-cgi/slugs.example.txt|found-cgi/slugs.txt"
  "found-cgi/smoke-test.config.example|found-cgi/smoke-test.config"
  "tag-manifest.example.csv|tag-manifest.csv"
)

created=0
skipped=0
for m in "${mappings[@]}"; do
  src="$root/${m%%|*}"
  dst="$root/${m##*|}"
  if [[ ! -f "$src" ]]; then
    echo "error: missing template: ${m%%|*}" >&2
    exit 1
  fi
  if [[ -e "$dst" && $force -eq 0 ]]; then
    echo "skip    ${m##*|}  (exists — pass --force to overwrite)"
    skipped=$((skipped + 1))
    continue
  fi
  cp "$src" "$dst"
  echo "create  ${m##*|}"
  created=$((created + 1))
done

echo "done: ${created} created, ${skipped} skipped"
if [[ $created -gt 0 ]]; then
  echo "next: edit the created files with your real values (they stay git-ignored)."
fi
