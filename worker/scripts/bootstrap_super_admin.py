#!/usr/bin/env python3
"""Create the first super-admin using the Worker verifier protocol."""

import argparse
import base64
import getpass
import hashlib
import json
import secrets
import urllib.error
import urllib.request


ITERATIONS = 600_000
CURL_USER_AGENT = "curl/8.14.1"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("worker_url", help="Worker origin, e.g. https://accounts.example.workers.dev")
    parser.add_argument("username")
    parser.add_argument("--display-name")
    args = parser.parse_args()

    password = getpass.getpass("Initial password (at least 8 characters): ")
    if len(password) < 8:
        parser.error("password must be at least 8 characters")
    bootstrap_secret = getpass.getpass("BOOTSTRAP_SECRET: ")
    if len(bootstrap_secret) < 32:
        parser.error("BOOTSTRAP_SECRET must be at least 32 characters")

    salt = secrets.token_bytes(16)
    verifier = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, ITERATIONS, dklen=32)
    payload = {
        "username": args.username,
        "displayName": args.display_name or args.username,
        "salt": base64.b64encode(salt).decode(),
        "iterations": ITERATIONS,
        "verifier": base64.b64encode(verifier).decode(),
    }
    url = args.worker_url.rstrip("/") + "/api/v1/bootstrap"
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={
            "Content-Type": "application/json",
            "X-Bootstrap-Secret": bootstrap_secret,
            "User-Agent": CURL_USER_AGENT,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print(response.read().decode())
    except urllib.error.HTTPError as error:
        print(f"HTTP {error.code}: {error.read().decode()}")
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
