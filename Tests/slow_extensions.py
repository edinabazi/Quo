#!/usr/bin/env python3
"""Extensions that slow pages down (SlowExtensions.swift), in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/slow_extensions.py`. A copy
of build/Search.app under a bundle id of its own, started hidden, with two
extensions loaded from folders: one whose content script spends 12 ms on
every pointer move in a page, and one that looks like a tool (a button,
scripts everywhere, "Fonts Inspector"). Checked:

- the page's time for the busy one is counted and told to the browser;
- an extension's own removeEventListener still finds what it added;
- past two seconds, the card offers On click, and Run on Click sets it;
- a tool-like extension starts On click when installed;
- Don't Ask Again: no card however much more it costs.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("slow-extensions")
BUNDLE = "com.officecommun.search.slowext"
work = Path(tempfile.mkdtemp(prefix="search-slowext-"))

PAGE = b"<!doctype html><title>Moves</title><p id=p style='font:20px sans-serif;margin:40px'>a page</p>"


class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, *a):
        pass


BUSY = {
    "manifest.json": json.dumps({"manifest_version": 3, "name": "Pointer Watcher", "version": "1.0",
                                 "action": {"default_title": "Watch"},
                                 "content_scripts": [{"matches": ["<all_urls>"], "js": ["c.js"], "run_at": "document_start"}]}),
    "c.js": """
      document.addEventListener('mousemove', () => { const t = performance.now(); while (performance.now() - t < 12) {} }, true);
      // Added and taken away: never heard, however the shim wrapped it.
      const gone = () => { document.documentElement.dataset.removed = 'heard'; };
      document.addEventListener('pointermove', gone, { capture: true });
      document.removeEventListener('pointermove', gone, true);
      document.documentElement.dataset.watcher = 'here';
    """,
}

TOOL = {
    "manifest.json": json.dumps({"manifest_version": 3, "name": "Fonts Inspector", "version": "1.0",
                                 "description": "See the font of anything on a page",
                                 "action": {"default_title": "Inspect"},
                                 "content_scripts": [{"matches": ["<all_urls>"], "js": ["c.js"]}]}),
    "c.js": "void 0;",
}


def probe_copy():
    app = work / "Search.app"
    shutil.copytree(Path(sv.ROOT, "build", "Search.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def install(files, name, within=30):
    folder = work / name.replace(" ", "-")
    folder.mkdir()
    for file, body in files.items():
        (folder / file).write_text(body)
    sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
    end = time.time() + within
    while time.time() < end:
        ext = next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["name"] == name and x["loaded"]), None)
        if ext:
            return ext
        time.sleep(0.5)
    return None


def slow(action=None):
    return sv.cmd({"do": "slowext", **({"action": action} if action else {})})


def of(state, name):
    return next((x for x in state["extensions"] if x["name"] == name), {})


def moves(page, n):
    """`n` pointer moves in the page, as the page itself would get them."""
    sv.ev(page, f"for (let i = 0; i < {n}; i++) document.dispatchEvent(new MouseEvent('mousemove', {{ clientX: i % 300, clientY: 40 }})); 1")


def main():
    t = sv.T()
    site = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    threading.Thread(target=site.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{site.server_port}"
    sv.APP = probe_copy()
    try:
        sv.setup()
        sv.launch()
        slow("reset")
        busy = install(BUSY, "Pointer Watcher")
        t.ok("the busy extension loads", busy is not None)
        if not busy:
            return t
        t.ok("…on every site, as installed", of(slow(), "Pointer Watcher").get("access") == "all", slow())
        page = sv.sp("open", url=base + "/one")["resultID"]
        time.sleep(3)
        t.ok("its script is in the page", sv.ev(page, "document.documentElement.dataset.watcher") == "here")
        moves(page, 120)
        t.ok("its own removeEventListener still takes away what it added",
             sv.ev(page, "document.documentElement.dataset.removed || ''") == "", sv.ev(page, "document.documentElement.dataset.removed"))
        # The page goes: what it measured is told.
        sv.cmd({"do": "eval", "id": page, "js": f"location.href = {json.dumps(base + '/two')}; 1"})
        time.sleep(3)
        state = slow()
        cost = of(state, "Pointer Watcher").get("cost", 0)
        t.ok("the pages' time for it is counted", cost >= 1200, cost)
        t.ok("…under two seconds, no card yet", state["suggestion"] is None, state)
        moves(page, 120)
        sv.cmd({"do": "eval", "id": page, "js": f"location.href = {json.dumps(base + '/three')}; 1"})
        time.sleep(3)
        state = slow()
        t.ok("past two seconds, the card offers On click", (state["suggestion"] or {}).get("name") == "Pointer Watcher", state)
        state = slow("accept")
        t.ok("Run on Click: it runs on click from now on", of(state, "Pointer Watcher").get("access") == "click" and state["suggestion"] is None, state)

        tool = install(TOOL, "Fonts Inspector")
        t.ok("a tool-like extension starts On click", tool is not None and of(slow(), "Fonts Inspector").get("access") == "click", slow())

        # Don't Ask Again: the busy one back on every site, costing again.
        slow("reset")
        sv.cmd({"do": "ext-sites", "id": busy["id"], "mode": "all"})
        time.sleep(1)
        state = slow("never")
        page2 = sv.sp("open", url=base + "/four")["resultID"]
        time.sleep(3)
        moves(page2, 250)
        sv.cmd({"do": "eval", "id": page2, "js": f"location.href = {json.dumps(base + '/five')}; 1"})
        time.sleep(3)
        state = slow()
        t.ok("Don't Ask Again: no card, however much it costs",
             state["suggestion"] is None and of(state, "Pointer Watcher").get("cost", 0) >= 2000, state)
    finally:
        sv.finish()
        site.shutdown()
        for kind in ("WebKit", "Caches", "HTTPStorages"):
            shutil.rmtree(Path.home() / "Library" / kind / BUNDLE, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
