#!/usr/bin/env python3
"""Go to … in a page's menu, as Chrome has it: an address chosen on a page
is offered by name, and opens in a new tab beside it. Words that aren't an
address, or an email address, offer nothing.

Build first (`./build.sh`), then `python3 Tests/go_to_selection.py`. A hidden
probe, a page of its own, the right-click as WebKit gets one (the bench's
linkmenu), nothing on your screen.
"""
import importlib.util
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("sv_go", HERE / "split_view.py")
sv = importlib.util.module_from_spec(spec); spec.loader.exec_module(sv)
sv.use("go-to-selection")
t = sv.T()


def choose(page, words, pick):
    """Select `words` on the page, right-click them, and pick `pick`."""
    js = f"""(() => {{
      document.body.innerHTML = '<p style="font:20px sans-serif;margin:40px">Mail ed@razegrowth.com or visit example.com and hello world</p>';
      const p = document.querySelector('p'), text = p.firstChild, at = text.data.indexOf({json.dumps(words)});
      const range = document.createRange(); range.setStart(text, at); range.setEnd(text, at + {len(words)});
      const s = getSelection(); s.removeAllRanges(); s.addRange(range);
      const r = range.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2];
    }})()"""
    x, y = sv.ev(page, js)
    return sv.cmd({"do": "linkmenu", "id": page, "x": x, "y": y, "pick": pick})


try:
    sv.setup()
    sv.launch()
    page = sv.page("words")
    before = len(sv.cmd({"do": "tabs"})["tabs"])
    r = choose(page, "example.com", "Go to example.com")
    t.ok("an address chosen: Go to example.com in the menu", "Go to example.com" in r.get("menu", []), r.get("menu"))
    t.ok("…above Search with", r["menu"].index("Go to example.com") < next((i for i, m in enumerate(r["menu"]) if m.startswith("Search with")), 99), r["menu"])
    time.sleep(1)
    tabs = sv.cmd({"do": "tabs"})["tabs"]
    t.ok("…and chosen, it opens in a new tab", len(tabs) == before + 1 and any("example.com" in x["url"] for x in tabs), [x["url"] for x in tabs])
    r = choose(page, "hello world", "nothing")
    t.ok("words that aren't an address: no Go to", not any(m.startswith("Go to") for m in r.get("menu", [])), r.get("menu"))
    r = choose(page, "ed@razegrowth.com", "nothing")
    t.ok("an email address: no Go to", not any(m.startswith("Go to") for m in r.get("menu", [])), r.get("menu"))
finally:
    t.done()
    sv.finish()
sys.exit(1 if t.failed else 0)
