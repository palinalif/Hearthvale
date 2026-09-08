#!/usr/bin/env python3
"""Upload one immutable CI artifact to a private Google Drive folder.

Uses a user OAuth refresh token because Hearthvale's destination is in My Drive.
The script never prints credentials or access tokens.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


TOKEN_URL = "https://oauth2.googleapis.com/token"
FILES_URL = "https://www.googleapis.com/drive/v3/files"
UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3/files"
FIELDS = "id,name,mimeType,size,md5Checksum,parents,shared,webViewLink"


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value


def request_json(request: urllib.request.Request, timeout: int = 60) -> tuple[dict, object]:
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
            return (json.loads(body) if body else {}), response.headers
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:1000]
        raise RuntimeError(f"Google Drive request failed with HTTP {error.code}: {detail}") from error


def access_token() -> str:
    form = urllib.parse.urlencode(
        {
            "client_id": required_env("GOOGLE_DRIVE_CLIENT_ID"),
            "client_secret": required_env("GOOGLE_DRIVE_CLIENT_SECRET"),
            "refresh_token": required_env("GOOGLE_DRIVE_REFRESH_TOKEN"),
            "grant_type": "refresh_token",
        }
    ).encode("ascii")
    payload, _ = request_json(
        urllib.request.Request(
            TOKEN_URL,
            data=form,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
    )
    token = str(payload.get("access_token", ""))
    if not token:
        raise RuntimeError("Google OAuth refresh succeeded without returning an access token")
    return token


def api_get(url: str, token: str) -> dict:
    payload, _ = request_json(
        urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    )
    return payload


def escape_query(value: str) -> str:
    return value.replace("\\", "\\\\").replace("'", "\\'")


def find_existing(name: str, folder_id: str, token: str) -> list[dict]:
    query = f"name = '{escape_query(name)}' and '{escape_query(folder_id)}' in parents and trashed = false"
    params = urllib.parse.urlencode(
        {
            "q": query,
            "spaces": "drive",
            "fields": f"files({FIELDS})",
            "pageSize": "10",
            "supportsAllDrives": "true",
            "includeItemsFromAllDrives": "true",
        }
    )
    return list(api_get(f"{FILES_URL}?{params}", token).get("files", []))


def verified_result(metadata: dict, path: Path, folder_id: str, md5: str) -> dict:
    if metadata.get("name") != path.name:
        raise RuntimeError("Drive readback name differs from the uploaded artifact")
    if int(metadata.get("size", -1)) != path.stat().st_size:
        raise RuntimeError("Drive readback size differs from the uploaded artifact")
    if metadata.get("md5Checksum", "").lower() != md5:
        raise RuntimeError("Drive readback checksum differs from the uploaded artifact")
    if folder_id not in metadata.get("parents", []):
        raise RuntimeError("Drive readback does not contain the requested parent folder")
    if metadata.get("shared") is not False:
        raise RuntimeError("Drive reports the uploaded artifact as shared; refusing a non-private delivery")
    return {
        "ok": True,
        "id": metadata["id"],
        "name": metadata["name"],
        "size": int(metadata["size"]),
        "md5": metadata["md5Checksum"].lower(),
        "parent": folder_id,
        "shared": False,
        "webViewLink": metadata["webViewLink"],
    }


def upload(path: Path, mime_type: str, folder_id: str, token: str) -> dict:
    md5 = hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()
    existing = find_existing(path.name, folder_id, token)
    if len(existing) > 1:
        raise RuntimeError(f"Drive contains multiple files named {path.name}; refusing an ambiguous delivery")
    if existing:
        return verified_result(existing[0], path, folder_id, md5)

    metadata = json.dumps(
        {
            "name": path.name,
            "mimeType": mime_type,
            "parents": [folder_id],
            "appProperties": {"hearthvaleCommit": os.environ.get("GITHUB_SHA", "local")},
        },
        separators=(",", ":"),
    ).encode("utf-8")
    params = urllib.parse.urlencode(
        {"uploadType": "resumable", "supportsAllDrives": "true", "fields": FIELDS}
    )
    _, headers = request_json(
        urllib.request.Request(
            f"{UPLOAD_URL}?{params}",
            data=metadata,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json; charset=UTF-8",
                "X-Upload-Content-Type": mime_type,
                "X-Upload-Content-Length": str(path.stat().st_size),
            },
            method="POST",
        )
    )
    session_url = headers.get("Location")
    if not session_url:
        raise RuntimeError("Drive did not return a resumable upload session URL")
    uploaded, _ = request_json(
        urllib.request.Request(
            session_url,
            data=path.read_bytes(),
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": mime_type,
                "Content-Length": str(path.stat().st_size),
            },
            method="PUT",
        ),
        timeout=300,
    )
    readback = api_get(
        f"{FILES_URL}/{urllib.parse.quote(str(uploaded['id']))}?"
        + urllib.parse.urlencode({"fields": FIELDS, "supportsAllDrives": "true"}),
        token,
    )
    return verified_result(readback, path, folder_id, md5)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("file", type=Path)
    parser.add_argument("--mime-type", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.file.is_file():
        raise RuntimeError(f"Artifact does not exist: {args.file}")
    folder_id = required_env("GOOGLE_DRIVE_FOLDER_ID")
    result = upload(args.file, args.mime_type, folder_id, access_token())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Drive delivery failed: {error}", file=sys.stderr)
        sys.exit(1)
