# found.cgi — self-hosted lost-and-found tag pages

Serves `https://www.example.com/found/<slug>` for the printed
QR tags. A valid slug renders a contact page (text / call / email, with
a backup contact). Anything else — unknown slug, malformed slug, no
slug — returns an identical generic 404, so valid and invalid requests
are indistinguishable from outside.

Runs as a classic CGI under Apache: a fresh process per request that
exits when the response is written, so there is no daemon, no state,
and nothing to leak. Configuration and data are re-read on every
request, so edits take effect immediately.

## Table of Contents

- [Files](#files)
- [config.json fields](#configjson-fields)
- [Request flow](#request-flow)
- [Behavior on unsupported URLs](#behavior-on-unsupported-urls)
- [Security properties](#security-properties)
- [Validation status](#validation-status)
- [Maintenance](#maintenance)
- [Local smoke test (any machine with python3)](#local-smoke-test-any-machine-with-python3)

## Files

| File                  | Role                                            | Edit?           |
|-----------------------|-------------------------------------------------|-----------------|
| `found.cgi`           | Request handler (Python 3.7+, stdlib only)      | No              |
| `page.html`           | HTML template for the contact page              | Styling only    |
| `config.json`         | Contact details (the only data you maintain)    | Yes             |
| `config.example.json` | Reference copy of the config shape              | No              |
| `slugs.txt`           | One valid 20-char slug per line (you generate)  | Regenerate only |
| `htaccess-docroot`    | Complete docroot `.htaccess` (rewrite + SetEnv) | No              |
| `setup.sh`            | Restores executable bits (run once, via bash)   | No              |
| `install.sh`          | Server-side installer (probes CGI user, installs, sanity-checks) | No |
| `smoke-test.sh`       | Over-the-wire verification                      | No              |
| `INSTALL.md`          | Step-by-step deployment for your host              | —               |

Deployed layout: `found.cgi` alone sits in the docroot's
`cgi-local/`; the three data files are grouped in `~/found-data/`,
outside the docroot, where no URL can reach them. The docroot
`.htaccess` points the script there via `SetEnv FOUND_CONFIG`,
`FOUND_SLUGS`, and `FOUND_TEMPLATE` (the script defaults to its own
directory when the variables are unset, which is what the local smoke
test below relies on).

## config.json fields

```json
{
  "owner_name":           "",
  "phone":                "",
  "phone_display":        "",
  "email":                "",
  "backup_phone":         "",
  "backup_phone_display": "",
  "backup_email":         "",
  "subject":              "I%20found%20your%20item",
  "reward_text":          "A reward is offered for the safe return of this item."
}
```

Values are HTML-escaped when loaded, so use plain text only — markup
will be rendered inert. `phone` values must be `tel:`-form
(`+1XXXXXXXXXX`); `subject` must be URL-encoded (spaces as `%20`).

## Request flow

```text
GET /found/<slug>
  └─ docroot .htaccess: RewriteRule matches ^found/([A-Za-z0-9]{20})$ only
       └─ /cgi-local/found.cgi invoked with PATH_INFO=/found/<slug>
            ├─ slug re-validated against ^[A-Za-z0-9]{20}$   (defense in depth)
            ├─ slug looked up in slugs.txt
            ├─ hit  → 200, page.html rendered with config.json values
            └─ miss → 404, generic body
```

Requests that don't match the rewrite pattern never spawn a CGI
process; Apache 404s them from the filesystem (no `found/` directory
exists on disk).

## Behavior on unsupported URLs

What an outside probe sees, case by case:

| Request                                  | Handled by      | Response                | What it reveals                          |
|------------------------------------------|-----------------|-------------------------|------------------------------------------|
| `/found/<valid, registered slug>`        | rewrite → CGI   | 200, contact page       | The tag exists (finder's intended path)  |
| `/found/<well-formed, unknown slug>`     | rewrite → CGI   | 404, generic body       | Nothing — identical to the cases below   |
| `/found/<well-formed, revoked slug>`     | rewrite → CGI   | 404, generic body       | Nothing — indistinguishable from unknown |
| `/found/<malformed: wrong length/chars>` | Apache directly | 404, Apache default body| Only that the URL shape is unrecognized  |
| `/found/` or `/found`                    | Apache directly | 404, Apache default body| Same                                     |
| `/found/../<anything>` (traversal)       | Apache directly | 404 (pattern can't match)| Same — and never reaches the CGI        |

**The guarantee that matters:** for any well-formed 20-character
candidate, the response is byte-identical whether that slug never
existed, was revoked, or was simply mistyped. An attacker gains no
oracle for "does this slug exist" short of hitting a registered one
outright — and at ~119 bits per slug, random and brute-force search
are computationally irrelevant (see Security properties).

**One honest asymmetry:** malformed paths get Apache's stock 404
while well-formed unknown slugs get the CGI's 404, and the two bodies
differ. A careful prober can therefore learn the *accepted slug
format* (20 alphanumerics). This is deliberate: routing malformed
requests to Apache means crawler noise and junk paths never spawn a
CGI process. Knowing the format does not help an attacker — the
search space is the point of the design, not the format's secrecy.
Timing is likewise uninformative: hit and miss both perform the same
file reads, differing only by a set lookup measured in microseconds,
far below network jitter.

## Security properties

- Slugs are 20 chars of mixed-case alphanumerics from a CSPRNG
  (~119 bits each): enumeration is not feasible.
- `slugs.txt` holds slugs only. The slug → item mapping
  (`tag-manifest.csv`) never goes on the server.
- `config.json`, `slugs.txt`, and `page.html` live in
  `~/found-data/`, outside the docroot: no URL maps to them, so
  their protection does not depend on any `.htaccess` rule.
- Path traversal is blocked twice: the rewrite pattern admits no `/`
  or `.`, and the CGI's own regex gate rejects the same before any
  file operation.
- Responses carry `X-Robots-Tag: noindex, nofollow` and the page a
  matching `<meta name="robots">`.

## Validation status

- HTML: Nu (W3C) HTML Checker — 0 errors, 0 warnings.
- CSS: stylelint, `stylelint-config-standard` — 0 problems.
- Python: mypy 1.4 `--python-version 3.7 --strict` — no issues;
  flake8 — clean; vermin — minimum required version 3.6.
- Behavior: 200 / 404 / traversal-rejection paths exercised.

## Maintenance

Contact info changed? Edit `config.json` on the server. Done — the
next request reads the new values. Nothing to restart, no labels to
reprint.

Tag compromised or item with tag sold? Delete its line from
`slugs.txt`; that URL immediately 404s like any other invalid slug.

## Local smoke test (any machine with python3)

```bash
printf 'ONE_REAL_SLUG_HERE00\n' > slugs.txt
PATH_INFO=/found/ONE_REAL_SLUG_HERE00 python3 found.cgi | head -1   # Status: 200 OK
PATH_INFO=/found/aaaaaaaaaaaaaaaaaaaa python3 found.cgi | head -1   # Status: 404 Not Found
```
