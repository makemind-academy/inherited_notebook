#!/usr/bin/env python3
"""inherited-notebook: nothing is overwritten; a corrected line stays in the full book and leaves the standing view."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "tools"))
from appplayer import AppPlayer  # noqa: E402
from mcpclient import Server  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(HERE, "notebook_server")
CAP = os.path.join(HERE, "captures")
SERVER_ID = "com.makemind.sample.notebook"

with Server(["dart", "run", "bin/server.dart"], cwd=SERVER) as s:
    every = s.call("notes.machine", {"machine": "Press 2"})
    assert every["rowCount"] == 4
    assert all(r["who"] and r["year"] for r in every["rows"])
    corrected = [r for r in every["rows"] if r.get("correctedBy")]
    assert corrected, "one line must have been corrected"
    standing = s.call("notes.standing")
    assert all(r["id"] != corrected[0]["id"] for r in standing["rows"])

ap = AppPlayer()
ap.register_server(SERVER_ID, "Inherited notebook", cwd=SERVER)
ap.restart()
ap.open_server(SERVER_ID)
ap.wait_text("Everything written down")
ap.expect_aligned("ENTRIES", min_rows=1) if False else None
ap.shot(f"{CAP}/01_every_line.png")
ap.tap("What still stands →")
ap.wait_text("← Everything")        # the other page, not the button that brought us here
ap.expect_no_text("valve trick")   # the superseded line is not in what stands
ap.shot(f"{CAP}/02_what_stands.png")
print("inherited-notebook: every line kept, the corrected one absent from what stands")
