#!/usr/bin/env python3
"""Verify the shareable Windows playtest ZIP and write its delivery receipt."""

from __future__ import annotations

import hashlib
import json
import os
import re
import struct
import subprocess
import zipfile
from pathlib import Path


EXPECTED_FILES = {"Hearthvale.exe", "Hearthvale.pck", "README.txt"}


def source_revision() -> str:
    revision = os.environ.get("GITHUB_SHA", "").strip()
    if not revision:
        revision = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], text=True, encoding="utf-8"
        ).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise RuntimeError("Invalid source revision")
    return revision


def pe_machine(payload: bytes) -> int:
    if len(payload) < 64 or payload[:2] != b"MZ":
        raise RuntimeError("Windows executable has no DOS header")
    pe_offset = struct.unpack_from("<I", payload, 0x3C)[0]
    if pe_offset + 6 > len(payload) or payload[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise RuntimeError("Windows executable has no PE header")
    return struct.unpack_from("<H", payload, pe_offset + 4)[0]


def verify_archive(package: Path, revision: str) -> dict:
    if not package.is_file():
        raise RuntimeError(f"PC package is missing: {package}")
    with zipfile.ZipFile(package) as archive:
        file_names = {name.replace("\\", "/") for name in archive.namelist() if not name.endswith("/")}
        if file_names != EXPECTED_FILES:
            raise RuntimeError(f"Unexpected PC package contents: {sorted(file_names)}")
        exe = archive.read("Hearthvale.exe")
        pck = archive.read("Hearthvale.pck")
        readme = archive.read("README.txt")
    if pe_machine(exe) != 0x8664:
        raise RuntimeError("Windows executable is not x86-64")
    if pck[:4] != b"GDPC":
        raise RuntimeError("Godot PCK signature is missing")
    if b"MOUSE" not in readme or b"KEYBOARD" not in readme:
        raise RuntimeError("PC playtest instructions are incomplete")
    return {
        "ok": True,
        "commit": revision,
        "workflow_run": os.environ.get("GITHUB_RUN_ID", "local"),
        "pc_zip": package.name,
        "bytes": package.stat().st_size,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "platform": "windows",
        "architecture": "x86_64",
        "package_files": sorted(EXPECTED_FILES),
        "executable_verified": True,
        "pck_verified": True,
        "instructions_verified": True,
        "code_signed": False,
    }


def main() -> None:
    revision = source_revision()
    short = revision[:8]
    package = Path("builds") / f"Hearthvale-M2-PC-{short}.zip"
    receipt = verify_archive(package, revision)
    receipt_path = package.with_suffix(".verification.json")
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
