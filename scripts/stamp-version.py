#!/usr/bin/env python3
"""Stamps a build's version into VERSION and Sources/Keyhop/Core/Version.swift.

    python3 scripts/stamp-version.py 2.0.0-beta.4

Release builds of a beta use it: the version comes from the tag, not from the files.
"""
import pathlib
import re
import sys

version = sys.argv[1].removeprefix("v") if len(sys.argv) > 1 else ""
if not re.fullmatch(r"\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?", version):
    sys.exit(f"Not a version: {version!r}")
root = pathlib.Path(__file__).resolve().parent.parent
(root / "VERSION").write_text(version + "\n")
swift = root / "Sources/Keyhop/Core/Version.swift"
text = swift.read_text()
stamped, count = re.subn(r'static let number = "[^"]*"', f'static let number = "{version}"', text)
if count != 1:
    sys.exit("Version.swift has no number to stamp")
swift.write_text(stamped)
print(f"Stamped {version}")
