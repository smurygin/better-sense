#!/usr/bin/env python3
"""Compile Better Sense and create a deterministic, uncompressed .mtmod archive."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile
import zlib

from bootstrap import CACHE, LOCK, ROOT, digest

PYTHON_MAGIC = b"\x03\xf3\r\n"
SWF_NAME = "res/gui/flash/better_sense.swf"
ENTRY_NAME = "res/scripts/client/gui/mods/mod_better_sense.pyc"


def normalize_swf(data):
    """Remove the compiler's wall-clock ProductInfo timestamp, preserving tags."""
    signature = data[:3]
    if signature not in (b"FWS", b"CWS") or len(data) < 12:
        raise ValueError("Compiler output is not a supported SWF")
    body = bytearray(zlib.decompress(data[8:]) if signature == b"CWS" else data[8:])
    if len(body) + 8 != struct.unpack("<I", data[4:8])[0]:
        raise ValueError("Invalid SWF length")
    offset = (5 + 4 * (body[0] >> 3) + 7) // 8 + 4
    while offset + 2 <= len(body):
        header = struct.unpack_from("<H", body, offset)[0]
        offset += 2
        tag, length = header >> 6, header & 63
        if length == 63:
            length = struct.unpack_from("<I", body, offset)[0]
            offset += 4
        if offset + length > len(body):
            raise ValueError("Truncated SWF tag")
        if tag == 41 and length == 26:
            body[offset + 18:offset + 26] = b"\0" * 8
        offset += length
        if tag == 0:
            break
    return b"FWS" + data[3:8] + bytes(body)


def compiler_command(java, royale, libraries, entry, output, test=False):
    paths = [] if test else [libraries / name for name in LOCK["libraries"]]
    paths.append(libraries / "playerglobal.swc")
    for path in paths:
        expected = LOCK["playerglobal"]["sha256"] if path.name == "playerglobal.swc" else LOCK["libraries"][path.name]
        if not path.is_file() or digest(path) != expected:
            raise RuntimeError("Missing or unverified library: " + str(path) + "; run tools/bootstrap.py")
    command = [
        str(java), "-Xmx512m", "-Droyalelib=" + str(royale / "frameworks"),
        "-jar", str(royale / "js/lib/mxmlc.jar"),
        "-load-config=" + str(ROOT / "as3/build-config.xml"),
        "-external-library-path=" + ",".join(map(str, paths)),
    ]
    if test and entry.stem != "DecimalInputTests":
        command.append("-source-path+=" + str(ROOT / "tests/as3/stubs"))
    command.extend(["-output=" + str(output), str(entry)])
    return command


def package_entries(destination, entries):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".building")
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED) as archive:
            for name, data in sorted(entries.items()):
                path = Path(name)
                if path.is_absolute() or ".." in path.parts or "\\" in name:
                    raise ValueError("Unsafe package path: " + name)
                info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, data)
        validate_package(temporary)
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def validate_package(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        required = {"meta.xml", SWF_NAME, ENTRY_NAME, "res/scripts/client/gui/mods/better_sense/__init__.pyc"}
        if not required.issubset(names) or len(names) != len(set(names)):
            raise ValueError("Package misses required runtime entries or has duplicates")
        metadata = ET.fromstring(archive.read("meta.xml"))
        if metadata.tag != "mod" or not metadata.findtext("version") or "{{" in metadata.findtext("version"):
            raise ValueError("Invalid mod metadata")
        for info in archive.infolist():
            name = info.filename
            if info.compress_type != zipfile.ZIP_STORED:
                raise ValueError("Mod entries must be uncompressed")
            if name == "meta.xml":
                continue
            if name == SWF_NAME:
                normalize_swf(archive.read(name))
            elif name == ENTRY_NAME or (name.startswith("res/scripts/client/gui/mods/better_sense/") and name.endswith(".pyc")):
                payload = archive.read(name)
                if len(payload) <= 8 or payload[:4] != PYTHON_MAGIC:
                    raise ValueError("Expected CPython 2.7 bytecode: " + name)
            else:
                raise ValueError("Unexpected package entry: " + name)


def options(parser):
    parser.add_argument("--python2", type=Path, default=Path(os.environ.get("BETTER_SENSE_PYTHON2", str(CACHE / "toolchain/python2/bin/python2.7"))))
    parser.add_argument("--java", type=Path, default=Path(os.environ.get("BETTER_SENSE_JAVA", str(CACHE / "toolchain" / LOCK["java_linux_x86_64"]["directory"] / "bin/java"))))
    parser.add_argument("--royale-root", type=Path, default=Path(os.environ.get("BETTER_SENSE_ROYALE", str(CACHE / "toolchain" / LOCK["royale"]["directory"]))))
    parser.add_argument("--libs", type=Path, default=CACHE / "libs")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    options(parser)
    parser.add_argument("--version", default="1.0.1")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--as3-tests", action="store_true", help="compile the pure DecimalInput test SWF instead of the mod")
    parser.add_argument("--as3-test-entry", choices=("DecimalInputTests", "SensitivityInputTests"), help="compile an AS3 test entry point instead of the mod")
    args = parser.parse_args()
    test_entry = args.as3_test_entry or ("DecimalInputTests" if args.as3_tests else None)
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?", args.version):
        parser.error("version must be a semantic version")
    for key in ("python2", "java", "royale_root", "libs", "output"):
        setattr(args, key, getattr(args, key).resolve())
    build_root = ROOT / "build"
    build_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="better-sense-", dir=build_root) as temporary:
        staging = Path(temporary)
        entry = ROOT / ("tests/as3/entries/" + test_entry + ".as" if test_entry else "as3/src/better_sense/BetterSenseView.as")
        swf = staging / "better_sense.swf"
        subprocess.run(compiler_command(args.java, args.royale_root, args.libs, entry, swf, bool(test_entry)), cwd=ROOT, check=True)
        compiled_swf = normalize_swf(swf.read_bytes())
        if test_entry:
            destination = build_root / (test_entry + ".swf")
            destination.write_bytes(compiled_swf)
            print("Compiled:", destination)
            return
        entries = {SWF_NAME: compiled_swf, "meta.xml": (ROOT / "meta.xml").read_bytes().replace(b"{{VERSION}}", args.version.encode("ascii"))}
        jobs = []
        source_root = ROOT / "res/scripts/client/gui/mods"
        for source in sorted(source_root.rglob("*.py")):
            name = source.relative_to(ROOT).as_posix() + "c"
            destination = staging / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            jobs.append({"source": str(source), "output": str(destination), "filename": name[:-1], "version": args.version})
        manifest = staging / "python-jobs.json"
        manifest.write_text(json.dumps(jobs), encoding="utf-8")
        subprocess.run([str(args.python2), "-B", str(ROOT / "tools/compile_python2.py"), str(manifest)], check=True)
        entries.update({job["filename"] + "c": Path(job["output"]).read_bytes() for job in jobs})
        destination = args.output / ("dqs.better_sense_" + args.version + "_mt1.45.mtmod")
        package_entries(destination, entries)
        print("Built:", destination)
        print("SHA256:", hashlib.sha256(destination.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
