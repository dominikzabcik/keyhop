#!/usr/bin/env python3
"""Copies the backdrop script from cloud/src/backdrop.ts into Sources/Switchr/Dashboard/Backdrop.swift.

The website and the app's dashboard run the same script. Edit cloud/src/backdrop.ts, then run this;
BackdropTests fails while the two copies differ.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
source = (ROOT / "cloud/src/backdrop.ts").read_text()
start = source.index("/* backdrop:start */")
end = source.index("/* backdrop:end */") + len("/* backdrop:end */")
script = source[start:end]
if '"""#' in script or "\\#" in script:
    raise SystemExit("The backdrop script can't contain \"\"\"# or \\# inside a Swift raw string.")

(ROOT / "Sources/Switchr/Dashboard/Backdrop.swift").write_text(
    "import Foundation\n\n"
    "/// Switchr's backdrop: illustrated scenes behind the dashboard. The website runs the same script\n"
    "/// from cloud/src/backdrop.ts, and BackdropTests keeps the two copies identical.\n"
    "enum Backdrop {\n"
    '    static let script = #"""\n' + script + '\n"""#\n'
    "}\n"
)
print(f"Copied {len(script)} characters into Backdrop.swift")
