import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "tools" / "upload-google-drive.py"
SPEC = importlib.util.spec_from_file_location("drive_upload", SCRIPT)
drive_upload = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(drive_upload)


class DriveUploadContractTest(unittest.TestCase):
    def test_query_escaping(self):
        self.assertEqual(drive_upload.escape_query("it's\\ready"), "it\\'s\\\\ready")

    def test_verified_private_readback(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "candidate.apk"
            path.write_bytes(b"verified candidate")
            md5 = drive_upload.hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()
            result = drive_upload.verified_result(
                {
                    "id": "file-id",
                    "name": path.name,
                    "size": str(path.stat().st_size),
                    "md5Checksum": md5,
                    "parents": ["folder-id"],
                    "shared": False,
                    "webViewLink": "https://drive.google.com/file/d/file-id/view",
                },
                path,
                "folder-id",
                md5,
            )
            self.assertTrue(result["ok"])
            self.assertFalse(result["shared"])

    def test_shared_readback_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "candidate.apk"
            path.write_bytes(b"verified candidate")
            md5 = drive_upload.hashlib.md5(path.read_bytes(), usedforsecurity=False).hexdigest()
            with self.assertRaisesRegex(RuntimeError, "shared"):
                drive_upload.verified_result(
                    {
                        "id": "file-id",
                        "name": path.name,
                        "size": str(path.stat().st_size),
                        "md5Checksum": md5,
                        "parents": ["folder-id"],
                        "shared": True,
                        "webViewLink": "https://drive.google.com/file/d/file-id/view",
                    },
                    path,
                    "folder-id",
                    md5,
                )


if __name__ == "__main__":
    unittest.main()
