#!/usr/bin/env python3
"""Ask the private Apps Script webhook to copy one verified CI artifact to Drive.

GitHub's artifact archive endpoint requires authentication even for public
repositories. This client exchanges that endpoint for its short-lived signed
redirect, then gives only the temporary download URL to Apps Script. It never
prints the GitHub token, webhook secret, or signed URL.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


MAX_ARCHIVE_BYTES = 50 * 1024 * 1024
WEBHOOK_MAX_ATTEMPTS = 4
WEBHOOK_RETRY_BASE_SECONDS = 2.0
TRANSIENT_HTTP_CODES = {408, 425, 429, 500, 502, 503, 504}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value


def github_json(url: str, token: str) -> dict:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read())


def select_artifact(payload: dict, expected_name: str) -> dict:
    matches = [item for item in payload.get("artifacts", []) if item.get("name") == expected_name]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one GitHub artifact named {expected_name}; found {len(matches)}")
    artifact = matches[0]
    if artifact.get("expired"):
        raise RuntimeError(f"GitHub artifact is expired: {expected_name}")
    size = int(artifact.get("size_in_bytes", -1))
    if size < 1 or size > MAX_ARCHIVE_BYTES:
        raise RuntimeError(f"GitHub artifact archive is {size} bytes; Apps Script accepts at most {MAX_ARCHIVE_BYTES}")
    url = str(artifact.get("archive_download_url", ""))
    if not url.startswith("https://api.github.com/"):
        raise RuntimeError("GitHub returned an invalid artifact archive URL")
    return artifact


def signed_archive_url(archive_url: str, token: str) -> str:
    request = urllib.request.Request(
        archive_url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    opener = urllib.request.build_opener(NoRedirect)
    try:
        opener.open(request, timeout=60)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            detail = error.read().decode("utf-8", errors="replace")[:500]
            raise RuntimeError(f"GitHub artifact redirect failed with HTTP {error.code}: {detail}") from error
        location = error.headers.get("Location", "")
        if location.startswith("https://"):
            return location
    raise RuntimeError("GitHub did not return a secure signed artifact URL")


def validate_webhook_response(payload: dict, expected_files: set[str]) -> dict:
    if payload.get("ok") is not True:
        raise RuntimeError(f"Apps Script delivery failed: {payload.get('error', 'unknown error')}")
    files = payload.get("files")
    if not isinstance(files, list):
        raise RuntimeError("Apps Script response did not contain a files list")
    names = {str(item.get("name", "")) for item in files if isinstance(item, dict)}
    missing = expected_files - names
    if missing:
        raise RuntimeError(f"Apps Script did not confirm expected files: {sorted(missing)}")
    for item in files:
        if item.get("name") in expected_files:
            if int(item.get("size", 0)) < 1 or not str(item.get("url", "")).startswith("https://drive.google.com/"):
                raise RuntimeError(f"Apps Script returned invalid Drive metadata for {item.get('name')}")
    return {"ok": True, "files": [item for item in files if item.get("name") in expected_files]}


def _webhook_retry_delay(error: urllib.error.HTTPError, attempt: int) -> float:
    retry_after = error.headers.get("Retry-After", "") if error.headers else ""
    try:
        if retry_after:
            return min(30.0, max(0.0, float(retry_after)))
    except ValueError:
        pass
    return WEBHOOK_RETRY_BASE_SECONDS * (2 ** attempt)


def notify(
    webhook_url: str,
    secret: str,
    download_url: str,
    expected_files: set[str],
    *,
    sleep_fn=time.sleep,
) -> dict:
    body = json.dumps({"secret": secret, "download_url": download_url}, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        webhook_url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    for attempt in range(WEBHOOK_MAX_ATTEMPTS):
        try:
            with urllib.request.urlopen(request, timeout=360) as response:
                payload = json.loads(response.read())
            return validate_webhook_response(payload, expected_files)
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")[:500]
            transient = error.code in TRANSIENT_HTTP_CODES or 500 <= error.code <= 599
            if not transient or attempt + 1 >= WEBHOOK_MAX_ATTEMPTS:
                raise RuntimeError(f"Apps Script webhook failed with HTTP {error.code}: {detail}") from error
            delay = _webhook_retry_delay(error, attempt)
            print(
                f"Apps Script webhook returned transient HTTP {error.code}; "
                f"retrying attempt {attempt + 2}/{WEBHOOK_MAX_ATTEMPTS} in {delay:g}s",
                file=sys.stderr,
            )
            # The receiver treats already-copied files as reusable, so retrying
            # a transient response is safe even if the prior request completed.
            sleep_fn(delay)
    raise RuntimeError("Apps Script webhook retry loop ended unexpectedly")


def delivery_spec(kind: str, commit: str) -> tuple[str, set[str]]:
    short = commit[:8]
    if kind == "apk":
        return (
            f"hearthvale-m1-repair-{commit}",
            {
                f"hearthvale-m1-repair-{short}.apk",
                f"hearthvale-m1-repair-{short}.verification.json",
            },
        )
    if kind == "pc":
        return (
            f"hearthvale-m2-pc-{commit}",
            {
                f"Hearthvale-M2-PC-{short}.zip",
                f"Hearthvale-M2-PC-{short}.verification.json",
            },
        )
    raise RuntimeError(f"Unsupported delivery kind: {kind}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--artifact-kind", choices=("apk", "pc"), default="apk")
    args = parser.parse_args()

    api_url = required_env("GITHUB_API_URL").rstrip("/")
    repository = required_env("GITHUB_REPOSITORY")
    run_id = required_env("GITHUB_RUN_ID")
    commit = required_env("GITHUB_SHA")
    token = required_env("GITHUB_TOKEN")
    webhook_url = required_env("APPS_SCRIPT_WEBHOOK_URL")
    webhook_secret = required_env("APPS_SCRIPT_WEBHOOK_SECRET")
    if not webhook_url.startswith("https://script.google.com/"):
        raise RuntimeError("APPS_SCRIPT_WEBHOOK_URL must be an HTTPS script.google.com URL")

    artifact_name, expected_files = delivery_spec(args.artifact_kind, commit)
    listing_url = f"{api_url}/repos/{repository}/actions/runs/{urllib.parse.quote(run_id)}/artifacts?per_page=100"
    artifact = select_artifact(github_json(listing_url, token), artifact_name)
    download_url = signed_archive_url(str(artifact["archive_download_url"]), token)
    result = notify(webhook_url, webhook_secret, download_url, expected_files)
    result.update({"artifact": artifact_name, "artifact_kind": args.artifact_kind, "commit": commit})
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "artifact": artifact_name, "files": sorted(expected_files)}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Drive delivery failed: {error}", file=sys.stderr)
        sys.exit(1)
