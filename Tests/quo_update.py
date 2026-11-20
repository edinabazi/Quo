#!/usr/bin/env python3
"""Quo updating itself from a feed of its own, end to end: an older Quo,
signed with the Developer ID, started hidden from a folder of its own, reads
a newer Quo's signed feed from a local server, fetches the ZIP, checks it and
swaps it in. The same code reads Quo's GitHub releases; only the address
differs (SEARCH_FEED, which a test run alone may set).

    python3 Tests/quo_update.py

Builds both Quos itself (a few minutes: the newer one with its disk image),
under build/ as ./quo.sh would, and needs the Developer ID certificate in the
keychain. Nothing in /Applications is touched. What is checked:

- the feed is signed as com.edinabazi.quo.appcast by Quo's team;
- the older Quo finds the newer one and swaps it in where it is;
- the bundle there is then the newer build, signed by the same team;
- a feed signed under another identifier is refused, the same one signed
  as Quo's is offered.
"""
import functools
import http.server
import importlib.util
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TEAM = "8B6VFDJHA2"
OLD, NEW = "202601010000", "202601020000"

served = Path(tempfile.mkdtemp(prefix="quo-feed-"))
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(served))
handler.log_message = lambda *a: None
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
FEED = f"http://127.0.0.1:{srv.server_port}"

QUO = {
    "SEARCH_NAME": "Quo", "SEARCH_BUNDLE_ID": "com.edinabazi.quo", "SEARCH_ICON": "Icon/Quo.icon",
    "SEARCH_FEED_URL": "https://github.com/edinabazi/Quo/releases/latest/download/appcast.json",
    "SEARCH_FEED_TEAM": TEAM, "SEARCH_NOTES": "QUO_NOTES.md",
}


def build(version, number, step):
    env = {**os.environ, **QUO, "SEARCH_VERSION": version, "SEARCH_BUILD": number, "SEARCH_DOWNLOAD_URL": FEED}
    subprocess.run(["./build.sh", "release", step], cwd=ROOT, env=env, check=True, stdout=subprocess.DEVNULL)


def info(app):
    return plistlib.load(open(f"{app}/Contents/Info.plist", "rb"))


def verifies(path, identifier):
    req = (f'anchor apple generic and identifier "{identifier}" and certificate 1[field.1.2.840.113635.100.6.2.6] '
           f'and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "{TEAM}"')
    return subprocess.run(["codesign", "--verify", f"-R={req}", str(path)], capture_output=True).returncode == 0


spec = importlib.util.spec_from_file_location("sv_quo_update", HERE / "split_view.py")
sv = importlib.util.module_from_spec(spec); spec.loader.exec_module(sv)
sv.use("quo-update")
sv.SUPPORT = sv.SUPPORT.replace("Search (", "Quo (")
sv.SOCK = f"{sv.SUPPORT}/bench.sock"
t = sv.T()
place = Path(tempfile.mkdtemp(prefix="quo-installed-"))
app = place / "Quo.app"

try:
    print("building the older Quo…")
    build("0.0.1", OLD, "app")
    shutil.copytree(ROOT / "build/Quo.app", app, symlinks=True)
    print("building the newer Quo and its feed…")
    build("0.0.2", NEW, "dmg")
    for name in ["Quo.zip", "Quo.dmg", "appcast.json", "appcast.json.zip"]:
        shutil.copy(ROOT / "build" / name, served / name)

    check = Path(tempfile.mkdtemp())
    subprocess.run(["ditto", "-x", "-k", str(served / "appcast.json.zip"), str(check)], check=True)
    t.ok("the feed is signed as Quo's, by Quo's team", verifies(check / "appcast.json", "com.edinabazi.quo.appcast"))
    t.ok("the older Quo names its own feed", info(app).get("SearchFeed", "").startswith("https://github.com/edinabazi/Quo/"), info(app).get("SearchFeed"))

    sv.APP = str(app)
    sv.setup()
    sv.launch(env={"SEARCH_FEED": f"{FEED}/appcast.json"})
    stage = ""
    for _ in range(60):
        stage = sv.cmd({"do": "update"})["stage"]
        if stage.startswith("ready"): break
        time.sleep(1)
    t.ok("the older Quo finds the newer one and swaps it in", stage.startswith("ready"), stage)
    t.ok("…the bundle where it was is now the newer build", info(app)["CFBundleVersion"] == NEW, info(app)["CFBundleVersion"])
    t.ok("…signed by the same team", verifies(app, "com.edinabazi.quo"))
    sv.quit()

    # A feed naming a build newer still: signed as Quo's it is taken up,
    # signed under any other identifier by the same team it is no feed.
    shutil.rmtree(app); shutil.copytree(ROOT / "build/Quo.app", app, symlinks=True)
    identity = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
    identity = next(l.split('"')[1] for l in identity.splitlines() if "Developer ID Application" in l)
    later = (served / "appcast.json").read_text().replace(f'"build": {NEW}', '"build": 209901010000')

    def serve_feed(identifier):
        folder = Path(tempfile.mkdtemp())
        (folder / "appcast.json").write_text(later)
        subprocess.run(["codesign", "--force", "--sign", identity, "--identifier", identifier, str(folder / "appcast.json")], check=True, capture_output=True)
        (served / "appcast.json.zip").unlink(missing_ok=True)
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", str(folder / "appcast.json"), str(served / "appcast.json.zip")], check=True)

    def stage_after_check():
        sv.setup()
        subprocess.run(["defaults", "write", sv.SUITE, "update.install", "-bool", "false"])
        sv.launch(env={"SEARCH_FEED": f"{FEED}/appcast.json"})
        sv.cmd({"do": "update", "action": "check"})
        time.sleep(4)
        found = sv.cmd({"do": "update"})["stage"]
        sv.quit()
        return found

    serve_feed("com.officecommun.search.appcast")
    found = stage_after_check()
    t.ok("a feed signed under another identifier is refused", found == "none", found)
    serve_feed("com.edinabazi.quo.appcast")
    found = stage_after_check()
    t.ok("…the same feed signed as Quo's is offered", found.startswith("waiting"), found)
finally:
    t.done()
    try: sv.finish()
    except Exception as e: print("finish:", e)
    subprocess.run(["defaults", "delete", sv.SUITE], capture_output=True)
    srv.shutdown()
    for folder in (served, place): shutil.rmtree(folder, ignore_errors=True)
sys.exit(1 if t.failed else 0)
