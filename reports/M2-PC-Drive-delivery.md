# M2 Windows Google Drive delivery

Status: implemented on `feat/m2-hamlet-building`; final CI receipt is recorded after the corrected pushed workflow completes.

Every branch push now produces two separately gated delivery artifacts from the same commit. The existing isolated ARM64 APK path is unchanged. The Windows path runs `tools/build.ps1 -WindowsOnly`, launches the exported executable headlessly as a smoke test, renames the shareable ZIP with the eight-character commit prefix, and runs `tools/verify-pc-build.py`.

The Windows receipt requires exactly `Hearthvale.exe`, `Hearthvale.pck`, and `README.txt` at the ZIP root; an x86-64 PE executable; a Godot PCK signature; and mouse/keyboard instructions. It records the full source commit, byte length, SHA-256, workflow run, platform, and architecture. The Drive job downloads and revalidates both the APK and Windows receipts before asking the private Apps Script bridge to copy each GitHub artifact. Existing Drive files are preserved and no public sharing is requested.

Local contract evidence on the pre-delivery runtime commit `401af4d44bd4db6b211732a464bfb90b7742a9b7`: five webhook contract tests pass. The existing Windows ZIP passes the new verifier at 40,682,250 bytes with SHA-256 `c2a0cdbaf39e8974e6ab9c0caced3fdbd5f74c8056f68478816368831aed22ff`. This local receipt validates the verifier against a real export; the final pushed commit must still complete CI before delivery is claimed.

The first end-to-end attempt, run `34387459753` at commit `1c42eef6d9510c3550046f7a5ce95ec12b485548`, passed all gameplay/render gates and produced verified APK and Windows artifacts, but the final Apps Script request failed. Inspection of the live receiver showed its Version 1 allowlist admitted only `.apk` and `.json`; it ignored the verified Windows ZIP. The receiver was updated in place and successfully deployed as Version 2 on 2026-09-09, adding `.zip` to the allowlist while retaining the existing secret check, 49 MiB download guard, same-name conflict rejection, destination folder, and private-sharing verification. No secret, deployment identifier, or folder identifier is stored in the repository.
