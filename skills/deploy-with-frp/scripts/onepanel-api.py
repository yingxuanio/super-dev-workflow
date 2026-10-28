#!/usr/bin/env python3
"""Call the local 1Panel v2 API with redacted output and write safeguards."""

import argparse
import hashlib
import hmac
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request


SAFE_POST_PATHS = {
    "/groups/search",
    "/websites/search",
    "/websites/proxies",
    "/websites/ssl/search",
}
SENSITIVE_KEY = re.compile(
    r"token|secret|password|private.?key|certificate|cert|pem|authorization",
    re.IGNORECASE,
)


def signature(api_key: str, timestamp: str, method: str) -> str:
    if method == "hmac":
        return hmac.new(
            api_key.encode(), f"1panel:{timestamp}".encode(), hashlib.sha256
        ).hexdigest()
    return hashlib.md5(f"1panel{api_key}{timestamp}".encode()).hexdigest()


def redact(value):
    if isinstance(value, dict):
        return {
            key: "<redacted>" if SENSITIVE_KEY.search(str(key)) else redact(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact(item) for item in value]
    return value


def request(base_url: str, path: str, method: str, body, api_key: str, auth: str):
    timestamp = str(int(time.time()))
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "1Panel-Timestamp": timestamp,
        "1Panel-Token": signature(api_key, timestamp, auth),
    }
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/v2{path}", data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as error:
        payload = error.read().decode()
        try:
            return error.code, json.loads(payload)
        except json.JSONDecodeError:
            return error.code, {"code": error.code, "message": payload[:500]}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("method", choices=("GET", "POST", "PUT", "DELETE"))
    parser.add_argument("path", help="API path below /api/v2, for example /websites/list")
    parser.add_argument("--base-url", default="https://panel.linktion.cn")
    parser.add_argument("--data", help="JSON request body")
    parser.add_argument("--auth", choices=("auto", "hmac", "md5"), default="auto")
    parser.add_argument("--allow-write", action="store_true")
    args = parser.parse_args()

    path = "/" + args.path.lstrip("/")
    is_safe = args.method == "GET" or (args.method == "POST" and path in SAFE_POST_PATHS)
    if not is_safe and not args.allow_write:
        parser.error("mutating endpoint requires --allow-write")

    api_key = os.environ.get("ONEPANEL_API_KEY")
    if not api_key:
        parser.error("ONEPANEL_API_KEY is not set")

    try:
        body = None if args.data is None else json.loads(args.data)
    except json.JSONDecodeError as error:
        parser.error(f"invalid --data JSON: {error}")

    auth_methods = ("hmac", "md5") if args.auth == "auto" else (args.auth,)
    status = 0
    payload = {}
    for auth_method in auth_methods:
        status, payload = request(
            args.base_url, path, args.method, body, api_key, auth_method
        )
        if not (status == 401 or payload.get("code") == 401):
            break

    print(json.dumps(redact(payload), ensure_ascii=False, indent=2))
    code = payload.get("code") if isinstance(payload, dict) else None
    return 0 if status < 400 and code in (None, 200) else 1


if __name__ == "__main__":
    sys.exit(main())
