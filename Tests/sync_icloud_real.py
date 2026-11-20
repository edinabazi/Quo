#!/usr/bin/env python3
"""Sync through the real iCloud: two hidden Quos on this Mac, in whichever
CloudKit environment build/Quo.app is signed for. A plain ./quo.sh, with
Quo.provisionprofile, is production; the first time, before the schema is
deployed, it has to be development. Each Quo is its own "Mac": they pass spaces both ways
through the iCloud account this Mac is signed into. Each turns sync off at
the end, which takes its records back out of iCloud.

For development, sign with the development profile Xcode made for
com.edinabazi.quo:

    SEARCH_SIGN_IDENTITY="Apple Development: …" SEARCH_PROFILE=<that profile> \
      SEARCH_ENTITLEMENTS=Quo.entitlements SEARCH_ICLOUD_ENV=Development ./quo.sh
    python3 Tests/sync_icloud_real.py

Test runs never reach the real iCloud unless SEARCH_REAL_CLOUD=1 says so,
which this sets. Pushes don't come here: CloudKit doesn't push to the device
that wrote, and both Quos are this Mac, so the half-minute pass carries it.
"""
import importlib.util, json, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent
def harness(name):
    spec = importlib.util.spec_from_file_location(f"sv_{name}", HERE / "split_view.py")
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    m.use(name); m.APP = str(HERE.parent / "build" / "Quo.app")
    m.SUPPORT = m.SUPPORT.replace("Search (", "Quo ("); m.SOCK = f"{m.SUPPORT}/bench.sock"
    return m
A, B = harness("icloud-real-a"), harness("icloud-real-b")
t = A.T()
def spaces(sv):
    try: return [s.get("name") for s in json.load(open(f"{sv.SUPPORT}/spaces.json"))]
    except Exception: return []
def sync(sv, action=None): return sv.cmd({"do": "sync", **({"action": action} if action else {})})
def wait(cond, within=90):
    end = time.time() + within
    while time.time() < end:
        if cond(): return True
        time.sleep(1)
    return cond()
stamp = time.strftime("%H%M%S")
try:
    for sv in (A, B):
        sv.setup()
        subprocess.run(["defaults", "write", sv.SUITE, "spaces", "-bool", "true"])
        subprocess.run(["defaults", "write", sv.SUITE, "sync.icloud", "-bool", "true"])
    A.launch(env={"SEARCH_REAL_CLOUD": "1"}); B.launch(env={"SEARCH_REAL_CLOUD": "1"})
    A.page("a"); B.page("b")
    ok = wait(lambda: sync(A)["problem"] == "" and sync(A)["synced"] > 0, 60)
    t.ok("A is on iCloud and has synced", ok, sync(A))
    t.ok("B is on iCloud and has synced", wait(lambda: sync(B)["problem"] == "" and sync(B)["synced"] > 0, 60), sync(B))
    t0 = time.time()
    A.cmd({"do": "space", "action": "new", "name": f"From A {stamp}"})
    t.ok("B gets A's new space through iCloud", wait(lambda: f"From A {stamp}" in spaces(B)), spaces(B))
    print(f"    (took {time.time()-t0:.0f}s)")
    t0 = time.time()
    B.cmd({"do": "space", "action": "new", "name": f"From B {stamp}"})
    t.ok("A gets B's new space through iCloud", wait(lambda: f"From B {stamp}" in spaces(A)), spaces(A))
    print(f"    (took {time.time()-t0:.0f}s)")
    t.ok("each names the other", wait(lambda: sync(A)["others"] != [] and sync(B)["others"] != [], 60), (sync(A), sync(B)))
finally:
    for sv in (A, B):
        try: sync(sv, "off"); time.sleep(4)
        except Exception as e: print("off:", e)
    t.done()
    for sv in (A, B):
        try: sv.finish()
        except Exception as e: print("finish:", e)
        subprocess.run(["defaults", "delete", sv.SUITE], capture_output=True)
sys.exit(1 if t.failed else 0)
