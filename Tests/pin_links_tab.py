#!/usr/bin/env python3
"""Pins keep their site, with links to other sites opening in a new tab
(Settings › Spaces & Pins › Links to other sites open in: New tab, the
default), as Dia does. Tests/pin_peek.py has the Peek choice.

Build first (`./build.sh`), then `python3 Tests/pin_links_tab.py`. It uses
the split suite's harness, started hidden, everything removed afterwards.
127.0.0.1 and localhost serve the same pages and stand for two sites.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("pin-links-tab")
t = sv.T()
OTHER = sv.BASE.replace("127.0.0.1", "localhost")


def follow(id, href):
    sv.ev(id, f"var a = document.createElement('a'); a.href = '{href}'; document.body.appendChild(a); a.click(); true")
    time.sleep(1.2)


def tap(id, href, blank=False):
    target = "a.target = '_blank';" if blank else ""
    sv.ev(id, f"document.getElementById('go')?.remove(); var a = document.createElement('a'); a.id = 'go'; a.href = '{href}'; {target} a.textContent = 'go'; a.style = 'position:fixed;left:0;top:0;width:200px;height:120px;display:block;font-size:40px'; document.body.appendChild(a); true")
    sv.cmd({"do": "tap", "id": id, "selector": "#go"})
    time.sleep(1.2)


def peek(): return sv.cmd({"do": "probe"})["peek"]
def tab_at(st, end): return next((x for x in st["tabs"] if x["url"].endswith(end)), None)


try:
    sv.setup(sidebar=True, **{"pins.peek": True}); sv.launch()
    a = sv.page("home"); sv.cmd({"do": "pin", "id": a}); sv.sp("select", id=a); time.sleep(0.5)

    follow(a, f"{OTHER}/out")
    st = sv.sp("state")
    out = tab_at(st, "/out")
    t.ok("a link from a pin to another site opens in a new tab", out is not None, [x["url"] for x in st["tabs"]])
    t.ok("…not a peek", peek() == "", peek())
    t.ok("…which is the one in front", out is not None and out.get("staysReason") == "on screen", out)
    t.ok("…and the pin stays on its page", sv.url(st, a).endswith("/home"), sv.url(st, a))

    sv.sp("select", id=a); time.sleep(0.5)
    tap(a, f"{OTHER}/blank", blank=True)
    st = sv.sp("state")
    t.ok("a target=_blank link from a pin opens in a tab too", tab_at(st, "/blank") is not None and peek() == "",
         ([x["url"] for x in st["tabs"]], peek()))
    t.ok("…the pin still on its page", sv.url(st, a).endswith("/home"), sv.url(st, a))

    sv.sp("select", id=a); time.sleep(0.5)
    follow(a, f"{sv.BASE}/inner")
    t.ok("a link within the site goes in the pin", sv.url(sv.sp("state"), a).endswith("/inner"), sv.url(sv.sp("state"), a))

    # Google's way: the page sends itself after the link by script.
    before = len(sv.sp("state")["tabs"])
    sv.ev(a, f"var a = document.createElement('a'); a.href = '{OTHER}/again'; a.onclick = function () {{ setTimeout(function () {{ location.href = a.href }}, 300) }}; document.body.appendChild(a); a.click(); true")
    time.sleep(1.6)
    st = sv.sp("state")
    t.ok("the page sending the pin after it by script is turned away",
         tab_at(st, "/again") is not None and sv.url(st, a).endswith("/inner"), (sv.url(st, a), [x["url"] for x in st["tabs"]]))
    t.ok("…with one tab for it, not two", len(st["tabs"]) == before + 1, (before, len(st["tabs"])))

    b = sv.page("loose"); sv.sp("select", id=b); time.sleep(0.5)
    follow(b, f"{OTHER}/away")
    t.ok("a tab that isn't a pin goes as before", sv.url(sv.sp("state"), b).endswith("/away"), sv.url(sv.sp("state"), b))
except Exception:
    import traceback; traceback.print_exc(); t.failed += 1
finally:
    sv.finish()
    t.done()
    sys.exit(1 if t.failed else 0)
