#!/usr/bin/python3.7
"""Lost-and-found tag contact page (CGI handler).

Serves ``https://www.example.com/found/<slug>``: a valid tag
slug renders a contact page from an HTML template and a JSON config;
anything else -- unknown slug, malformed slug, missing slug -- returns
a byte-identical generic 404, so valid and invalid tag URLs cannot be
distinguished from outside.

Design notes
------------
* Classic CGI process model: one process per request, exiting after
  the response is written. There is no daemon, no cache, and no shared
  state; data files are re-read on every request, so edits to the
  config or slug list take effect immediately with nothing to restart.
* Pure standard library, compatible with Python 3.7 (the interpreter
  available on the target shared host at ``/usr/bin/python3.7``).
* No deployment data lives in this file. Contact details, the slug
  list, and the page template are external (see ``DEFAULTS``); this
  script never needs editing.
* Input validation happens before any file access: the slug must match
  ``SLUG_PATTERN`` exactly, which admits no path separators, dots, or
  over/under-length input. Apache's rewrite rule enforces the same
  shape upstream, making this the second of two independent gates.

Request contract
----------------
Invoked by the web server with the CGI environment; the only variable
consulted is ``PATH_INFO``, expected in the form::

    /found/<slug>

where ``<slug>`` is exactly 20 characters of ``[A-Za-z0-9]``.
The response is a standard CGI response on stdout: a ``Status:``
header, ``Content-Type``, ``X-Robots-Tag``, a blank line, then the
HTML body.

Data files (paths overridable via environment variables)
---------------------------------------------------------
``config.json``   (``FOUND_CONFIG``)   -- template values; every value
                  is HTML-escaped at load time, so config content can
                  never inject markup.
``slugs.txt``     (``FOUND_SLUGS``)    -- one valid slug per line;
                  blank lines ignored. Deleting a line revokes that
                  tag URL immediately.
``page.html``     (``FOUND_TEMPLATE``) -- ``str.format`` template;
                  literal CSS braces are doubled (``{{ }}``).
"""

from typing import Dict, FrozenSet, Optional

import html
import json
import os
import re
import sys

# Data-file locations. Each may be overridden by the environment
# variable used as its key; otherwise the file is expected to sit in
# the same directory as this script.
_HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULTS = {
    "FOUND_CONFIG": os.path.join(_HERE, "config.json"),
    "FOUND_SLUGS": os.path.join(_HERE, "slugs.txt"),
    "FOUND_TEMPLATE": os.path.join(_HERE, "page.html"),
}

# The one and only acceptable slug shape. Anchored full-match of 20
# URL-safe alphanumeric characters: no separators, no dots, no other lengths.
SLUG_PATTERN = re.compile(r"^[A-Za-z0-9]{20}$")


def path_for(name: str) -> str:
    """Resolve the filesystem path for a named data file.

    Args:
        name: A key of ``DEFAULTS`` (``FOUND_CONFIG``, ``FOUND_SLUGS``,
            or ``FOUND_TEMPLATE``), doubling as the environment
            variable that may override it.

    Returns:
        The value of the environment variable ``name`` if set,
        otherwise the default path beside this script.

    Raises:
        KeyError: If ``name`` is not a key of ``DEFAULTS`` (programming
            error; never triggered by request input).
    """
    return os.environ.get(name, DEFAULTS[name])


def load_config() -> Dict[str, str]:
    """Load contact details for template substitution.

    Every value is passed through :func:`html.escape` and coerced to
    ``str``, so nothing in the config file can inject markup into the
    rendered page -- the config is data, never HTML.

    Returns:
        A mapping of template placeholder names to escaped values,
        suitable for ``page_template.format(**config)``.

    Raises:
        OSError: If the config file cannot be read.
        json.JSONDecodeError: If the file is not valid JSON.
    """
    with open(path_for("FOUND_CONFIG"), encoding="utf-8") as f:
        raw = json.load(f)
    return {key: html.escape(str(value)) for key, value in raw.items()}


def load_slugs() -> FrozenSet[str]:
    """Load the set of currently valid tag slugs.

    The file format is one slug per line; blank lines (including a
    trailing newline) are ignored. No shape validation is done here --
    membership is only ever tested against input that has already
    passed ``SLUG_PATTERN``.

    Returns:
        A frozen set of slug strings; empty if the file is empty.

    Raises:
        OSError: If the slug file cannot be read.
    """
    with open(path_for("FOUND_SLUGS"), encoding="utf-8") as f:
        return frozenset(line.strip() for line in f if line.strip())


def load_template() -> str:
    """Load the HTML page template.

    Returns:
        The template text verbatim. Placeholders use ``str.format``
        syntax (``{owner_name}`` etc.); literal braces in embedded CSS
        are doubled.

    Raises:
        OSError: If the template file cannot be read.
    """
    with open(path_for("FOUND_TEMPLATE"), encoding="utf-8") as f:
        return f.read()


def extract_slug(path_info: str) -> Optional[str]:
    """Extract and validate the slug from a CGI ``PATH_INFO`` value.

    The candidate is the final path segment after stripping leading
    and trailing slashes, so both ``/found/<slug>`` (production shape,
    via the rewrite rule) and ``/<slug>`` are accepted. The candidate
    is then matched against ``SLUG_PATTERN`` in full.

    This function is the script's input-validation gate: nothing that
    fails here reaches the filesystem or the response body.

    Args:
        path_info: The raw ``PATH_INFO`` string; may be empty.

    Returns:
        The validated slug, or ``None`` if the path does not contain
        a well-formed slug in its final segment.
    """
    candidate = path_info.strip("/").rpartition("/")[2]
    return candidate if SLUG_PATTERN.fullmatch(candidate) else None


def respond(status: str, body: str) -> None:
    """Write a complete CGI response to stdout.

    Emits ``Status`` and ``Content-Type`` headers, an
    ``X-Robots-Tag: noindex, nofollow`` header (the page also carries
    the equivalent meta tag), the header-terminating blank line, and
    the body. Header lines use CRLF per the CGI convention.

    Args:
        status: HTTP status line value, e.g. ``"200 OK"``.
        body: Complete HTML document to send as the response body.
    """
    sys.stdout.write(
        f"Status: {status}\r\n"
        "Content-Type: text/html; charset=utf-8\r\n"
        "X-Robots-Tag: noindex, nofollow\r\n"
        "\r\n"
    )
    sys.stdout.write(body)


def not_found() -> None:
    """Send the generic 404 response.

    Deliberately identical for every failure mode -- malformed slug,
    unknown slug, or missing slug -- so responses leak no information
    about which slugs exist or why a request failed.
    """
    respond("404 Not Found", "<!doctype html><title>Not Found</title><h1>Not Found</h1>")


def main() -> None:
    """Handle one CGI request.

    Flow: extract and validate the slug from ``PATH_INFO``; on any
    validation failure or unknown slug, send the generic 404;
    otherwise render the template with the escaped config values and
    send it with status 200.
    """
    slug = extract_slug(os.environ.get("PATH_INFO", ""))
    if slug is None or slug not in load_slugs():
        not_found()
        return
    respond("200 OK", load_template().format(**load_config()))


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        # Client closed the connection early; nothing useful to do.
        sys.exit(0)
