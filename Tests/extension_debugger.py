#!/usr/bin/env python3
"""An extension that works a page through Chrome's debugger API — Claude,
ChatGPT's agent — clicks, types, presses keys, takes pictures and runs
scripts in Quo, in a hidden probe.

Build first (`./build.sh`), then `python3 Tests/extension_debugger.py`.
It runs a copy of build/Search.app under a bundle id of its own, in a world
of its own with split_view.py's harness, started hidden; the copy, its
WebKit folders and the world are removed afterwards. Nothing is done on
your screen: every event goes to the page's view (ExtensionDebugger.swift).

Served here: a form with a field, a box for longer text and a button that
note whether what reached them was trusted, a red square, a box that
scrolls, and a page whose policy forbids eval. A test extension asking for
"debugger" goes through a simple form flow end to end with CDP commands —
the ones Claude's extension sends, and the DOM and Runtime ones other
agents use — and the page's state is checked after each. A second
extension that doesn't ask for "debugger" is refused.
"""
import json
import os
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

sv.use("ext-debugger")
BUNDLE = "com.officecommun.search.extdebugger"
work = Path(tempfile.mkdtemp(prefix="search-extdebugger-"))

FORM = b"""<!doctype html><title>Form</title>
<style>body{margin:0;font:16px sans-serif} #red{position:absolute;left:0;top:0;width:100px;height:100px;background:#f00}
form{position:absolute;left:150px;top:20px} #scroller{position:absolute;left:150px;top:300px;width:200px;height:100px;overflow:auto}
#scroller div{height:1000px}</style>
<div id=red></div>
<form id=f><input id=name name=name autocomplete=off><textarea id=note></textarea><button id=go type=button>Continue</button></form>
<div id=scroller><div>tall</div></div>
<script>
const d = document.documentElement.dataset;
document.getElementById('go').addEventListener('click', (e) => { d.clicked = String(e.isTrusted); d.clicks = String(Number(d.clicks || 0) + 1); });
document.getElementById('name').addEventListener('keydown', (e) => { d.keydown = (d.keydown || '') + e.key + (e.isTrusted ? '' : '?') + ','; });
document.getElementById('name').addEventListener('input', (e) => { d.input = String(e.isTrusted); });
document.getElementById('f').addEventListener('submit', (e) => { e.preventDefault(); d.submitted = document.getElementById('name').value; });
window.addEventListener('keydown', (e) => { if (e.metaKey && e.key === 'k') d.shortcut = 'cmd-k'; });
</script>"""


class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        body = FORM if self.path.startswith("/form") else b"<!doctype html><title>Strict</title><p id=p>strict</p>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        if self.path.startswith("/strict"):
            self.send_header("Content-Security-Policy", "script-src 'none'; object-src 'none'")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


# The extension's page runs each step and keeps the answer, since the
# bench's eval answers at once: R[name] is "pending" until it is done.
HARNESS = """
window.R = {};
window.run = (name, f) => {
  R[name] = "pending";
  Promise.resolve().then(f).then((v) => { R[name] = JSON.stringify({ ok: v === undefined ? null : v }); },
    (e) => { R[name] = JSON.stringify({ err: String(e && e.message || e) }); });
  return 1;
};
window.cdp = (tabId, method, params) => chrome.debugger.sendCommand({ tabId }, method, params || {});
// The callback form, with Chrome's lastError.
window.cdpCb = (tabId, method, params) => new Promise((ok) => chrome.debugger.sendCommand({ tabId }, method, params || {}, (r) => {
  ok({ result: r === undefined ? null : r, lastError: chrome.runtime.lastError ? chrome.runtime.lastError.message : null });
}));
window.ev = async (tabId, expression, extra) => (await cdp(tabId, "Runtime.evaluate", Object.assign({ expression, returnByValue: true, awaitPromise: true }, extra || {})));
window.click = async (tabId, x, y) => {
  await cdp(tabId, "Input.dispatchMouseEvent", { type: "mouseMoved", x, y, button: "none", buttons: 0 });
  await cdp(tabId, "Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", buttons: 1, clickCount: 1 });
  await cdp(tabId, "Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", buttons: 0, clickCount: 1 });
};
window.center = async (tabId, sel) => (await ev(tabId, `(() => { const r = document.querySelector(${JSON.stringify(sel)}).getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()`)).result.value;
window.key = async (tabId, k) => {
  await cdp(tabId, "Input.dispatchKeyEvent", Object.assign({ type: k.text ? "keyDown" : "rawKeyDown" }, k));
  await cdp(tabId, "Input.dispatchKeyEvent", { type: "keyUp", key: k.key, code: k.code, modifiers: k.modifiers || 0, windowsVirtualKeyCode: k.windowsVirtualKeyCode });
};
// A picture's size, and the colour at a point of it.
window.look = (b64, format, x, y) => new Promise((ok, no) => {
  const img = new Image();
  img.onload = () => {
    const c = document.createElement("canvas"); c.width = img.width; c.height = img.height;
    const g = c.getContext("2d"); g.drawImage(img, 0, 0);
    ok({ width: img.width, height: img.height, rgb: Array.from(g.getImageData(x, y, 1, 1).data).slice(0, 3) });
  };
  img.onerror = () => no(new Error("bad image"));
  img.src = "data:image/" + format + ";base64," + b64;
});
"""

FILES = {
    "manifest.json": json.dumps({
        "manifest_version": 3, "name": "Driver", "version": "1.0",
        "permissions": ["debugger", "tabs", "tabGroups"], "host_permissions": ["<all_urls>"],
        "background": {"service_worker": "sw.js"},
    }),
    "sw.js": "chrome.runtime.onInstalled.addListener(() => {});",
    "page.html": "<!doctype html><title>driver</title><script src=page.js></script>",
    "page.js": HARNESS,
}
OTHER = {
    "manifest.json": json.dumps({"manifest_version": 3, "name": "NoDebugger", "version": "1.0",
                                 "permissions": ["tabs"], "background": {"service_worker": "sw.js"}}),
    "sw.js": "chrome.runtime.onInstalled.addListener(() => {});",
    "page.html": "<!doctype html><title>other</title><script src=page.js></script>",
    "page.js": HARNESS,
}


def probe_copy():
    """build/Search.app under a bundle id of its own, signed ad hoc."""
    app = work / "Search.app"
    shutil.copytree(Path(sv.ROOT, "build", "Search.app"), app, symlinks=True)
    subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Set :CFBundleIdentifier {BUNDLE}", str(app / "Contents/Info.plist")], check=True)
    (app / "Contents/embedded.provisionprofile").unlink(missing_ok=True)
    subprocess.run(["codesign", "-f", "-s", "-", "--entitlements", str(Path(sv.ROOT, "Search.entitlements")), "--deep", str(app)],
                   check=True, capture_output=True)
    return str(app)


def loaded(name, within=30):
    end = time.time() + within
    while time.time() < end:
        ext = next((x for x in sv.cmd({"do": "extensions"})["extensions"] if x["name"] == name and x["loaded"]), None)
        if ext:
            return ext
        time.sleep(0.5)
    return None


def step(page, name, js, within=20):
    """Runs `js` (an async function body) in the extension's page."""
    sv.ev(page, f"run({json.dumps(name)}, async () => {{ {js} }})")
    end = time.time() + within
    while time.time() < end:
        got = sv.ev(page, f"R[{json.dumps(name)}]")
        if got and got != "pending":
            return json.loads(got)
        time.sleep(0.2)
    return {"err": "timed out"}


def data(tid):
    return json.loads(sv.ev(tid, "JSON.stringify(Object.assign({}, document.documentElement.dataset))") or "{}")


def install(files, name):
    folder = work / name
    folder.mkdir()
    for file, body in files.items():
        (folder / file).write_text(body)
    sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
    return loaded(name)


def main():
    t = sv.T()
    site = ThreadingHTTPServer(("127.0.0.1", 0), Site)
    threading.Thread(target=site.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{site.server_port}"
    sv.APP = probe_copy()
    try:
        sv.setup(**{"tabs.groups": True, "sidebar": True, "sidebar.roomy": True})
        sv.launch()
        ext = install(FILES, "Driver")
        t.ok("the extension loads", ext is not None)
        if not ext:
            return t
        # Tabs of your own, not the bench's: those are never grouped, and
        # these sit off screen behind the extension's page, as a background
        # tab an agent works in does.
        form = sv.sp("open", url=base + "/form")["resultID"]
        strict = sv.sp("open", url=base + "/strict")["resultID"]
        time.sleep(3)
        page = sv.cmd({"do": "ext-page", "id": ext["id"], "path": "page.html"})["id"]
        time.sleep(2)
        t.ok("chrome.debugger is there", sv.ev(page, "typeof chrome.debugger.attach") == "function")

        ids = step(page, "ids", f"""
          const all = await chrome.tabs.query({{}});
          return {{ form: all.find((x) => x.url.startsWith({json.dumps(base + '/form')})).id,
                    strict: all.find((x) => x.url.startsWith({json.dumps(base + '/strict')})).id }};""").get("ok") or {}
        t.ok("its tabs are found", "form" in ids and "strict" in ids, ids)
        F, S = ids.get("form"), ids.get("strict")

        r = step(page, "unattached", f"return await cdpCb({F}, 'Page.enable');")
        t.ok("a command before attaching: lastError, as in Chrome",
             "not attached" in str((r.get("ok") or {}).get("lastError")), r)

        r = step(page, "missing", "return await new Promise((ok) => chrome.debugger.attach({ tabId: 987654 }, '1.3', () => ok(chrome.runtime.lastError ? chrome.runtime.lastError.message : null)));")
        t.ok("attaching to a tab that isn't there: lastError", "No tab" in str(r.get("ok")), r)
        r = step(page, "attach", f"""
          await chrome.debugger.attach({{ tabId: {F} }}, "1.3");
          const targets = await chrome.debugger.getTargets();
          let again = null; try {{ await chrome.debugger.attach({{ tabId: {F} }}, "1.3"); }} catch (e) {{ again = e.message; }}
          return {{ attached: targets.find((x) => x.tabId === {F}).attached, again }};""")
        t.ok("attaches, and getTargets says so", (r.get("ok") or {}).get("attached") is True, r)
        t.ok("a second attach is refused", "already attached" in str((r.get("ok") or {}).get("again")), r)
        r = step(page, "enable", f"await cdp({F}, 'Page.enable'); await cdp({F}, 'Runtime.enable'); return await cdp({F}, 'Network.enable');")
        t.ok("Page, Runtime and Network enable", r.get("ok") == {}, r)

        # Scripts, answered as Chrome answers.
        r = step(page, "eval1", f"return (await ev({F}, 'document.title')).result;")
        t.ok("Runtime.evaluate: a value", (r.get("ok") or {}).get("value") == "Form", r)
        r = step(page, "eval2", f"return (await ev({F}, '{{\\nconst a = 2;\\na * 21\\n}}', {{ replMode: true }})).result;")
        t.ok("the last statement's value, in Claude's block", (r.get("ok") or {}).get("value") == 42, r)
        r = step(page, "eval3", f"return (await ev({F}, 'await new Promise((r) => setTimeout(r, 20));\\nconst o = {{ a: [1, 2], b: \"x\" }};\\no')).result;")
        t.ok("awaits at the top, and an object comes back by value", (r.get("ok") or {}).get("value") == {"a": [1, 2], "b": "x"}, r)
        r = step(page, "eval4", f"return await ev({F}, 'null.x');")
        exc = ((r.get("ok") or {}).get("exceptionDetails") or {}).get("exception") or {}
        t.ok("an exception is exceptionDetails", exc.get("className") == "TypeError" and "TypeError" in exc.get("description", ""), r)
        r = step(page, "eval5", f"return await ev({F}, '1 +');")
        exc = ((r.get("ok") or {}).get("exceptionDetails") or {}).get("exception") or {}
        t.ok("a syntax error too", exc.get("className") == "SyntaxError", r)
        r = step(page, "eval6", f"return (await ev({F}, '(async()=>{{\\nreturn document.querySelectorAll(\"input\").length\\n}})()')).result;")
        t.ok("Claude's retry, an async function with return", (r.get("ok") or {}).get("value") == 1, r)
        r = step(page, "eval7", f"return (await ev({F}, '// a comment; 5\\n6')).result;")
        t.ok("a comment isn't mistaken for code", (r.get("ok") or {}).get("value") == 6, r)
        r = step(page, "eval8", f"return (await ev({F}, 'await new Promise(() => {{}})', {{ timeout: 300 }}));")
        desc = str(((r.get("ok") or {}).get("exceptionDetails") or {}).get("exception", {}).get("description"))
        t.ok("a timeout answers as Chrome's terminated execution", "execution was terminated" in desc, r)

        # Strict CSP: scripts still run.
        step(page, "attach2", f"await chrome.debugger.attach({{ tabId: {S} }}, '1.3');")
        r = step(page, "csp", f"return (await ev({S}, 'const p = document.getElementById(\"p\");\\np.textContent')).result;")
        t.ok("a page whose policy forbids eval still runs the script", (r.get("ok") or {}).get("value") == "strict", r)

        # The form flow: click the field, type, press keys, click the button.
        r = step(page, "field", f"const [x, y] = await center({F}, '#name'); await click({F}, x, y); return (await ev({F}, 'document.activeElement.id')).result.value;")
        t.ok("a click puts focus in the field", r.get("ok") == "name", r)
        r = step(page, "type", f"""
          await cdp({F}, 'Input.insertText', {{ text: 'Ada' }});
          for (const c of ' Lo') await key({F}, {{ key: c, code: c === ' ' ? 'Space' : 'Key' + c.toUpperCase(), text: c, windowsVirtualKeyCode: c.toUpperCase().charCodeAt(0), modifiers: c === 'L' ? 8 : 0 }});
          return (await ev({F}, 'document.getElementById(\"name\").value')).result.value;""")
        t.ok("insertText and typed keys put text in", r.get("ok") == "Ada Lo", r)
        d = data(form)
        t.ok("the page heard trusted keys and input", d.get("input") == "true" and "L," in d.get("keydown", "") and "?" not in d.get("keydown", ""), d)
        r = step(page, "backspace", f"""
          await key({F}, {{ key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8 }});
          return (await ev({F}, 'document.getElementById(\"name\").value')).result.value;""")
        t.ok("Backspace deletes", r.get("ok") == "Ada L", r)
        r = step(page, "selectall", f"""
          await key({F}, {{ key: 'a', code: 'KeyA', text: 'a', windowsVirtualKeyCode: 65, modifiers: 4, commands: ['selectAll'] }});
          await cdp({F}, 'Input.insertText', {{ text: 'Grace' }});
          return (await ev({F}, 'document.getElementById(\"name\").value')).result.value;""")
        t.ok("⌘A with selectAll, then typing, replaces the text", r.get("ok") == "Grace", r)
        step(page, "shortcut", f"await key({F}, {{ key: 'k', code: 'KeyK', text: 'k', windowsVirtualKeyCode: 75, modifiers: 4 }});")
        t.ok("a ⌘ key without a command reaches the page's own shortcut", data(form).get("shortcut") == "cmd-k", data(form))
        r = step(page, "enter", f"""
          await cdp({F}, 'Input.dispatchKeyEvent', {{ type: 'keyDown', key: 'Enter', code: 'Enter', text: '\\r', windowsVirtualKeyCode: 13 }});
          await cdp({F}, 'Input.dispatchKeyEvent', {{ type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 }});
          return 1;""")
        time.sleep(0.5)
        t.ok("Return submits the form", data(form).get("submitted") == "Grace", data(form))
        r = step(page, "button", f"const [x, y] = await center({F}, '#go'); await click({F}, x, y); return 1;")
        time.sleep(0.3)
        d = data(form)
        t.ok("a click on the button reaches it once, trusted", d.get("clicked") == "true" and d.get("clicks") == "1", d)
        r = step(page, "tab", f"""
          const [x, y] = await center({F}, '#name'); await click({F}, x, y);
          await key({F}, {{ key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 }});
          return (await ev({F}, 'document.activeElement.id')).result.value;""")
        t.ok("Tab moves focus on, to the next field", r.get("ok") == "note", r)

        # Pictures.
        r = step(page, "shot", f"""
          const m = (await ev({F}, '[innerWidth, innerHeight, devicePixelRatio]')).result.value;
          const s = await cdp({F}, 'Page.captureScreenshot', {{ format: 'png', captureBeyondViewport: false, fromSurface: true }});
          const seen = await look(s.data, 'png', 10, 10);
          return {{ m, seen }};""")
        ok = r.get("ok") or {}
        m, seen = ok.get("m") or [0, 0, 1], ok.get("seen") or {}
        t.ok("a screenshot the size of the viewport at the screen's scale",
             abs(seen.get("width", 0) - m[0] * m[2]) <= 1 and abs(seen.get("height", 0) - m[1] * m[2]) <= 1, r)
        t.ok("showing the page: red at the top left", seen.get("rgb", [0])[0] > 200 and seen.get("rgb", [0, 255])[1] < 60, r)
        r = step(page, "clip", f"""
          const s = await cdp({F}, 'Page.captureScreenshot', {{ format: 'jpeg', quality: 80, clip: {{ x: 50, y: 50, width: 100, height: 100, scale: 0.5 }} }});
          const dpr = (await ev({F}, 'devicePixelRatio')).result.value;
          return {{ dpr, left: await look(s.data, 'jpeg', 2, 2), right: await look(s.data, 'jpeg', Math.round(45 * dpr), 2) }};""")
        ok = r.get("ok") or {}
        dpr = ok.get("dpr") or 1
        t.ok("a clip at a scale: its size", abs((ok.get("left") or {}).get("width", 0) - 50 * dpr) <= 1, r)
        t.ok("and what's in it: red, then not", (ok.get("left") or {}).get("rgb", [0])[0] > 200
             and (ok.get("right") or {}).get("rgb", [0, 0])[1] > 150, r)

        # The DOM, for agents that find elements by node.
        r = step(page, "dom", f"""
          const root = (await cdp({F}, 'DOM.getDocument')).root;
          const {{ nodeId }} = await cdp({F}, 'DOM.querySelector', {{ nodeId: root.nodeId, selector: '#go' }});
          const box = (await cdp({F}, 'DOM.getBoxModel', {{ nodeId }})).model;
          const {{ object }} = await cdp({F}, 'DOM.resolveNode', {{ nodeId }});
          const called = await cdp({F}, 'Runtime.callFunctionOn', {{ objectId: object.objectId, functionDeclaration: 'function (suffix) {{ return this.textContent + suffix; }}', arguments: [{{ value: '!' }}], returnByValue: true }});
          const metrics = await cdp({F}, 'Page.getLayoutMetrics');
          const tree = await cdp({F}, 'Page.getFrameTree');
          return {{ name: root.nodeName, nodeId, width: box.width, called: called.result.value, sub: object.subtype,
                    vw: metrics.cssLayoutViewport.clientWidth, url: tree.frameTree.frame.url }};""")
        ok = r.get("ok") or {}
        t.ok("DOM.getDocument and querySelector", ok.get("name") == "#document" and ok.get("nodeId", 0) > 0, r)
        t.ok("getBoxModel, resolveNode and callFunctionOn on the node", ok.get("width", 0) > 0 and ok.get("sub") == "node"
             and ok.get("called") == "Continue!", r)
        t.ok("layout metrics and the frame tree", ok.get("vw", 0) > 0 and ok.get("url", "").startswith(base + "/form"), r)

        # The wheel scrolls the box under it.
        r = step(page, "wheel", f"""
          const [x, y] = await center({F}, '#scroller');
          await cdp({F}, 'Input.dispatchMouseEvent', {{ type: 'mouseWheel', x, y, deltaX: 0, deltaY: 120 }});
          return (await ev({F}, 'document.getElementById(\"scroller\").scrollTop')).result.value;""")
        t.ok("mouseWheel scrolls the box under it", (r.get("ok") or 0) >= 100, r)

        # A drag selects the field's text.
        r = step(page, "drag", f"""
          const b = (await ev({F}, '(() => {{ const r = document.getElementById(\"name\").getBoundingClientRect(); return [r.left + 3, r.right - 3, r.top + r.height / 2]; }})()')).result.value;
          await cdp({F}, 'Input.dispatchMouseEvent', {{ type: 'mousePressed', x: b[0], y: b[2], button: 'left', buttons: 1, clickCount: 1 }});
          await cdp({F}, 'Input.dispatchMouseEvent', {{ type: 'mouseMoved', x: (b[0] + b[1]) / 2, y: b[2], button: 'left', buttons: 1 }});
          await cdp({F}, 'Input.dispatchMouseEvent', {{ type: 'mouseMoved', x: b[1], y: b[2], button: 'left', buttons: 1 }});
          await cdp({F}, 'Input.dispatchMouseEvent', {{ type: 'mouseReleased', x: b[1], y: b[2], button: 'left', buttons: 0, clickCount: 1 }});
          return (await ev({F}, '(() => {{ const n = document.getElementById(\"name\"); return n.selectionEnd - n.selectionStart; }})()')).result.value;""")
        t.ok("a drag across the field selects its text", (r.get("ok") or 0) >= 4, r)

        # Its own group, as Claude makes one to work in, looks like an
        # agent's: marked as its, and at work while it sends commands.
        mine = sv.sp("open", url=base + "/form?mine")["resultID"]
        sv.cmd({"do": "group", "id": mine, "new": True, "name": "Reading"})
        r = step(page, "group", f"""
          const g = await chrome.tabs.group({{ tabIds: [{F}, {S}] }});
          await chrome.tabGroups.update(g, {{ title: 'Claude' }});
          await cdp({F}, 'Runtime.evaluate', {{ expression: '1' }});
          return g;""")
        listed = sv.cmd({"do": "group"})
        groups = {g["name"]: g for g in listed.get("groups", [])}
        t.ok("the group it makes is marked as an agent's", (groups.get("Claude") or {}).get("agent") == ext["id"], (r, listed))
        t.ok("and shows it at work", (groups.get("Claude") or {}).get("working") is True, groups)
        t.ok("a group of your own isn't", (groups.get("Reading") or {}).get("agent") is None, groups)
        shots = os.environ.get("SEARCH_PICTURES")
        if shots:
            sv.cmd({"do": "picture", "path": str(Path(shots, "agent-group-roomy.png"))})
        time.sleep(5)
        groups = {g["name"]: g for g in sv.cmd({"do": "group"}).get("groups", [])}
        t.ok("quiet again a few seconds after its last command", (groups.get("Claude") or {}).get("working") is False, groups)
        if shots:
            sv.cmd({"do": "picture", "path": str(Path(shots, "agent-group-quiet.png"))})

        r = step(page, "unknown", f"return await cdpCb({F}, 'Nope.nothing');")
        t.ok("an unknown command is Chrome's error", "wasn't found" in str((r.get("ok") or {}).get("lastError")), r)
        r = step(page, "detach", f"""
          await chrome.debugger.detach({{ tabId: {F} }});
          const after = await cdpCb({F}, 'Page.enable');
          const targets = await chrome.debugger.getTargets();
          return {{ after: after.lastError, attached: targets.find((x) => x.tabId === {F}).attached }};""")
        ok = r.get("ok") or {}
        t.ok("detached, commands are refused and getTargets says so", "not attached" in str(ok.get("after")) and ok.get("attached") is False, r)

        # An extension that never asked for the debugger.
        other = install(OTHER, "NoDebugger")
        if other:
            opage = sv.cmd({"do": "ext-page", "id": other["id"], "path": "page.html"})["id"]
            time.sleep(2)
            r = step(opage, "refused", f"""
              let why = null; try {{ await chrome.debugger.attach({{ tabId: {F} }}, '1.3'); }} catch (e) {{ why = e.message; }}
              return why;""")
            t.ok("an extension without the permission is refused", "isn't available" in str(r.get("ok")), r)
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
