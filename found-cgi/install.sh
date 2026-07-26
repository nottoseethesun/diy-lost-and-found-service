#!/usr/bin/env bash
#
# install.sh -- install the found-tag system. RUN THIS ON KONTAR,
# from inside the extracted found-cgi/ directory, after placing your
# workstation-generated slugs.txt in this directory.
#
# Usage:
#   ./install.sh
#
# Does, in order:
#   1. checks the Python interpreter and required files
#   2. probes which user Apache executes CGI as (throwaway CGI,
#      fetched once over HTTPS, removed immediately) and selects
#      data-file permissions accordingly:
#        runs as you          -> dir 700, files 600 (strict)
#        runs as server user  -> dir 711, files 644 (relaxed)
#   3. creates ~/found-data and installs config.json, slugs.txt,
#      page.html into it
#   4. installs found.cgi into the docroot's cgi-local/
#   5. backs up the docroot .htaccess (timestamped), installs the new one
#   6. runs a local 200/404 sanity check and an over-the-wire check
#
# Environment overrides (rarely needed):
#   DOCROOT=... DATADIR=... BASE=... PYTHON=... DATA_PERMS=strict|relaxed

set -euo pipefail

readonly DOCROOT="${DOCROOT:-$HOME/your-site}"
readonly CGIDIR="$DOCROOT/cgi-local"
readonly DATADIR="${DATADIR:-$HOME/found-data}"
readonly BASE="${BASE:-https://www.example.com}"
# INSECURE_TLS=1 adds -k: acceptable when this host is fetching its own
# pages from itself (old local CA bundle can't verify Let's Encrypt
# chains); it does not affect what finders' browsers verify.
readonly CURL="curl -s${INSECURE_TLS:+ -k}"
readonly PYTHON="${PYTHON:-/usr/bin/python3.7}"

die() {
    printf 'error: %s\n' "$1" >&2
    exit 1
}

check_prerequisites() {
    "$PYTHON" -V >/dev/null 2>&1 || die "$PYTHON not found -- cannot proceed"
    local f
    for f in found.cgi page.html config.json htaccess-docroot slugs.txt; do
        [[ -r "$f" ]] || die "missing file in current directory: $f \
(slugs.txt is generated on your workstation -- see INSTALL.md step 1)"
    done
    [[ -d "$CGIDIR" ]] || die "no such directory: $CGIDIR"
    grep -qE '^[A-Za-z0-9]{20}$' slugs.txt || die "slugs.txt contains no valid slugs"
    "$PYTHON" -c "import ast; ast.parse(open('found.cgi').read())" \
        || die "found.cgi fails to parse under $PYTHON"
    printf 'prerequisites: OK (%s)\n' "$("$PYTHON" -V 2>&1)"
}

probe_cgi_user() {
    # Installs a throwaway CGI that reports its identity, fetches it
    # once, removes it (even on failure), and prints the id output.
    local name result
    name="whoami-test-$$.cgi"
    printf '#!/bin/sh\nprintf "Content-Type: text/plain\\r\\n\\r\\n"\nid\n' \
        > "$CGIDIR/$name"
    chmod 755 "$CGIDIR/$name"
    result=$($CURL "$BASE/cgi-local/$name") || true
    rm -f "$CGIDIR/$name"
    printf '%s' "$result"
}

select_permissions() {
    # Sets globals dir_mode/file_mode from DATA_PERMS if preset,
    # otherwise from the live probe.
    local probe
    if [[ -n "${DATA_PERMS:-}" ]]; then
        printf 'permissions preset via DATA_PERMS=%s\n' "$DATA_PERMS"
    else
        probe=$(probe_cgi_user)
        printf 'CGI executes as: %s\n' "$probe"
        if grep -q "uid=$(id -u)(" <<< "$probe"; then
            DATA_PERMS=strict
        elif grep -q 'uid=' <<< "$probe"; then
            DATA_PERMS=relaxed
        else
            die "probe returned no identity -- CGI did not execute; not installing"
        fi
    fi
    case "$DATA_PERMS" in
        strict)  dir_mode=700; file_mode=600 ;;
        relaxed) dir_mode=711; file_mode=644 ;;
        *) die "DATA_PERMS must be 'strict' or 'relaxed', got: $DATA_PERMS" ;;
    esac
    printf 'data permissions: %s (dir %s, files %s)\n' \
        "$DATA_PERMS" "$dir_mode" "$file_mode"
}

install_files() {
    mkdir -p "$DATADIR"
    cp page.html config.json slugs.txt "$DATADIR/"
    chmod "$dir_mode" "$DATADIR"
    chmod "$file_mode" "$DATADIR/page.html" "$DATADIR/config.json" "$DATADIR/slugs.txt"

    cp found.cgi "$CGIDIR/"
    sed -i 's/\r$//' "$CGIDIR/found.cgi"
    chmod 755 "$CGIDIR/found.cgi"

    cp "$DOCROOT/.htaccess" "$DOCROOT/.htaccess.bak-$(date +%Y%m%d-%H%M%S)"
    cp htaccess-docroot "$DOCROOT/.htaccess"
    printf 'files installed; .htaccess backed up and replaced\n'
}

sanity_check() {
    local slug status
    slug=$(grep -m1 -E '^[A-Za-z0-9]{20}$' slugs.txt)

    # local: execute the CGI directly with the deployed data files
    ( cd "$CGIDIR"
      export FOUND_CONFIG="$DATADIR/config.json"
      export FOUND_SLUGS="$DATADIR/slugs.txt"
      export FOUND_TEMPLATE="$DATADIR/page.html"
      [[ "$(PATH_INFO=/found/$slug "$PYTHON" ./found.cgi | head -1)" == \
         "$(printf 'Status: 200 OK\r')" ]] || die "local sanity: valid slug != 200"
      [[ "$(PATH_INFO=/found/aaaaaaaaaaaaaaaaaaaa "$PYTHON" ./found.cgi | head -1)" == \
         "$(printf 'Status: 404 Not Found\r')" ]] || die "local sanity: bad slug != 404"
    )
    printf 'local sanity: PASS\n'

    # over the wire: through Apache, rewrite, SetEnv, permissions
    status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/found/$slug") \
        || die "wire check: could not reach $BASE (curl exit $?)"
    [[ "$status" == 200 ]] || die "wire check: valid slug returned $status (see INSTALL.md troubleshooting)"
    status=$($CURL -o /dev/null -w '%{http_code}' "$BASE/found/aaaaaaaaaaaaaaaaaaaa") \
        || die "wire check: could not reach $BASE (curl exit $?)"
    [[ "$status" == 404 ]] || die "wire check: unknown slug returned $status"
    printf 'wire check: PASS\n'
}

main() {
    check_prerequisites
    select_permissions
    install_files
    sanity_check
    printf '\ninstall complete -- next: ./smoke-test.sh\n'
}

main "$@"
