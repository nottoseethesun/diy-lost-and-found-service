# INSTALL — found-tag system on your host (your shared host shared hosting)

Flow: prepare one file on your workstation, upload the tarball plus
that file to your host, then run two scripts ON KONTAR. Every command is
copy-paste ready; the scripts abort loudly with a diagnosis on any
failure.

Target (probed): Apache 2.0.64, docroot `~/your-site/`,
existing `cgi-local/`, Python 3.7.4 confirmed at `/usr/bin/python3.7`.

---

## 1. (Workstation) Generate slugs.txt

From the directory holding your `tag-manifest.csv` (from the
QR-generation tarball):

```bash
cut -d, -f2 tag-manifest.csv | tail -n +2 > slugs.txt
wc -l slugs.txt    # expect: 100
```

The manifest itself (slug -> item mapping) NEVER gets uploaded.

## 2. (Workstation) Upload the tarball and slugs.txt

Destination: your HOME directory (`/home/youruser`) — NOT
inside `your-site/`, so nothing lands in web-served space.

Using sftp (preferred; same credentials as ssh):

```bash
sftp youruser@your-host.example.com << 'SFTP'
put found-cgi.tar.gz
put slugs.txt
bye
SFTP
```

(Or with scp: `scp found-cgi.tar.gz slugs.txt
youruser@your-host.example.com:` — note the trailing colon,
meaning "home directory".)

## 3. (your host) Extract and bootstrap

```bash
cd ~
tar xzf found-cgi.tar.gz
mv slugs.txt found-cgi/
cd found-cgi
bash setup.sh
```

`setup.sh` restores executable bits in case the transfer stripped
them (invoked via `bash` so it never needs its own). Expected output
ends with: `ready -- next: ./install.sh`

## 4. (your host) Install

```bash
./install.sh
```

What it does, in order, dying loudly at the first problem:

1. Checks `/usr/bin/python3.7`, all required files, that slugs.txt
   contains valid slugs, and that found.cgi parses.
2. Probes which user Apache executes CGI as (throwaway CGI, one HTTPS
   fetch, removed immediately) and selects data-file permissions:
   runs-as-you -> `700/600` (strict); server user -> `711/644`
   (relaxed).
3. Creates `~/found-data/` and installs `config.json`, `slugs.txt`,
   `page.html` into it.
4. Installs `found.cgi` into `~/your-site/cgi-local/`
   (CRLF-stripped, `755`).
5. Backs up the docroot `.htaccess` with a timestamp, installs the
   new one (your WKD rule preserved as its first lines).
6. Sanity-checks locally (direct CGI execution: 200 and 404 paths)
   and over the wire (through Apache, rewrite, SetEnv, permissions).

Expected tail of output:

```
local sanity: PASS
wire check: PASS

install complete -- next: ./smoke-test.sh
```

## 5. (your host) Full verification

```bash
./smoke-test.sh
```

Eight checks; expected: `8 passed, 0 failed`

## 6. Phone test

Open a `/found/<slug>` URL on your phone; tap all six buttons. Scan
one printed QR label and confirm the same page loads — **before
applying labels to anything.**

## 7. (your host) Clean up the staging files

```bash
cd ~
rm -rf found-cgi found-cgi.tar.gz
```

Everything the system needs is already installed in `~/found-data/`
and `cgi-local/`; the extracted directory is only staging.

---

## Resulting layout

```
~/found-data/                    all system data, grouped, outside
|-- config.json                  the docroot -- no URL maps here
|-- page.html
`-- slugs.txt

~/your-site/
|-- .htaccess                    replaced (timestamped backup kept):
|                                rewrite rule + SetEnv pointers
|-- .well-known/                 untouched
|-- README.txt                   untouched
|-- doorsinpoetryandhistory@     untouched
`-- cgi-local/
    |-- found.cgi                the handler -- only file in docroot
    `-- php*.fcgi                untouched
```

There is deliberately NO `found/` directory; the `/found/<slug>` URLs
exist only in the rewrite rule.

## Maintenance (on your host)

Change contact info -- edit and done, effective on the next request:

```bash
vi ~/found-data/config.json
python3.7 -m json.tool ~/found-data/config.json   # verify still valid JSON
```

Revoke a tag (item sold, label compromised):

```bash
grep -v THE_SLUG_TO_REVOKE ~/found-data/slugs.txt > ~/found-data/slugs.new
mv ~/found-data/slugs.new ~/found-data/slugs.txt
```

## Overrides (rarely needed)

```bash
DOCROOT=$HOME/other_dir ./install.sh
DATADIR=$HOME/other_data ./install.sh
DATA_PERMS=relaxed ./install.sh     # skip the probe, force a mode
BASE=http://www.example.com ./install.sh   # if your host's old curl
                                    # can't verify the TLS cert (try first)
INSECURE_TLS=1 ./install.sh         # if HTTP is force-redirected to HTTPS:
                                    # adds curl -k; fine here because the
                                    # host is fetching its own pages
BASE=https://other.example ./install.sh   # also works for smoke-test.sh
```

## Rollback (on your host)

```bash
cd ~/your-site
cp $(ls -t .htaccess.bak-* | head -1) .htaccess
rm -f cgi-local/found.cgi
rm -rf ~/found-data
```

Restores the newest `.htaccess` backup and removes everything the
install added. The `php*.fcgi` wrappers are untouched throughout.

## Troubleshooting

| Symptom                              | Likely cause / fix                                                    |
|--------------------------------------|------------------------------------------------------------------------|
| install dies at python check         | Interpreter path changed -- rerun with `PYTHON=/path ./install.sh`   |
| install dies: missing slugs.txt      | Step 1/3 skipped -- generate on workstation, `mv` into found-cgi/    |
| install dies: probe returned no id   | Usually your host's old curl failing TLS verification of the Let's Encrypt cert -- retry `BASE=http://... ./install.sh`, then `INSECURE_TLS=1 ./install.sh`. If both fail, CGI may not execute at all -- contact host support |
| wire check: valid slug returned 500  | Permission mismatch -- rerun `DATA_PERMS=relaxed ./install.sh`       |
| wire check: valid slug returned 404  | `.htaccess` rewrite/SetEnv not honored -- check AllowOverride with host |
| smoke-test: contacts FAIL            | `config.json` invalid -- `python3.7 -m json.tool ~/found-data/config.json` |
