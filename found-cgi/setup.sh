#!/usr/bin/env bash
#
# setup.sh -- one-time bootstrap after extracting the tarball.
# Sets the executable bit on everything that needs it, in case the
# transfer or extraction stripped permissions.
#
# Invoke WITHOUT needing an executable bit on this file itself:
#
#   bash setup.sh
#
set -euo pipefail

cd "$(dirname "$0")"

readonly EXECUTABLES=(
    found.cgi
    install.sh
    smoke-test.sh
)

main() {
    local f
    for f in "${EXECUTABLES[@]}"; do
        [[ -f "$f" ]] || { printf 'error: missing file: %s\n' "$f" >&2; exit 1; }
        chmod 755 "$f"
        printf 'chmod 755  %s\n' "$f"
    done
    printf '\nready -- next: ./install.sh\n'
}

main "$@"
