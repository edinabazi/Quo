#!/usr/bin/env python3
"""chrome.notifications in an extension behaves as in Chrome
(ExtensionNotifications.swift), in a hidden probe.

Build first (`./build.sh debug`), then `python3 Tests/extension_notifications.py`.
It runs a copy of build/Search.app under a bundle id of its own, hidden, in
a world of its own with split_view.py's harness; the copy, its WebKit
folders and the world are removed afterwards.

A test run posts nothing to the Mac: it keeps what it would have posted, and
the bench answers a notification as a click on it would. What is checked,
with an extension that makes notifications and listens to what is done with
them:

- its listening opens one port to the browser;
- a notification is posted with its buttons (two at most) as the Mac
  notification's actions, its context line as the subtitle, and a category
  named for the extension and its buttons, the same for the same buttons;
- a click, a button and a dismissal are told as onClicked, onButtonClicked
  (with the button's number) and onClosed (by the user), once each, and the
  browser keeps nothing once the background has heard;
- with no listener left the port closes, and a click then waits: told as
  the extension listens again, as a worker woken by the click would be;
- getAll, update and clear work on what was posted.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("extension-notifications")
BUNDLE = "com.officecommun.search.notifyevents"
work = Path(tempfile.mkdtemp(prefix="search-notifyevents-"))

FILES = {
    "manifest.json": json.dumps({
        "manifest_version": 3, "name": "Notify Events", "version": "1.0",
        "permissions": ["notifications", "storage"],
        "background": {"service_worker": "background.js"},
        "externally_connectable": {"matches": ["http://127.0.0.1/*"]},
    }),
    "background.js": """
let queue = Promise.resolve();
const note = (event) => {
  queue = queue.then(() => chrome.storage.local.get({ events: [] }))
    .then(({ events }) => chrome.storage.local.set({ events: [...events, event] }));
};
const on = {
  clicked: (id) => note("clicked:" + id),
  button: (id, index) => note("button:" + id + ":" + index),
  closed: (id, byUser) => note("closed:" + id + ":" + byUser),
};
const start = () => {
  chrome.notifications.onClicked.addListener(on.clicked);
  chrome.notifications.onButtonClicked.addListener(on.button);
  chrome.notifications.onClosed.addListener(on.closed);
};
const stop = () => {
  chrome.notifications.onClicked.removeListener(on.clicked);
  chrome.notifications.onButtonClicked.removeListener(on.button);
  chrome.notifications.onClosed.removeListener(on.closed);
};
start();
chrome.runtime.onMessageExternal.addListener((message, sender, sendResponse) => {
  const answer = (p) => p.then((value) => sendResponse({ value }), (e) => sendResponse({ error: String(e) }));
  if (message.type === "start") { start(); sendResponse({ ok: true }); }
  else if (message.type === "stop") { stop(); sendResponse({ ok: true }); }
  else if (message.type === "create") answer(chrome.notifications.create(message.id, message.options));
  else if (message.type === "update") answer(chrome.notifications.update(message.id, message.options));
  else if (message.type === "clear") answer(chrome.notifications.clear(message.id));
  else if (message.type === "getAll") answer(chrome.notifications.getAll());
  else queue.then(() => chrome.storage.local.get({ events: [] })).then((r) => sendResponse(r));
  return true;
});
""",
}

ASK = """(function (ext, message) {
  window.__r = null;
  chrome.runtime.sendMessage(ext, message, (r) => { window.__r = r || { none: String(chrome.runtime.lastError && chrome.runtime.lastError.message) }; });
})(%s, %s); 1"""

BUTTONS = [{"title": "Mark as read"}, {"title": "Archive"}, {"title": "Third, dropped"}]


def probe_copy():
    app = work / "Search.app"
    shutil.copytree(Path(sv.ROOT, "build", "Search.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def ev(id, js):
    return sv.cmd({"do": "eval", "id": id, "js": js}).get("value")


def notes(**f):
    return sv.cmd({"do": "ext-notifications", **f})


def main():
    t = sv.T()
    folder = work / "ext"
    folder.mkdir()
    for name, body in FILES.items(): (folder / name).write_text(body)
    sv.APP = probe_copy()
    try:
        sv.setup(**{"start.fresh": False})
        sv.launch()
        sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
        ext = None
        for _ in range(60):
            ext = next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["name"] == "Notify Events" and x["loaded"]), None)
            if ext: break
            time.sleep(0.25)
        t.ok("the extension loads", ext is not None)
        if not ext: return t
        eid = ext["id"]

        listed = sv.page("listed")

        def ask(message):
            ev(listed, ASK % (json.dumps(eid), json.dumps(message)))
            for _ in range(80):
                got = ev(listed, "JSON.stringify(window.__r || null)")
                if got and got != "null": return json.loads(got)
                time.sleep(0.25)
            return None

        def told():
            return (ask({"type": "events"}) or {}).get("events", [])

        def wait_for(event, within=8):
            began = time.time()
            while time.time() - began < within:
                if event in told(): return True
                time.sleep(0.2)
            return False

        def wait_ports(n, within=10):
            status = {}
            for _ in range(int(within / 0.25)):
                status = notes()["status"]
                if status.get("ports") == n: return status
                time.sleep(0.25)
            return status

        status = wait_ports(1)
        t.ok("listening opens one port to the browser", status.get("ports") == 1, status)

        made = ask({"type": "create", "id": "t|acct|thread1", "options": {
            "type": "basic", "iconUrl": "icon.png", "title": "Ada", "message": "Lunch?",
            "contextMessage": "ada@example.com", "buttons": BUTTONS}})
        t.ok("create gives back its id", (made or {}).get("value") == "t|acct|thread1", made)
        recorded = notes()["recorded"]
        last = recorded[-1] if recorded else {}
        t.ok("posted with its title and message", last.get("title") == "Ada" and last.get("body") == "Lunch?", last)
        t.ok("its context line as the subtitle", last.get("subtitle") == "ada@example.com", last)
        t.ok("its first two buttons, as Chrome takes them", last.get("buttons") == ["Mark as read", "Archive"], last)
        t.ok("a category for the extension and its buttons", str(last.get("category", "")).startswith(f"ext.{eid}."), last)

        ask({"type": "create", "id": "t|acct|thread2", "options": {
            "type": "basic", "iconUrl": "icon.png", "title": "Bo", "message": "Hi", "buttons": BUTTONS[:2]}})
        second = notes()["recorded"][-1]
        t.ok("the same buttons, the same category", second.get("category") == last.get("category"), (second, last))
        t.ok("no context line: the extension's name", second.get("subtitle") == "Notify Events", second)
        ask({"type": "create", "id": "plain", "options": {"type": "basic", "iconUrl": "icon.png", "title": "No buttons", "message": "x"}})
        plain = notes()["recorded"][-1]
        t.ok("no buttons: the extension's own category", plain.get("category") == f"ext.{eid}", plain)

        listed_all = (ask({"type": "getAll"}) or {}).get("value") or {}
        t.ok("getAll lists those up", set(listed_all) == {"t|acct|thread1", "t|acct|thread2", "plain"}, listed_all)

        notes(extension=eid, key="t|acct|thread1", action="button.1")
        t.ok("a button is told as onButtonClicked with its number", wait_for("button:t|acct|thread1:1"), told())
        notes(extension=eid, key="t|acct|thread1", action="default")
        t.ok("a click is told as onClicked", wait_for("clicked:t|acct|thread1"), told())
        notes(extension=eid, key="t|acct|thread2", action="dismiss")
        t.ok("a dismissal is told as onClosed, by the user", wait_for("closed:t|acct|thread2:true"), told())
        time.sleep(1.5)
        events = told()
        t.ok("each told once", len(events) == len(set(events)) == 3, events)
        pending = {}
        for _ in range(20):
            pending = notes()["status"].get("pending", {})
            if not pending: break
            time.sleep(0.25)
        t.ok("the browser keeps nothing once heard", not pending, pending)

        listed_all = (ask({"type": "getAll"}) or {}).get("value") or {}
        t.ok("those clicked or dismissed are gone from getAll", set(listed_all) == {"plain"}, listed_all)
        updated = (ask({"type": "update", "id": "plain", "options": {"title": "Changed"}}) or {}).get("value")
        t.ok("update of one still up says so", updated is True, updated)
        missing = (ask({"type": "update", "id": "never", "options": {"title": "x"}}) or {}).get("value")
        t.ok("update of one never made says not", missing is False, missing)
        ask({"type": "clear", "id": "plain"})
        listed_all = (ask({"type": "getAll"}) or {}).get("value") or {}
        t.ok("clear takes it off the list", "plain" not in listed_all, listed_all)

        # No listener: the port goes, and a click waits for one.
        ask({"type": "stop"})
        status = wait_ports(0)
        t.ok("no listener left, no port", status.get("ports") == 0, status)
        notes(extension=eid, key="t|acct|thread3", action="button.0")
        time.sleep(1.5)
        t.ok("a click then is told to nobody yet", "button:t|acct|thread3:0" not in told(), told())
        t.ok("the browser keeps it", notes()["status"].get("pending", {}).get(eid) == 1, notes()["status"])
        ask({"type": "start"})
        t.ok("listening again, what was missed is told", wait_for("button:t|acct|thread3:0"), told())
    finally:
        sv.finish()
        for kind in ("WebKit", "Caches", "HTTPStorages"):
            shutil.rmtree(Path.home() / "Library" / kind / BUNDLE, ignore_errors=True)
        shutil.rmtree(work, ignore_errors=True)
    return t


if __name__ == "__main__":
    t = main()
    t.done()
