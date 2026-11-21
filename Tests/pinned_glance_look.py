#!/usr/bin/env python3
"""How a pinned calendar and inbox look (Glance.swift), in a hidden probe:
the countdown and the unread dot in the squares' corners, and each card a
rest on its pin brings, as Arc's. Pictures to PATH (default a temp folder).

Build first (`./build.sh`), then `python3 Tests/pinned_glance_look.py [PATH]`.
Two local pages stand in for Google Calendar and Gmail (the bench's
standIn); the meeting and Gmail's notification are given through the
bench, never read from the Mac. Nothing here makes, shows or brings
forward a window.
"""
import sys
import tempfile
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("pinned-glance-look")
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="glance-look-"))
OUT.mkdir(parents=True, exist_ok=True)


class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        title = {"/mail": "Inbox (7) - you@example.com - Gmail", "/calendar": "Calendar"}.get(self.path, "Page")
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(f"<!doctype html><title>{title}</title><p>{self.path}".encode())

    def log_message(self, *a):
        pass


def main():
    t = sv.T()
    site = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    threading.Thread(target=site.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{site.server_port}"
    try:
        sv.setup(**{"sidebar": True, "sidebar.roomy": True, "look": "dark"})
        sv.launch()
        sv.cmd({"do": "glance", "standIn": {"/calendar": "calendar", "/mail": "mail"}})
        cal = sv.sp("open", url=base + "/calendar")["resultID"]
        mail = sv.sp("open", url=base + "/mail")["resultID"]
        other = sv.sp("open", url=base + "/other")["resultID"]
        time.sleep(2)
        for tab in (cal, mail, other):
            sv.cmd({"do": "pin", "id": tab})
        time.sleep(1)
        sv.cmd({"do": "glance", "id": cal, "meetings": [
            {"title": "Standup", "in": 30, "minutes": 15, "link": "https://meet.google.com/abc-defg-hij"},
            {"title": "Design review", "in": 120, "minutes": 45, "link": None},
            {"title": "1:1 with Sam", "in": 200, "minutes": 30, "link": None}]})
        sv.cmd({"do": "glance", "id": mail, "note": {"title": "Google", "body": "Security alert\nA new sign-in on Mac OS. We noticed a new sign-in to your account."}})
        time.sleep(1)
        sv.cmd({"do": "picture", "path": str(OUT / "pins.png"), "page": False})

        g = sv.cmd({"do": "glance", "id": mail})
        t.ok("Gmail's notification is the card's latest", g["latest"][:2] == ["Google", "Security alert"], g)
        sv.cmd({"do": "glance", "id": mail, "hover": True})
        time.sleep(1.2)
        t.ok("a rest on the inbox brings its card", sv.cmd({"do": "glance", "id": mail})["card"] is True)
        sv.cmd({"do": "picture", "path": str(OUT / "mail-card.png"), "page": False})

        sv.cmd({"do": "glance", "id": mail, "hover": False})
        sv.cmd({"do": "glance", "id": cal, "hover": True})
        time.sleep(1.2)
        t.ok("on to the calendar: its card", sv.cmd({"do": "glance", "id": cal})["card"] is True)
        sv.cmd({"do": "picture", "path": str(OUT / "calendar-card.png"), "page": False})

        sv.cmd({"do": "glance", "id": cal, "hover": False})
        time.sleep(1.2)
        # A row of the column under the pointer: its cross, drawn as ⌘T's
        # Switch to Tab arrow is.
        row = sv.sp("open", url=base + "/row")["resultID"]
        time.sleep(1)
        sv.cmd({"do": "hoverrow", "id": row})
        time.sleep(0.6)
        sv.cmd({"do": "picture", "path": str(OUT / "row-cross.png"), "page": False})
        sv.cmd({"do": "hoverrow", "id": row, "on": False})
        t.ok("off the pins: the card goes", sv.cmd({"do": "glance", "id": cal})["card"] is False)
        print(f"  pictures in {OUT}")
    finally:
        sv.finish()
        site.shutdown()
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
