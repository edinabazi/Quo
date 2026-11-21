#!/usr/bin/env python3
"""A pinned calendar's countdown and Join, and a pinned inbox's unread
(Glance.swift), in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/pinned_glance.py`. Two local
pages stand in for Google Calendar and Gmail (the bench's standIn), pinned;
meetings and mail are given through the bench, never read from the Mac.
Checked: the countdown within the hour and "now" while one is on, nothing
past the hour; the Join row only for a meeting with a call five minutes out
or on, and only with the calendar pinned; the inbox's unread from its title,
and its latest unread as given.
"""
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("pinned-glance")


class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        title = "Inbox (7) - you@example.com - Gmail" if self.path.startswith("/mail") else "Calendar"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        rows = ""
        if self.path.startswith("/mail"):
            # Two unread rows and a read one, as Gmail draws its list.
            rows = ("<table>"
                    "<tr class='zA zE' id=':1a'><td class='yX'><span email='ana@example.com' name='Ana'>Ana</span></td>"
                    "<td><span class='bog'>Lunch tomorrow?</span><span class='y2'> - Are you free at noon</span></td>"
                    "<td class='xW'><span title='Fri'>10:02</span></td></tr>"
                    "<tr class='zA zE' id=':1b'><td class='yW'><span email='ben@example.com' name='Ben'>Ben</span></td>"
                    "<td><span class='bog'>Invoice</span><span class='y2'> - Attached</span></td>"
                    "<td class='xW'><span>9:40</span></td></tr>"
                    "<tr class='zA yO' id=':1c'><td class='yX'><span email='c@example.com' name='Cy'>Cy</span></td>"
                    "<td><span class='bog'>Read already</span></td></tr></table>"
                    "<script>document.addEventListener('click', e => { const r = e.target.closest('tr'); if (r) document.title = 'opened ' + r.id; }, true)</script>")
        self.wfile.write(f"<!doctype html><title>{title}</title><p>{self.path}{rows}".encode())

    def log_message(self, *a):
        pass


def main():
    t = sv.T()
    site = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    threading.Thread(target=site.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{site.server_port}"
    try:
        sv.setup(sidebar=True)
        sv.launch()
        sv.cmd({"do": "glance", "standIn": {"/calendar": "calendar", "/mail": "mail"}})
        cal = sv.sp("open", url=base + "/calendar")["resultID"]
        mail = sv.sp("open", url=base + "/mail")["resultID"]
        time.sleep(2)
        sv.cmd({"do": "pin", "id": cal})
        sv.cmd({"do": "pin", "id": mail})
        time.sleep(1)

        g = sv.cmd({"do": "glance", "id": cal, "meetings": [{"title": "Standup", "in": 30, "minutes": 15, "link": "https://meet.google.com/abc-defg-hij"}]})
        t.ok("a pinned calendar is one", g["kind"] == "calendar", g)
        t.ok("thirty minutes out: the pin counts down", g["countdown"] == "30m", g)
        t.ok("…and no Join yet", g["joinable"] == "" and g["row"] is False, g)

        g = sv.cmd({"do": "glance", "meetings": [{"title": "Standup", "in": 3, "minutes": 15, "link": "https://meet.google.com/abc-defg-hij"}]})
        t.ok("three minutes out: Join, over the foot", g["joinable"] == "Standup" and g["row"] is True and g["countdown"] == "3m", g)

        g = sv.cmd({"do": "glance", "meetings": [{"title": "Review", "in": -5, "minutes": 30, "link": "https://zoom.us/j/123"}]})
        t.ok("on now: 'now', Join still there", g["countdown"] == "now" and g["joinable"] == "Review", g)

        g = sv.cmd({"do": "glance", "meetings": [{"title": "Lunch", "in": 4, "minutes": 60, "link": None}]})
        t.ok("no call in it: no Join", g["joinable"] == "" and g["countdown"] == "4m", g)

        g = sv.cmd({"do": "glance", "meetings": [{"title": "Later", "in": 90, "minutes": 30, "link": None}]})
        t.ok("past the hour: nothing on the pin", g["countdown"] == "" and g["next"] == "Later", g)

        g = sv.cmd({"do": "glance", "id": mail, "mail": [{"from": "Ana", "subject": "Hello", "summary": "Hi there"},
                                                         {"from": "Ben", "subject": "Lunch?", "summary": ""}]})
        t.ok("a pinned inbox is one", g["kind"] == "mail", g)
        t.ok("its unread, from its title", g["unread"] == 7, g)
        t.ok("its latest unread, as given", g["mails"] == 2, g)

        # No feed on this server: the unread rows of the inbox on the page.
        g = sv.cmd({"do": "glance", "id": mail, "fetch": True})
        t.ok("no feed: the page's unread rows, read ones left out", g["mails"] == 2 and g["from"] == ["Ana", "Ben"], g)
        t.ok("…their subjects, and the rows to open", g["subjects"] == ["Lunch tomorrow?", "Invoice"] and g["rows"] == [":1a", ":1b"], g)
        sv.cmd({"do": "glance", "id": mail, "open": ":1b"})
        time.sleep(0.6)
        title = sv.ev(mail, "document.title")
        t.ok("a row taken from the preview opens it in the page", title == "opened :1b", title)

        # Unpinned: the Join row goes with the calendar.
        sv.cmd({"do": "glance", "meetings": [{"title": "Standup", "in": 2, "minutes": 15, "link": "https://meet.google.com/x"}]})
        sv.cmd({"do": "pin", "id": cal, "off": True})
        time.sleep(1)
        g = sv.cmd({"do": "glance"})
        t.ok("no calendar pinned: no Join row", g["row"] is False, g)
    finally:
        sv.finish()
        site.shutdown()
    return t


if __name__ == "__main__":
    t = main()
    t.done()
    sys.exit(1 if t.failed else 0)
