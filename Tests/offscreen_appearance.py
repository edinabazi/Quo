#!/usr/bin/env python3
"""An extension's offscreen document follows the app's light or dark look
while it is open, checked in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/offscreen_appearance.py PATH`,
PATH an unpacked extension whose offscreen document (reason MATCH_MEDIA)
writes `darkScheme` to chrome.storage.local whenever
`(prefers-color-scheme: dark)` changes — Glance's build/glance does.
Started hidden in a world of its own, driven through ./bench's socket, and
removed afterwards. Nothing here makes, shows or brings forward a window.
"""
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("bld-offapp")
EXT = str(Path(sys.argv[1]).resolve())


def write(look): subprocess.run(["defaults", "write", sv.SUITE, "look", "-string", look])


def dark(tab):
    # The bench's eval waits for no promise: start the read, then collect it.
    sv.ev(tab, "window.__d = undefined; chrome.storage.local.get('darkScheme').then(v => { window.__d = String(v.darkScheme) }); 0")
    time.sleep(0.2)
    return sv.ev(tab, "String(window.__d)")


def becomes(tab, want, within=8):
    end = time.time() + within
    while time.time() < end:
        got = dark(tab)
        if got == want: return got
        time.sleep(0.4)
    return dark(tab)


def main():
    t = sv.T()
    sv.setup()
    write("light")
    sv.launch()
    try:
        added = sv.cmd({"do": "ext-folder", "path": EXT, "yes": True})
        exts = sv.cmd({"do": "extensions"}).get("extensions", [])
        ext = next((e for e in exts if e.get("path") == EXT or e.get("name") == "Glance"), None)
        t.ok("the extension is installed", ext is not None, (added, exts))
        if not ext: return t
        time.sleep(4)
        # A page that reports nothing itself: only the offscreen document speaks.
        tab = sv.cmd({"do": "ext-page", "id": ext["id"], "path": "icon/16.png"})["id"]
        time.sleep(1)
        t.ok("light at first", becomes(tab, "false") == "false", dark(tab))
        write("dark")
        t.ok("the offscreen document sees the app go dark", becomes(tab, "true") == "true", dark(tab))
        write("light")
        t.ok("and light again", becomes(tab, "false") == "false", dark(tab))
    finally:
        sv.finish()
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
