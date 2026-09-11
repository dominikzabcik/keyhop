#!/usr/bin/env python3
"""Copies the Field script from cloud/src/field.ts into Sources/Switchr/Dashboard/Field.swift.

The website and the app's dashboard run the same script. Edit cloud/src/field.ts, then run this;
FieldTests fails while the two copies differ.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
source = (ROOT / "cloud/src/field.ts").read_text()
start = source.index("/* field:start */")
end = source.index("/* field:end */") + len("/* field:end */")
script = source[start:end]
if '"""#' in script or "\\#" in script:
    raise SystemExit("The field script can't contain \"\"\"# or \\# inside a Swift raw string.")

(ROOT / "Sources/Switchr/Dashboard/Field.swift").write_text(
    "import Foundation\n\n"
    "/// The Field: Switchr's live dot-matrix backdrop, behind the dashboard. The website runs the same\n"
    "/// script from cloud/src/field.ts, and FieldTests keeps the two copies identical.\n"
    "enum Field {\n"
    '    static let script = #"""\n' + script + '\n"""#\n'
    "}\n"
)
print(f"Copied {len(script)} characters into Field.swift")
