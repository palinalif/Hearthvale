import importlib.util
import io
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).parents[1] / "tools" / "upload-google-drive.py"
SPEC = importlib.util.spec_from_file_location("drive_upload", SCRIPT)
drive_upload = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(drive_upload)


class FakeResponse:
    def __init__(self, payload: bytes):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def read(self):
        return self.payload


class DriveUploadContractTest(unittest.TestCase):
    def test_builds_versioned_apk_and_pc_delivery_specs(self):
        commit = "a" * 40
        apk_artifact, apk_files = drive_upload.delivery_spec("apk", commit)
        pc_artifact, pc_files = drive_upload.delivery_spec("pc", commit)
        self.assertEqual(apk_artifact, f"hearthvale-m1-repair-{commit}")
        self.assertEqual(
            apk_files,
            {"hearthvale-m1-repair-aaaaaaaa.apk", "hearthvale-m1-repair-aaaaaaaa.verification.json"},
        )
        self.assertEqual(pc_artifact, f"hearthvale-m2-pc-{commit}")
        self.assertEqual(
            pc_files,
            {"Hearthvale-M2-PC-aaaaaaaa.zip", "Hearthvale-M2-PC-aaaaaaaa.verification.json"},
        )

    def test_selects_exact_unexpired_artifact(self):
        artifact = drive_upload.select_artifact(
            {
                "artifacts": [
                    {
                        "name": "hearthvale-m1-repair-fullsha",
                        "expired": False,
                        "size_in_bytes": 32000000,
                        "archive_download_url": "https://api.github.com/repos/example/project/actions/artifacts/1/zip",
                    }
                ]
            },
            "hearthvale-m1-repair-fullsha",
        )
        self.assertEqual(artifact["size_in_bytes"], 32000000)

    def test_rejects_archive_above_apps_script_limit(self):
        with self.assertRaisesRegex(RuntimeError, "Apps Script accepts at most"):
            drive_upload.select_artifact(
                {
                    "artifacts": [
                        {
                            "name": "candidate",
                            "expired": False,
                            "size_in_bytes": drive_upload.MAX_ARCHIVE_BYTES + 1,
                            "archive_download_url": "https://api.github.com/repos/example/project/actions/artifacts/1/zip",
                        }
                    ]
                },
                "candidate",
            )

    def test_validates_private_drive_delivery_shape(self):
        expected = {"candidate.apk", "candidate.verification.json"}
        result = drive_upload.validate_webhook_response(
            {
                "ok": True,
                "files": [
                    {"name": "candidate.apk", "size": 12, "url": "https://drive.google.com/file/d/apk/view", "reused": False},
                    {"name": "candidate.verification.json", "size": 4, "url": "https://drive.google.com/file/d/json/view", "reused": True},
                ],
            },
            expected,
        )
        self.assertTrue(result["ok"])
        self.assertEqual({item["name"] for item in result["files"]}, expected)

    def test_rejects_missing_receipt(self):
        with self.assertRaisesRegex(RuntimeError, "did not confirm expected files"):
            drive_upload.validate_webhook_response(
                {"ok": True, "files": [{"name": "candidate.apk", "size": 12, "url": "https://drive.google.com/file/d/apk/view"}]},
                {"candidate.apk", "candidate.verification.json"},
            )

    def test_retries_transient_webhook_503_then_succeeds(self):
        expected = {"candidate.zip", "candidate.verification.json"}
        transient = urllib.error.HTTPError(
            "https://script.google.com/macros/s/test/exec",
            503,
            "Service Unavailable",
            {},
            io.BytesIO(b"busy"),
        )
        success = FakeResponse(
            b'{"ok":true,"files":['
            b'{"name":"candidate.zip","size":12,"url":"https://drive.google.com/file/d/zip/view"},'
            b'{"name":"candidate.verification.json","size":4,"url":"https://drive.google.com/file/d/json/view"}'
            b']}'
        )
        delays = []
        with mock.patch.object(drive_upload.urllib.request, "urlopen", side_effect=[transient, success]) as urlopen:
            result = drive_upload.notify(
                "https://script.google.com/macros/s/test/exec",
                "secret",
                "https://example.invalid/artifact.zip",
                expected,
                sleep_fn=delays.append,
            )
        self.assertTrue(result["ok"])
        self.assertEqual(urlopen.call_count, 2)
        self.assertEqual(delays, [drive_upload.WEBHOOK_RETRY_BASE_SECONDS])

    def test_does_not_retry_non_transient_webhook_error(self):
        expected = {"candidate.zip"}
        bad_request = urllib.error.HTTPError(
            "https://script.google.com/macros/s/test/exec",
            400,
            "Bad Request",
            {},
            io.BytesIO(b"bad payload"),
        )
        delays = []
        with mock.patch.object(drive_upload.urllib.request, "urlopen", side_effect=bad_request) as urlopen:
            with self.assertRaisesRegex(RuntimeError, "HTTP 400"):
                drive_upload.notify(
                    "https://script.google.com/macros/s/test/exec",
                    "secret",
                    "https://example.invalid/artifact.zip",
                    expected,
                    sleep_fn=delays.append,
                )
        self.assertEqual(urlopen.call_count, 1)
        self.assertEqual(delays, [])


if __name__ == "__main__":
    unittest.main()
