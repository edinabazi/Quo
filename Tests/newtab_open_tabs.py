#!/usr/bin/env python3
"""⌘T's floating field as Arc's (Browser.launchOffers, guess, submit).

Build first (`./build.sh`), then `python3 Tests/newtab_open_tabs.py`. Checked:
before typing it lists the open tabs to switch to; typing puts the matching
open tab first and offers commands; ↓ and Return switches; Return on an
open page's address goes to its tab, not a second copy; words still search
in a new tab.
"""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv
sv.use("cmdt")
t = sv.T()
try:
    sv.setup(**{"sidebar": True, "sidebar.addressBar": True, "newtab.floating": True, "sidebar.roomy": True})
    sv.launch()
    for n in ("alpha", "bravo", "charlie"): sv.page(n)
    time.sleep(1)
    sv.cmd({"do": "keyeq", "chars": "t", "code": 17})
    time.sleep(0.8)
    st = sv.cmd({"do": "suggest"})
    t.ok("before typing: open tabs to switch to", [o[1] for o in st["offers"]][:2] == ["open", "open"], st["offers"])
    sv.cmd({"do": "field", "text": "bra"})
    time.sleep(0.8)
    st = sv.cmd({"do": "suggest"})
    t.ok("typed: the matching open tab first", st["offers"] and st["offers"][0][1] == "open" and "bravo" in st["offers"][0][2], st["offers"])
    sv.cmd({"do": "field", "text": "downl"})
    time.sleep(0.8)
    st = sv.cmd({"do": "suggest"})
    t.ok("typed: commands offered", any(o[1] == "command" for o in st["offers"]), st["offers"])
    sv.cmd({"do": "field", "text": "bra"})
    time.sleep(0.6)
    sv.cmd({"do": "suggest", "action": "walk", "step": 1})
    time.sleep(0.5)
    st = sv.cmd({"do": "suggest", "action": "go"})
    t.ok("↓ then Return switches to the open tab", "bravo" in st["address"], st["address"])
    # Return on an open page's address: that tab.
    sv.cmd({"do": "keyeq", "chars": "t", "code": 17}); time.sleep(0.6)
    sv.cmd({"do": "field", "text": sv.BASE.replace("http://", "") + "/alpha"}); time.sleep(0.6)
    before = len(sv.cmd({"do": "tabs"})["tabs"])
    st = sv.cmd({"do": "suggest", "action": "go"})
    t.ok("Return on an open page's address: switches, no second copy",
         "alpha" in st["address"] and len(sv.cmd({"do": "tabs"})["tabs"]) == before, (st["address"], before))
    # A search still opens a new tab, as before.
    sv.cmd({"do": "keyeq", "chars": "t", "code": 17}); time.sleep(0.6)
    sv.cmd({"do": "field", "text": "zzz qqq"}); time.sleep(0.6)
    st = sv.cmd({"do": "suggest", "action": "go"})
    t.ok("words still search in a new tab", len(sv.cmd({"do": "tabs"})["tabs"]) == before + 1, len(sv.cmd({"do": "tabs"})["tabs"]))
finally:
    sv.finish()
t.done()
sys.exit(1 if t.failed else 0)
