"""Verify the isolated Thor candidate; never publish keys or touch player saves."""
import hashlib
import json
import os
import re
import subprocess
import zipfile
from pathlib import Path


def run_checked(args):
    result = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} failed with exit {result.returncode}')
    return result.stdout


def main():
    sha = os.environ['GITHUB_SHA']
    short = sha[:8]
    assert re.fullmatch(r'[0-9a-f]{40}', sha), 'Invalid source revision'
    package = 'org.hearthvale.game.repair.c' + short
    apk = Path('builds') / f'hearthvale-m1-repair-{short}.apk'
    sdk = Path(os.environ['ANDROID_HOME']) / 'build-tools'
    versions = [p for p in sdk.iterdir() if p.is_dir() and re.fullmatch(r'\d+\.\d+\.\d+', p.name)]
    tools = max(versions, key=lambda p: tuple(map(int, p.name.split('.'))))
    java = Path(os.environ['JAVA_HOME']) / 'bin/java.exe'
    aapt = tools / 'aapt.exe'
    badging = run_checked([str(aapt), 'dump', 'badging', str(apk)])
    assert f"name='{package}'" in badging, 'Wrong APK package; original app must remain untouched'
    assert "versionCode='6'" in badging, 'Wrong candidate version'
    assert f"versionName='0.1.3-repair-{short}'" in badging, 'Missing build identity'
    manifest = run_checked([str(aapt), 'dump', 'xmltree', str(apk), 'AndroidManifest.xml'])
    assert re.search(r'org\.godotengine\.rendering\.method[^\n]*\n[^\n]*="mobile"', manifest), 'Mobile renderer metadata missing'
    signature = run_checked([str(java), '-jar', str(tools / 'lib/apksigner.jar'), 'verify', '--verbose', str(apk)])
    assert 'Verified using' in signature, 'No signature verification receipt'
    with zipfile.ZipFile(apk) as z:
        names = z.namelist()
        arches = sorted({n.split('/')[1] for n in names if n.startswith('lib/')})
        assert arches == ['arm64-v8a'], arches
        native = [n for n in names if n.startswith('lib/arm64-v8a/') and 'libvoxel' in n]
        assert len(native) == 1, 'Expected one native voxel library'
        pinned = list(Path('addons/zylann.voxel').rglob(Path(native[0]).name))
        assert len(pinned) == 1, 'Pinned voxel library missing or ambiguous'
        assert hashlib.sha256(z.read(native[0])).digest() == hashlib.sha256(pinned[0].read_bytes()).digest(), 'Native library differs from locked dependency'
        assert 'assets/scripts/m1_scene_playtest_repair.gdc' in names, 'Repair scene not compiled into APK'
        assert not any(n.startswith(('assets/tests/', 'assets/tools/', 'assets/docs/', 'assets/reports/', 'assets/tasks/', 'assets/dev/', 'assets/.codex/')) or 'godot_ai' in n for n in names), 'Development content included'
    receipt = {
        'ok': True, 'commit': sha, 'workflow_run': os.environ['GITHUB_RUN_ID'],
        'apk': apk.name, 'bytes': apk.stat().st_size, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
        'package': package, 'version_code': 6, 'version_name': '0.1.3-repair-' + short,
        'installation': 'separate test app; fresh saves; does not replace org.hearthvale.game',
        'signature_verified': True, 'metadata_verified': True, 'renderer': 'mobile',
        'architectures': arches, 'native_matches_pinned': True,
        'compiled_repair_scene': True, 'development_resources_excluded': True,
        'physical_thor_validation': 'not run; player playtest required',
    }
    apk.with_suffix('.verification.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
