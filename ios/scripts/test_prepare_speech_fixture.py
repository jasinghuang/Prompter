import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
import urllib.error

spec = importlib.util.spec_from_file_location("prepare_speech_fixture", Path(__file__).with_name("prepare-speech-fixture.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class ModelSourceFallbackTests(unittest.TestCase):
    def test_bad_mirror_content_uses_verified_backup(self):
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / "model.onnx"
            calls = []

            def fetch(url, timeout):
                calls.append(url)
                return io.BytesIO(b"bad" if url == "mirror" else b"yes")

            prepare.download_verified(target, 3, hashlib.sha256(b"yes").hexdigest(), ["mirror", "backup"], fetch)
            self.assertEqual(calls, ["mirror", "backup"])
            self.assertEqual(target.read_bytes(), b"yes")
            self.assertEqual(list(Path(root).glob("*.partial")), [])

    def test_network_failure_falls_back(self):
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / "tokens.txt"

            def fetch(url, timeout):
                if url == "mirror":
                    raise urllib.error.URLError("timed out")
                return io.BytesIO(b"yes")

            prepare.download_verified(target, 3, hashlib.sha256(b"yes").hexdigest(), ["mirror", "backup"], fetch)
            self.assertEqual(target.read_bytes(), b"yes")

    def test_failed_sources_do_not_replace_existing_model(self):
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / "model.onnx"
            target.write_bytes(b"previous verified model")
            with self.assertRaises(RuntimeError):
                prepare.download_verified(target, 3, hashlib.sha256(b"yes").hexdigest(),
                                          ["mirror", "backup"], lambda url, timeout: io.BytesIO(b"bad"))
            self.assertEqual(target.read_bytes(), b"previous verified model")
            self.assertEqual(list(Path(root).glob("*.partial")), [])


if __name__ == "__main__":
    unittest.main()
