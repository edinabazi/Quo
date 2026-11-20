"""Another browser's profiles come over each into one of their own, and a
browser macOS keeps from this app is said to be here, not missing.

Build first (`./build.sh`), then `python3 Tests/bring_profiles.py`. A made-up
Chrome with three profiles — its first, "Work", and one with nothing in it —
is brought in through the same call the sheet makes with Profiles on: the
first into this window's profile, Work into a new profile of that name, the
empty one nowhere. Brought in again, nothing doubles and no second Work is
made. A made-up Dia whose folder can't be listed is reported as refused.
Nothing here reads a real browser's data.
"""
import json
import os
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("bring-profiles")

PROFILES = {
    # folder: (name, bookmarks, places)
    "Default": ("Ed", [("Home", "https://home.example.com/")], ["https://home.example.com/", "https://news.example.com/"]),
    "Profile 1": ("Work", [("Tracker", "https://tracker.example.com/"), ("Docs", "https://docs.example.com/")],
                  ["https://tracker.example.com/"]),
    "Profile 2": ("Empty", [], []),
}


def chrome():
    root = Path(f"{sv.SUPPORT}/Import/Google/Chrome")
    for folder, (name, marks, places) in PROFILES.items():
        profile = root / folder
        profile.mkdir(parents=True, exist_ok=True)
        if marks:
            children = [{"type": "url", "name": t, "url": u} for t, u in marks]
            (profile / "Bookmarks").write_text(json.dumps({"roots": {"bookmark_bar": {"children": children}}}))
        db = sqlite3.connect(profile / "History")
        db.execute("CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER,"
                   " typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER)")
        for n, url in enumerate(places):
            db.execute("INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden)"
                       " VALUES (?, ?, 3, 0, ?, 0)", (url, url, 13_300_000_000_000_000 + n))
        db.commit(); db.close()
    cache = {folder: {"name": name} for folder, (name, _, _) in PROFILES.items()}
    (root / "Local State").write_text(json.dumps({"profile": {"info_cache": cache, "last_used": "Profile 1"}}))


def dia_refused():
    """Dia's folder there, and unreadable: as macOS leaves Chrome's on a Mac
    that hasn't allowed it."""
    root = Path(f"{sv.SUPPORT}/Import/Dia/User Data")
    (root / "Default").mkdir(parents=True, exist_ok=True)
    (root / "Default" / "Bookmarks").write_text("{}")
    os.chmod(root, 0)
    return root


def main():
    t = sv.T()
    locked = None
    try:
        sv.setup()
        chrome()
        locked = dia_refused()
        sv.launch()

        seen = sv.cmd({"do": "import-preview"})
        names = [b["name"] for b in seen["browsers"]]
        t.ok("Chrome, the only readable browser, is found", names == ["Chrome"], names)
        chrome_seen = next(b for b in seen["browsers"] if b["name"] == "Chrome")
        t.ok("with its three profiles by name", [p["name"] for p in chrome_seen["profiles"]] == ["Ed", "Work", "Empty"],
             chrome_seen["profiles"])
        refused = [r["name"] for r in seen.get("refused", [])]
        t.ok("Dia, unreadable, is said to be here", refused == ["Dia"], seen.get("refused"))
        t.ok("…as kept from this app, not missing",
             any("until you allow" in r["message"] for r in seen.get("refused", [])), seen.get("refused"))

        what = ["profiles", "profile-bookmarks", "profile-history"]
        out = sv.cmd({"do": "import", "from": "Chrome", "what": what})
        taken = {p["name"]: p for p in out.get("profiles-taken", [])}
        t.ok("two profiles had something to bring", sorted(taken) == ["Ed", "Work"], out.get("profiles-taken"))
        ed, work = taken.get("Ed", {}), taken.get("Work", {})
        t.ok("Chrome's first comes into this window's profile", ed.get("here") is True and not ed.get("made"), ed)
        t.ok("Work into a new profile of its name", work.get("into") == "Work" and work.get("made") is True, work)
        t.ok("each with its own bookmarks", ed.get("bookmarks") == 1 and work.get("bookmarks") == 2, taken)
        t.ok("and its own history", ed.get("places") == 2 and work.get("places") == 1, taken)
        t.ok("Work's bookmarks are in Work, not here", work.get("intoBookmarks") == 2, work)
        t.ok("the empty one makes no profile", out.get("profilesHere") == ["Personal", "Work"], out.get("profilesHere"))
        record = out.get("record") or {}
        t.ok("the record counts all of them", record.get("bookmarks") == 3 and record.get("places") == 3, record)

        again = sv.cmd({"do": "import", "from": "Chrome", "what": what})
        taken = {p["name"]: p for p in again.get("profiles-taken", [])}
        t.ok("brought again, Work is found by name, not made twice",
             taken.get("Work", {}).get("made") is False and again.get("profilesHere") == ["Personal", "Work"],
             again.get("profilesHere"))
        t.ok("and no bookmark doubles", all(p["bookmarks"] == 0 for p in taken.values()), taken)

        sv.quit(); time.sleep(1)
        kept = json.load(open(f"{sv.SUPPORT}/profiles.json"))
        work_id = next((p["id"] for p in kept if p["name"] == "Work"), None)
        t.ok("Work is kept as a profile", work_id is not None, kept)
        marks = Path(f"{sv.SUPPORT}/bookmarks-{work_id}.json")
        t.ok("with its bookmarks in its own file", marks.exists() and "tracker.example.com" in marks.read_text(),
             marks)
    finally:
        if locked: os.chmod(locked, 0o700)
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
