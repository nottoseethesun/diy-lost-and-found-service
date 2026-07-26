#!/usr/bin/env bash
#
# smoke-test.sh -- verify the deployed found-tag pages over HTTPS.
# Run from the same directory as deploy.sh (needs the slugs.txt it
# generated). No arguments, no editing.

set -euo pipefail

readonly BASE="${BASE:-https://www.example.com}"
# INSECURE_TLS=1 adds -k: acceptable when this host is fetching its own
# pages from itself (old local CA bundle can't verify Let's Encrypt
# chains); it does not affect what finders' browsers verify.
readonly CURL="curl -s${INSECURE_TLS:+ -k}"

pass=0
fail=0

check() {
    local label=$1 expected=$2 url=$3
    local got
    got=$($CURL -o /dev/null -w '%{http_code}' "$url")
    if [[ "$got" == "$expected" ]]; then
        printf 'PASS  %-40s %s\n' "$label" "$got"
        (( ++pass ))
    else
        printf 'FAIL  %-40s got %s, expected %s\n' "$label" "$got" "$expected"
        (( ++fail ))
    fi
}

main() {
    [[ -r slugs.txt ]] || { echo "error: slugs.txt not found (run deploy.sh first)" >&2; exit 1; }
    local slug
    slug=$(head -1 slugs.txt)

    check "valid slug"                200 "$BASE/found/$slug"
    check "unknown slug"              404 "$BASE/found/aaaaaaaaaaaaaaaaaaaa"
    check "malformed slug"            404 "$BASE/found/short"
    check "bare /found/"              404 "$BASE/found/"
    check "data dir not web-mapped"   404 "$BASE/found-data/config.json"
    check "no stale data in cgi-local" 404 "$BASE/cgi-local/slugs.txt"

    # content check: expected contact substrings from smoke-test.config
    # (git-ignored; e.g. EXPECT_CONTACTS="yourdomain.com"), else a structural
    # fallback -- the page must carry at least two mailto: links.
    local body
    body=$($CURL "$BASE/found/$slug")
    if [[ -r smoke-test.config ]]; then
        # shellcheck source=/dev/null
        source ./smoke-test.config
    fi
    local ok=1 clabel
    if [[ -n "${EXPECT_CONTACTS:-}" ]]; then
        clabel="page renders expected contacts"
        local token
        for token in $EXPECT_CONTACTS; do
            grep -q "$token" <<< "$body" || ok=0
        done
    else
        clabel="page renders contacts (>=2 mailto links)"
        [[ "$(grep -o 'mailto:' <<< "$body" | wc -l)" -ge 2 ]] || ok=0
    fi
    if [[ "$ok" == 1 ]]; then
        printf 'PASS  %-40s\n' "$clabel"
        (( ++pass ))
    else
        printf 'FAIL  %-40s\n' "$clabel"
        (( ++fail ))
    fi

    # WKD regression: rule must still pass through (any non-500 accepted)
    local wkd
    wkd=$($CURL -o /dev/null -w '%{http_code}' "$BASE/.well-known/openpgpkey/")
    if [[ "$wkd" != 5* ]]; then
        printf 'PASS  %-40s %s\n' "WKD passthrough intact" "$wkd"
        (( ++pass ))
    else
        printf 'FAIL  %-40s %s\n' "WKD passthrough intact" "$wkd"
        (( ++fail ))
    fi

    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    (( fail == 0 ))
}

main "$@"
