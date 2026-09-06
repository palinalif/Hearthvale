"""Verify local M1 exports without printing signing identifiers or secrets."""
import argparse
import hashlib
import json
import os
import re
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
SDK = Path(os.environ["LOCALAPPDATA"]) / "Android/Sdk/build-tools/36.0.0"
JAVA = Path("C:/Program Files/Eclipse Adoptium/jdk-17.0.19.10-hotspot/bin/java.exe")

def signature(path):
    result = subprocess.run([str(JAVA), "-jar", str(SDK / "lib/apksigner.jar"), "verify", "--verbose", "--print-certs", str(path)], capture_output=True, text=True)
    digest = re.search(r"certificate SHA-256 digest: ([0-9a-f]+)", result.stdout)
    assert result.returncode == 0 and digest, "APK signature verification failed"
    return digest.group(1)

parser = argparse.ArgumentParser()
parser.add_argument('--apk', help='Verify only this versioned Mobile debug APK')
parser.add_argument('--report', default='reports/m1-rework-apk-verification.json')
args = parser.parse_args()
preset_text = Path('export_presets.cfg').read_text(encoding='utf-8')
version_code = int(re.search(r'version/code=(\d+)', preset_text).group(1))
version_name = re.search(r'version/name="([^"]+)"', preset_text).group(1)
previous_signature = signature(Path("builds/m1-first-playtest/hearthvale-m1-debug.apk"))
results = []
for flavor in (["debug"] if args.apk else ["debug", "release", "compatibility"]):
    apk = Path(args.apk) if args.apk else Path("builds/hearthvale-m1-" + flavor + ".apk")
    badging = subprocess.run([str(SDK / "aapt2.exe"), "dump", "badging", str(apk)], capture_output=True, text=True)
    manifest = subprocess.run([str(SDK / "aapt.exe"), "dump", "xmltree", str(apk), "AndroidManifest.xml"], capture_output=True, text=True)
    renderer = "gl_compatibility" if flavor == "compatibility" else "mobile"
    metadata = f"versionCode='{version_code}'" in badging.stdout and f"versionName='{version_name}'" in badging.stdout and "name='org.hearthvale.game'" in badging.stdout
    renderer_ok = re.search(r'org\.godotengine\.rendering\.method[^\n]*\n[^\n]*="' + renderer + '"', manifest.stdout) is not None
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        native = [n for n in names if n.startswith("lib/") and "libvoxel" in n]
        assert len(native) == 1
        pinned = list(Path("addons/zylann.voxel").rglob(Path(native[0]).name))
        assert len(pinned) == 1
        native_ok = hashlib.sha256(archive.read(native[0])).digest() == hashlib.sha256(pinned[0].read_bytes()).digest()
        architectures = sorted({n.split('/')[1] for n in names if n.startswith('lib/')})
        compiled = any('m1_scene' in n and n.endswith('.gdc') for n in names)
        excluded = not any(n.startswith(('assets/dev/', 'assets/tests/', 'assets/docs/', 'assets/reports/', 'assets/tasks/', 'assets/.codex/', 'assets/tools/')) or 'godot_ai' in n for n in names)
    same_signature = signature(apk) == previous_signature
    passed = all([badging.returncode == 0, manifest.returncode == 0, metadata, renderer_ok, native_ok, architectures == ['arm64-v8a'], compiled, excluded, same_signature])
    result = dict(apk=str(apk), ok=passed, version_code=version_code, version_name=version_name, manifest_renderer=renderer, renderer_verified=renderer_ok, metadata_verified=metadata, signature_verified=True, certificate_matches_previous_build=same_signature, native_library=native[0], native_matches_pinned=native_ok, architectures=architectures, m1_compiled_scene_present=compiled, excluded_development_resources=excluded, aapt2_exit=badging.returncode, aapt2_warning=badging.stderr.strip(), bytes=apk.stat().st_size, sha256=hashlib.sha256(apk.read_bytes()).hexdigest())
    results.append(result)
Path(args.report).write_text(json.dumps(results, indent=2), encoding='utf-8')
assert all(r['ok'] for r in results), 'APK verification failed; inspect report'
print(json.dumps(results, indent=2))
