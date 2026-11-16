import os
from pathlib import Path
import plistlib
import sqlite3
import sys
import time


if os.geteuid() != 0 or os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("Permission setup is restricted to the ephemeral GitHub macOS runner.")
bundle = Path(sys.argv[1]).resolve()
requirement = Path(sys.argv[2]).read_bytes()
with (bundle / "Contents/Info.plist").open("rb") as file:
    info = plistlib.load(file)
identifier = info["CFBundleIdentifier"]
if identifier != "org.icescreen.tests.source-focus" or bundle.name != "Checks.app":
    raise SystemExit("Only the signed source-focus test application can receive test permissions.")
database = Path("/Library/Application Support/com.apple.TCC/TCC.db")
with sqlite3.connect(f"file:{database}?mode=rw", uri=True) as connection:
    for service in ("kTCCServiceAccessibility", "kTCCServiceScreenCapture"):
        connection.execute(
            "INSERT OR REPLACE INTO access "
            "(service,client,client_type,auth_value,auth_reason,auth_version,csreq,"
            "indirect_object_identifier_type,indirect_object_identifier,flags,last_modified) "
            "VALUES (?,?,0,2,4,1,?,0,'UNUSED',0,?)",
            (service, identifier, requirement, int(time.time())),
        )
    rows = connection.execute(
        "SELECT service,auth_value FROM access WHERE client=? AND client_type=0", (identifier,)
    ).fetchall()
    if dict(rows) != {"kTCCServiceAccessibility": 2, "kTCCServiceScreenCapture": 2}:
        raise RuntimeError("The native test permission records were not installed correctly.")
print("Configured real Accessibility and Screen Recording permissions for the signed source-focus test app.")
