#!/usr/bin/env python3
"""Fetch checksummed build dependencies into the project cache, never the system.

Linux x86_64: --toolchain additionally builds isolated CPython 2.7 and installs
the portable Java runtime. Other platforms may supply their own tools to build.py.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "better-sense"
LOCK = json.loads((ROOT / "tools" / "toolchain.lock.json").read_text())


def digest(path, algorithm="sha256"):
    result = hashlib.new(algorithm)
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def fetch(url, target, expected, algorithm="sha256"):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and digest(target, algorithm) == expected:
        return target
    temporary = target.with_suffix(target.suffix + ".download")
    print("Download:", url, flush=True)
    request = urllib.request.Request(url, headers={"User-Agent": "BetterSense-build/0.1"})
    try:
        with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if digest(temporary, algorithm) != expected:
            raise RuntimeError("Checksum mismatch: " + url)
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    return target


def unpack(key, filename):
    spec = LOCK[key]
    algorithm = "sha512" if "sha512" in spec else "sha256"
    archive = fetch(spec["url"], CACHE / "downloads" / filename, spec[algorithm], algorithm)
    destination = CACHE / "toolchain"
    destination.mkdir(parents=True, exist_ok=True)
    expected = destination / spec["directory"]
    if not expected.is_dir():
        with tempfile.TemporaryDirectory(prefix="extract-", dir=destination) as temporary:
            with tarfile.open(archive) as source:
                # Python 3.12+ data filter rejects traversal and external links.
                source.extractall(temporary, filter="data")
            if not (Path(temporary) / spec["directory"]).is_dir():
                raise RuntimeError("Unexpected archive layout: " + key)
            top = Path(spec["directory"]).parts[0]
            shutil.move(str(Path(temporary) / top), str(destination / top))
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", action="store_true", help="also provision isolated compiler, Java and Python 2.7 (Linux x86_64)")
    parser.add_argument("--test-runtime", action="store_true", help="also fetch Ruffle for pure AS3 tests")
    args = parser.parse_args()
    for name, expected in LOCK["libraries"].items():
        fetch(LOCK["game_swc_base_url"] + name, CACHE / "libs" / name, expected)
    spec = LOCK["playerglobal"]
    fetch(spec["url"], CACHE / "libs" / "playerglobal.swc", spec["sha256"])
    if args.toolchain:
        if platform.system() != "Linux" or platform.machine() not in ("x86_64", "AMD64"):
            parser.error("--toolchain supports Linux x86_64; supply local Java, Royale and Python 2.7 to build.py on other systems")
        unpack("royale", "royale.tar.gz")
        unpack("java_linux_x86_64", "java.tar.gz")
        source = unpack("python2", "python.tar.xz")
        installation = CACHE / "toolchain" / "python2"
        if not (installation / "bin" / "python2.7").exists():
            environment = dict(os.environ, CFLAGS="-std=gnu11")
            commands = [
                ["./configure", "--prefix=" + str(installation), "--without-ensurepip", "--disable-shared"],
                ["make", "-j" + str(min(os.cpu_count() or 2, 6))],
                ["make", "install"],
            ]
            log = CACHE / "python2-build.log"
            print("Building isolated Python 2.7; log:", log, flush=True)
            with log.open("w") as output:
                for command in commands:
                    subprocess.run(command, cwd=source, env=environment, stdout=output, stderr=subprocess.STDOUT, check=True)
    if args.test_runtime:
        unpack("ruffle", "ruffle.tar.gz")
    print("Dependencies verified:", CACHE)


if __name__ == "__main__":
    main()
