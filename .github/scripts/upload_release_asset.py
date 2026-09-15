#!/usr/bin/env python3
"""Upload or replace an asset in a GitHub release using the REST API."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def request(url: str, token: str, *, method: str = "GET", data: bytes | None = None,
            content_type: str | None = None) -> dict:
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req) as response:
        body = response.read()
    return json.loads(body) if body else {}


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <release-tag> <asset>", file=sys.stderr)
        return 2
    tag, asset_arg = sys.argv[1:]
    asset = Path(asset_arg)
    token = os.environ.get("GITHUB_TOKEN")
    repository = os.environ.get("GITHUB_REPOSITORY")
    if not token or not repository:
        raise SystemExit("GITHUB_TOKEN and GITHUB_REPOSITORY are required")
    if not asset.is_file():
        raise SystemExit(f"asset does not exist: {asset}")

    api = f"https://api.github.com/repos/{repository}"
    release = request(f"{api}/releases/tags/{urllib.parse.quote(tag)}", token)
    name = asset.name
    for existing in release.get("assets", []):
        if existing.get("name") == name:
            request(f"{api}/releases/assets/{existing['id']}", token, method="DELETE")
            break

    upload_url = release["upload_url"].split("{", 1)[0]
    upload_url += "?" + urllib.parse.urlencode({"name": name})
    request(upload_url, token, method="POST", data=asset.read_bytes(),
            content_type="application/x-xz")
    print(f"uploaded {name} to release {tag}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        print(f"GitHub API error {error.code}: {detail}", file=sys.stderr)
        raise
