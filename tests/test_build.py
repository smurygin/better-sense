import json
import io
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from build import ENTRY_NAME, PYTHON_MAGIC, SWF_NAME, normalize_swf, package_entries, validate_package
from bootstrap import digest, fetch


def swf_with_timestamp(timestamp):
    # RECT, frame rate/count, ProductInfo, End. Two builds must differ only in
    # compiler timestamp; normalizing must not change the other ProductInfo data.
    body = b"\0" * 5 + struct.pack("<H", (41 << 6) | 26) + b"x" * 18 + struct.pack("<Q", timestamp) + b"\0\0"
    return b"FWS\x11" + struct.pack("<I", len(body) + 8) + body


def package_fixture():
    bytecode = PYTHON_MAGIC + b"\0" * 4 + b"c"
    return {
        "meta.xml": b"<mod><name>Better Sense</name><version>1.0.0</version></mod>",
        SWF_NAME: swf_with_timestamp(0),
        ENTRY_NAME: bytecode,
        "res/scripts/client/gui/mods/better_sense/__init__.pyc": bytecode,
    }


class BuildTests(unittest.TestCase):
    def test_verified_cache_needs_no_network_and_bad_download_preserves_cache(self):
        with tempfile.TemporaryDirectory() as temporary:
            cached = Path(temporary) / "library.swc"
            cached.write_bytes(b"verified library")
            expected = digest(cached)
            with patch("bootstrap.urllib.request.urlopen", side_effect=AssertionError("network must not be used")):
                self.assertEqual(fetch("https://example.invalid/library", cached, expected), cached)
            with patch("bootstrap.urllib.request.urlopen", return_value=io.BytesIO(b"corrupted download")):
                with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                    fetch("https://example.invalid/library", cached, "0" * 64)
            self.assertEqual(cached.read_bytes(), b"verified library")
            self.assertFalse(cached.with_suffix(".swc.download").exists())

    def test_archive_is_deterministic_and_uncompressed(self):
        with tempfile.TemporaryDirectory() as temporary:
            first = Path(temporary) / "first.mtmod"
            second = Path(temporary) / "second.mtmod"
            entries = package_fixture()
            package_entries(first, entries)
            package_entries(second, dict(reversed(list(entries.items()))))
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist(), sorted(entries))
                self.assertTrue(all(item.compress_type == zipfile.ZIP_STORED for item in archive.infolist()))

    def test_swf_wall_clock_is_removed_without_changing_product_info(self):
        first = normalize_swf(swf_with_timestamp(100))
        second = normalize_swf(swf_with_timestamp(200))
        self.assertEqual(first, second)
        self.assertIn(b"x" * 18, first)
        self.assertEqual(first, normalize_swf(first))
        compressed = b"CWS" + first[3:8] + zlib.compress(first[8:])
        self.assertEqual(normalize_swf(compressed), first)

    def test_rejects_incorrect_python_and_unexpected_files(self):
        for bad_name, bad_content in [
            (ENTRY_NAME, b"\xa7\r\r\n" + b"\0" * 12),
            ("res/gui/flash/gui_base.swc", b"client library"),
            ("res/scripts/client/gui/mods/other_mod.pyc", PYTHON_MAGIC + b"\0" * 8),
            ("../escape", b"x"),
        ]:
            with self.subTest(name=bad_name), tempfile.TemporaryDirectory() as temporary:
                entries = package_fixture()
                entries[bad_name] = bad_content
                destination = Path(temporary) / "mod.mtmod"
                with self.assertRaises(ValueError):
                    package_entries(destination, entries)
                self.assertFalse(destination.exists())

    def test_failed_build_preserves_previously_valid_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "mod.mtmod"
            package_entries(destination, package_fixture())
            original = destination.read_bytes()
            entries = package_fixture()
            del entries[SWF_NAME]
            with self.assertRaises(ValueError):
                package_entries(destination, entries)
            self.assertEqual(destination.read_bytes(), original)

    def test_python2_compilation_never_executes_source_and_uses_stable_filename(self):
        interpreter = ROOT / ".cache/better-sense/toolchain/python2/bin/python2.7"
        if not interpreter.is_file():
            self.skipTest("isolated Python 2.7 not provisioned")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "fixture.py"
            output = root / "fixture.pyc"
            source.write_bytes(b"# coding: utf-8\nVERSION = '{{VERSION}}'\nraise RuntimeError('must not execute')\n")
            manifest = root / "jobs.json"
            manifest.write_text(json.dumps([{
                "source": str(source), "output": str(output),
                "filename": "res/scripts/client/gui/mods/fixture.py", "version": "1.0.0",
            }]))
            subprocess.run([str(interpreter), "-B", str(ROOT / "tools/compile_python2.py"), str(manifest)], check=True)
            compiled = output.read_bytes()
            self.assertEqual(compiled[:8], PYTHON_MAGIC + b"\0" * 4)
            self.assertIn(b"res/scripts/client/gui/mods/fixture.py", compiled)
            self.assertNotIn(temporary.encode(), compiled)
            self.assertIn(b"1.0.0", compiled)
            self.assertNotIn(b"{{VERSION}}", compiled)


if __name__ == "__main__":
    unittest.main()
