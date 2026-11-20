import AppKit
import JavaScriptCore
import WebKit

// Chrome's debugger API, for the extensions that work a page the way a person
// would: Claude, ChatGPT's agent and the like click, type, take pictures and
// run scripts through `chrome.debugger` and the DevTools protocol. WebKit has
// neither, so this answers the part of the protocol those extensions send,
// with the tab's own view:
//
// - clicks, drags and keys are real events handed straight to the page's
//   view, as the bench's and coding agents' are (PageHands): the page hears
//   trusted events and does what it does for a hand — a field takes focus,
//   Return submits its form, Tab moves on. Never through the app, so none of
//   Quo's shortcuts or menus hears them, and the pointer never moves;
// - text goes in as typing does, through the view's text input;
// - pictures are the view's snapshot, cut and scaled as asked;
// - scripts run in the page's own world, their answer shaped as Chrome's.
//
// Only for an extension whose manifest asks for "debugger" (the gate in
// ExtensionShims), only on web pages, and only in tabs it may see. A tab
// that isn't on screen is laid out in the room off every screen
// (PageRoom) while it is worked, as Chrome works a background tab.

@available(macOS 15.4, *)
@MainActor
enum ExtensionDebugger {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The tabs each extension has attached to, by Chrome's tab id.
    private static var attached: [String: Set<Int>] = [:]
    /// The mouse buttons held in each view, for drags.
    private static var held: [ObjectIdentifier: Int] = [:]
    /// Key-downs answered with editing commands, so their key-ups are too.
    private static var commanded: [ObjectIdentifier: Set<String>] = [:]

    // MARK: - attaching

    static func attach(_ id: Int, tab: Tab?, extension ext: String) throws {
        guard let tab else { throw Failure(message: "No tab with given id \(id).") }
        try check(tab)
        // The same extension attaching again is its background started over
        // (an update, a worker woken afresh), which in Chrome would have
        // detached it: it is attached, as it asked.
        attached[ext, default: []].insert(id)
    }

    static func detach(_ id: Int, extension ext: String) throws {
        guard attached[ext]?.remove(id) != nil else {
            throw Failure(message: "Debugger is not attached to the tab with id: \(id).")
        }
    }

    static func targets(extension ext: String) -> [Int] { Array(attached[ext] ?? []) }

    /// An extension gone, its attachments with it.
    static func forget(extension ext: String) { attached[ext] = nil }

    /// Web pages only: not Quo's own, nor any extension's, nor a file.
    static func check(_ tab: Tab) throws {
        let url = tab.address
        let scheme = url?.scheme?.lowercased() ?? "about"
        guard ["http", "https", "about", "data", "blob"].contains(scheme) else {
            throw Failure(message: "Cannot access a \(scheme):// URL.")
        }
    }

    // MARK: - commands

    static func send(_ method: String, _ params: [String: Any], tabID id: Int, tab: Tab?, extension ext: String) async throws -> Any {
        guard attached[ext]?.contains(id) == true else {
            throw Failure(message: "Debugger is not attached to the tab with id: \(id).")
        }
        guard let tab else { throw Failure(message: "No tab with given id \(id).") }
        try check(tab)
        let web = tab.web
        // Its group's heading shows the agent at work (AgentGroups.swift).
        if !method.hasSuffix(".enable"), !method.hasSuffix(".disable") { AgentActivity.shared.touched(tab.id) }
        switch method {
        // Domains whose only work in Chrome is to send events: on.
        case "Page.enable", "Page.disable", "Runtime.enable", "Runtime.disable", "Network.enable", "Network.disable",
             "DOM.enable", "DOM.disable", "CSS.enable", "CSS.disable", "Log.enable", "Log.disable",
             "Console.enable", "Console.disable", "Overlay.enable", "Overlay.disable", "Inspector.enable",
             "Security.enable", "Accessibility.enable", "Accessibility.disable", "Page.setLifecycleEventsEnabled",
             "Runtime.runIfWaitingForDebugger", "Runtime.releaseObjectGroup", "Target.setAutoAttach",
             "Target.setDiscoverTargets", "Emulation.setFocusEmulationEnabled", "Input.cancelDragging",
             "Input.setIgnoreInputEvents", "Network.setCacheDisabled", "Page.bringToFront":
            return [String: Any]()
        case "Page.handleJavaScriptDialog":
            throw Failure(message: "No dialog is showing")
        case "Input.dispatchMouseEvent":
            return try await mouse(params, in: web, tab: tab)
        case "Input.dispatchKeyEvent":
            return try await key(params, in: web, tab: tab)
        case "Input.insertText":
            return try await insert(params["text"] as? String ?? "", in: web, tab: tab)
        case "Input.synthesizeScrollGesture":
            let x = number(params["x"]) ?? 0, y = number(params["y"]) ?? 0
            return try await wheel(["x": x, "y": y, "deltaX": -(number(params["xDistance"]) ?? 0),
                                    "deltaY": -(number(params["yDistance"]) ?? 0)], in: web)
        case "Page.captureScreenshot":
            return try await screenshot(params, of: web, tab: tab)
        case "Page.getFrameTree":
            return ["frameTree": ["frame": frame(web, tab: tab, id: id), "childFrames": [Any]()]]
        case "Page.getNavigationHistory":
            let list = web.backForwardList
            let items = list.backList + (list.currentItem.map { [$0] } ?? []) + list.forwardList
            return ["currentIndex": list.backList.count,
                    "entries": items.enumerated().map { ["id": $0.offset, "url": $0.element.url.absoluteString,
                                                         "userTypedURL": $0.element.initialURL.absoluteString,
                                                         "title": $0.element.title ?? "", "transitionType": "link"] }]
        case "Page.navigateToHistoryEntry":
            let list = web.backForwardList
            let items = list.backList + (list.currentItem.map { [$0] } ?? []) + list.forwardList
            guard let index = params["entryId"] as? Int, items.indices.contains(index) else {
                throw Failure(message: "No entry with passed id")
            }
            web.go(to: items[index])
            return [String: Any]()
        case "Page.navigate":
            guard let text = params["url"] as? String, let url = URL(string: text),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") || text == "about:blank"
            else { throw Failure(message: "Cannot navigate to invalid URL") }
            web.load(URLRequest(url: url))
            return ["frameId": frameID(id), "loaderId": UUID().uuidString]
        case "Page.reload":
            if params["ignoreCache"] as? Bool == true { web.reloadFromOrigin() } else { web.reload() }
            return [String: Any]()
        case "Page.stopLoading":
            web.stopLoading()
            return [String: Any]()
        case "Target.getTargetInfo":
            return ["targetInfo": ["targetId": String(id), "type": "page", "title": tab.title,
                                   "url": tab.address?.absoluteString ?? "", "attached": true, "canAccessOpener": false]]
        case "Browser.getVersion":
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            return ["protocolVersion": "1.3", "product": "\(Store.name)/\(version)", "revision": "",
                    "userAgent": web.customUserAgent ?? "", "jsVersion": ""]
        case "Runtime.evaluate":
            return try await evaluate(params, in: web)
        case "Runtime.callFunctionOn":
            return try await callFunctionOn(params, in: web)
        case "Page.getLayoutMetrics", "Runtime.getProperties", "Runtime.releaseObject",
             "DOM.getDocument", "DOM.querySelector", "DOM.querySelectorAll", "DOM.describeNode", "DOM.resolveNode",
             "DOM.requestNode", "DOM.getBoxModel", "DOM.getContentQuads", "DOM.scrollIntoViewIfNeeded", "DOM.focus",
             "DOM.getOuterHTML", "DOM.setAttributeValue", "DOM.getNodeForLocation", "DOM.getAttributes",
             "DOM.removeNode", "DOM.setNodeValue":
            return try await kit(method, params, in: web, frame: frameID(id))
        default:
            throw Failure(message: "'\(method)' wasn't found")
        }
    }

    // MARK: - the view

    /// The view of a tab with somewhere to be: one off screen is laid out in
    /// the room off every screen while it is worked.
    private static func placed(_ web: PageView, tab: Tab) -> PageView {
        if web.window == nil { PageRoom.shared.house(tab, anyway: true) }
        return web
    }

    /// CSS pixels to the view's points.
    private static func zoom(_ web: WKWebView) -> CGFloat { max(web.pageZoom, 0.1) * max(web.magnification, 0.1) }

    /// A point in the page's viewport, in the window's coordinates.
    private static func spot(_ x: Double, _ y: Double, in web: WKWebView) -> NSPoint {
        let z = zoom(web)
        let local = NSPoint(x: CGFloat(x) * z, y: web.isFlipped ? CGFloat(y) * z : web.bounds.height - CGFloat(y) * z)
        return web.convert(local, to: nil)
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    private static func flags(_ modifiers: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & 1 != 0 { flags.insert(.option) }
        if modifiers & 2 != 0 { flags.insert(.control) }
        if modifiers & 4 != 0 { flags.insert(.command) }
        if modifiers & 8 != 0 { flags.insert(.shift) }
        return flags
    }

    // MARK: - the mouse

    private static func mouse(_ p: [String: Any], in page: PageView, tab: Tab) async throws -> Any {
        let type = p["type"] as? String ?? ""
        let x = number(p["x"]) ?? 0, y = number(p["y"]) ?? 0
        let button = p["button"] as? String ?? "none"
        let modifiers = flags(p["modifiers"] as? Int ?? 0)
        if type == "mouseWheel" {
            return try await wheel(p, in: page)
        }
        // The right button opens the app's own menu over the page: the page
        // is told of it, and no menu is shown.
        if button == "right" || button == "back" || button == "forward" {
            if type == "mousePressed" {
                if button == "back", page.canGoBack { page.goBack() }
                if button == "forward", page.canGoForward { page.goForward() }
            }
            if button == "right" { try await script(Self.rightClick, ["type": type, "x": x, "y": y], in: page) }
            return [String: Any]()
        }
        let web = placed(page, tab: tab)
        guard let window = web.window else { throw Failure(message: "The tab has no window") }
        let key = ObjectIdentifier(web)
        let middle = button == "middle"
        let kind: NSEvent.EventType
        switch type {
        case "mousePressed":
            kind = middle ? .otherMouseDown : .leftMouseDown
            held[key] = middle ? 4 : 1
        case "mouseReleased":
            kind = middle ? .otherMouseUp : .leftMouseUp
            held[key] = nil
        case "mouseMoved":
            let buttons = p["buttons"] as? Int ?? held[key] ?? 0
            kind = buttons & 1 != 0 ? .leftMouseDragged : buttons & 4 != 0 ? .otherMouseDragged : .mouseMoved
        default:
            throw Failure(message: "Invalid type: \(type)")
        }
        let count = max(p["clickCount"] as? Int ?? (type == "mouseMoved" ? 0 : 1), 0)
        guard var event = NSEvent.mouseEvent(
            with: kind, location: spot(x, y, in: web), modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: count, pressure: kind == .leftMouseDown || kind == .otherMouseDown ? 1 : 0
        ) else { throw Failure(message: "Couldn't make the event") }
        if middle, let raw = event.cgEvent {
            raw.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            if let again = NSEvent(cgEvent: raw) { event = again }
        }
        switch kind {
        case .leftMouseDown: web.mouseDown(with: event)
        case .leftMouseUp: web.mouseUp(with: event)
        case .leftMouseDragged: web.mouseDragged(with: event)
        case .otherMouseDown: web.otherMouseDown(with: event)
        case .otherMouseUp: web.otherMouseUp(with: event)
        case .otherMouseDragged: web.otherMouseDragged(with: event)
        default: web.mouseMoved(with: event)
        }
        return [String: Any]()
    }

    private static let rightClick = """
    const el = document.elementFromPoint(x, y) || document.body;
    const init = { bubbles: true, cancelable: true, composed: true, clientX: x, clientY: y, button: 2, view: window };
    if (type === "mousePressed") {
      el.dispatchEvent(new PointerEvent("pointerdown", { ...init, buttons: 2, pointerType: "mouse", isPrimary: true }));
      el.dispatchEvent(new MouseEvent("mousedown", { ...init, buttons: 2 }));
    } else if (type === "mouseReleased") {
      el.dispatchEvent(new PointerEvent("pointerup", { ...init, buttons: 0, pointerType: "mouse", isPrimary: true }));
      el.dispatchEvent(new MouseEvent("mouseup", { ...init, buttons: 0 }));
      el.dispatchEvent(new MouseEvent("contextmenu", { ...init, buttons: 0 }));
    }
    return 1;
    """

    /// A turn of the wheel: the page hears it, and what it doesn't take
    /// scrolls the nearest box that can.
    private static func wheel(_ p: [String: Any], in web: WKWebView) async throws -> Any {
        try await script("""
        const el = document.elementFromPoint(x, y) || document.scrollingElement || document.documentElement;
        const taken = !el.dispatchEvent(new WheelEvent("wheel", { bubbles: true, cancelable: true, composed: true,
          clientX: x, clientY: y, deltaX: dx, deltaY: dy, deltaMode: 0, view: window }));
        if (taken) return 1;
        const can = (n) => {
          if (!(n instanceof Element)) return false;
          const s = getComputedStyle(n);
          const y = dy && /(auto|scroll|overlay)/.test(s.overflowY) && n.scrollHeight > n.clientHeight;
          const x = dx && /(auto|scroll|overlay)/.test(s.overflowX) && n.scrollWidth > n.clientWidth;
          return y || x;
        };
        let box = el;
        while (box && box !== document.documentElement && box !== document.body && !can(box)) {
          box = box.parentElement || (box.getRootNode() && box.getRootNode().host) || null;
        }
        if (box && box !== document.documentElement && box !== document.body) box.scrollBy(dx, dy);
        else window.scrollBy(dx, dy);
        return 1;
        """, ["x": number(p["x"]) ?? 0, "y": number(p["y"]) ?? 0,
              "dx": number(p["deltaX"]) ?? 0, "dy": number(p["deltaY"]) ?? 0], in: web)
        return [String: Any]()
    }

    // MARK: - keys

    /// Chrome's `code` names to the Mac's key codes.
    private static let codes: [String: UInt16] = [
        "KeyA": 0, "KeyS": 1, "KeyD": 2, "KeyF": 3, "KeyH": 4, "KeyG": 5, "KeyZ": 6, "KeyX": 7, "KeyC": 8, "KeyV": 9,
        "KeyB": 11, "KeyQ": 12, "KeyW": 13, "KeyE": 14, "KeyR": 15, "KeyY": 16, "KeyT": 17, "Digit1": 18, "Digit2": 19,
        "Digit3": 20, "Digit4": 21, "Digit6": 22, "Digit5": 23, "Equal": 24, "Digit9": 25, "Digit7": 26, "Minus": 27,
        "Digit8": 28, "Digit0": 29, "BracketRight": 30, "KeyO": 31, "KeyU": 32, "BracketLeft": 33, "KeyI": 34,
        "KeyP": 35, "Enter": 36, "KeyL": 37, "KeyJ": 38, "Quote": 39, "KeyK": 40, "Semicolon": 41, "Backslash": 42,
        "Comma": 43, "Slash": 44, "KeyN": 45, "KeyM": 46, "Period": 47, "Tab": 48, "Space": 49, "Backquote": 50,
        "Backspace": 51, "Escape": 53, "NumpadDecimal": 65, "NumpadMultiply": 67, "NumpadAdd": 69, "NumpadDivide": 75,
        "NumpadEnter": 76, "NumpadSubtract": 78, "NumpadEqual": 81, "Numpad0": 82, "Numpad1": 83, "Numpad2": 84,
        "Numpad3": 85, "Numpad4": 86, "Numpad5": 87, "Numpad6": 88, "Numpad7": 89, "Numpad8": 91, "Numpad9": 92,
        "F5": 96, "F6": 97, "F7": 98, "F3": 99, "F8": 100, "F9": 101, "F11": 103, "F10": 109, "F12": 111,
        "Insert": 114, "Home": 115, "PageUp": 116, "Delete": 117, "F4": 118, "End": 119, "F2": 120, "PageDown": 121,
        "F1": 122, "ArrowLeft": 123, "ArrowRight": 124, "ArrowDown": 125, "ArrowUp": 126,
    ]

    /// What the Mac's event carries for a key that types nothing.
    private static let specials: [String: Int] = [
        "Enter": 0x0D, "Tab": 0x09, "Backspace": 0x7F, "Escape": 0x1B,
        "ArrowUp": NSUpArrowFunctionKey, "ArrowDown": NSDownArrowFunctionKey, "ArrowLeft": NSLeftArrowFunctionKey,
        "ArrowRight": NSRightArrowFunctionKey, "Delete": NSDeleteFunctionKey, "Home": NSHomeFunctionKey,
        "End": NSEndFunctionKey, "PageUp": NSPageUpFunctionKey, "PageDown": NSPageDownFunctionKey,
        "Insert": NSInsertFunctionKey, "F1": NSF1FunctionKey, "F2": NSF2FunctionKey, "F3": NSF3FunctionKey,
        "F4": NSF4FunctionKey, "F5": NSF5FunctionKey, "F6": NSF6FunctionKey, "F7": NSF7FunctionKey,
        "F8": NSF8FunctionKey, "F9": NSF9FunctionKey, "F10": NSF10FunctionKey, "F11": NSF11FunctionKey,
        "F12": NSF12FunctionKey,
    ]

    private static func key(_ p: [String: Any], in page: PageView, tab: Tab) async throws -> Any {
        let type = p["type"] as? String ?? ""
        let name = p["key"] as? String ?? ""
        let code = p["code"] as? String ?? ""
        let text = p["text"] as? String ?? ""
        let modifiers = p["modifiers"] as? Int ?? 0
        let commands = (p["commands"] as? [String] ?? []).filter { !$0.isEmpty }
        if type == "char" { return try await insert(text, in: page, tab: tab) }
        // A modifier on its own changes nothing until the next key.
        if ["Shift", "Control", "Alt", "Meta", "CapsLock", "Fn"].contains(name) { return [String: Any]() }
        let web = placed(page, tab: tab)
        let id = ObjectIdentifier(web)
        let down = type == "keyDown" || type == "rawKeyDown"
        guard down || type == "keyUp" else { throw Failure(message: "Invalid type: \(type)") }

        // Editing commands (⌘A's selectAll, ⌘Z's undo): the page hears the
        // key, and what it leaves alone is done to the view, as the menu
        // would. The key itself never goes to the view, where an unused ⌘
        // key would go on to the app.
        let keyName = code + "|" + name
        if !commands.isEmpty || (!down && commanded[id]?.contains(keyName) == true) {
            let taken = try await script(Self.domKey, ["type": down ? "keydown" : "keyup", "key": name, "code": code,
                                                       "modifiers": modifiers], in: web) as? Bool ?? false
            if down {
                commanded[id, default: []].insert(keyName)
                if !taken { for command in commands { perform(command, in: web) } }
            } else {
                commanded[id]?.remove(keyName)
            }
            return [String: Any]()
        }
        // ⌘ or ⌃ with a letter and no command: the page's own shortcut. Told
        // to the page alone, never to the app.
        if modifiers & 6 != 0 {
            _ = try await script(Self.domKey, ["type": down ? "keydown" : "keyup", "key": name, "code": code,
                                               "modifiers": modifiers], in: web)
            return [String: Any]()
        }

        let special = specials[name].map { String(Character(UnicodeScalar(UInt32($0))!)) }
        let characters = !text.isEmpty ? (text == "\n" ? "\r" : text) : special ?? (name.count == 1 ? name : "")
        let bare = (p["unmodifiedText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? characters
        var keyFlags = flags(modifiers)
        if name.hasPrefix("Arrow") { keyFlags.formUnion([.numericPad, .function]) }
        else if let value = specials[name], value >= 0xF700 { keyFlags.insert(.function) }
        let keyCode = codes[code] ?? characters.first.map { Bench.keyCode(for: $0) } ?? 49
        guard let event = NSEvent.keyEvent(
            with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: keyFlags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: web.window?.windowNumber ?? 0,
            context: nil, characters: characters, charactersIgnoringModifiers: bare,
            isARepeat: p["autoRepeat"] as? Bool ?? false, keyCode: keyCode
        ) else { throw Failure(message: "Couldn't make the event") }
        if down { web.keyDown(with: event) } else { web.keyUp(with: event) }
        return [String: Any]()
    }

    /// A key told to the page alone, at what has focus. True when the page
    /// took it (prevented its default).
    private static let domKey = """
    let el = document.activeElement || document.body;
    while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement;
    const ev = new KeyboardEvent(type, { key, code, bubbles: true, cancelable: true, composed: true,
      altKey: !!(modifiers & 1), ctrlKey: !!(modifiers & 2), metaKey: !!(modifiers & 4), shiftKey: !!(modifiers & 8) });
    return !(el || document).dispatchEvent(ev);
    """

    /// One of Chrome's editing commands, done to the view: they are named
    /// as AppKit's own (selectAll, deleteWordBackward, moveToEndOfLine…).
    private static func perform(_ command: String, in web: WKWebView) {
        switch command {
        case "undo": web.undoManager?.undo()
        case "redo": web.undoManager?.redo()
        default:
            let name = command.prefix(1).lowercased() + command.dropFirst()
            let selector = NSSelectorFromString(name + ":")
            if web.responds(to: selector) { NSApp.sendAction(selector, to: web, from: nil) }
            else { web.doCommand(by: selector) }
        }
    }

    /// Text put in as typing does: through the view's text input when it has
    /// a window, or the page's own insertText otherwise.
    private static func insert(_ text: String, in page: PageView, tab: Tab) async throws -> Any {
        guard !text.isEmpty else { return [String: Any]() }
        let web = placed(page, tab: tab)
        if web.window != nil, let client = web as NSView as? NSTextInputClient {
            client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else {
            try await script("document.execCommand('insertText', false, text); return 1;", ["text": text], in: web)
        }
        return [String: Any]()
    }

    // MARK: - pictures

    private static func screenshot(_ p: [String: Any], of page: PageView, tab: Tab) async throws -> Any {
        let web = placed(page, tab: tab)
        guard let found = try await script(
            "return [innerWidth, innerHeight, scrollX, scrollY, devicePixelRatio || 1];", [:], in: web) as? [NSNumber],
              found.count == 5 else { throw Failure(message: "Unable to capture screenshot") }
        let width = found[0].doubleValue, height = found[1].doubleValue
        let scrollX = found[2].doubleValue, scrollY = found[3].doubleValue, ratio = found[4].doubleValue
        var rect = CGRect(x: 0, y: 0, width: width, height: height), scale = 1.0
        if let clip = p["clip"] as? [String: Any] {
            rect = CGRect(x: (number(clip["x"]) ?? 0) - scrollX, y: (number(clip["y"]) ?? 0) - scrollY,
                          width: number(clip["width"]) ?? width, height: number(clip["height"]) ?? height)
            scale = number(clip["scale"]) ?? 1
        }
        guard rect.width >= 1, rect.height >= 1 else { throw Failure(message: "Unable to capture screenshot") }
        let pixels = CGSize(width: max(1, (rect.width * scale * ratio).rounded()),
                            height: max(1, (rect.height * scale * ratio).rounded()))
        let z = zoom(web)
        let inView = CGRect(x: rect.minX * z, y: web.isFlipped ? rect.minY * z : web.bounds.height - rect.maxY * z,
                            width: rect.width * z, height: rect.height * z)
        let config = WKSnapshotConfiguration()
        config.rect = inView
        config.afterScreenUpdates = true
        let image: NSImage = try await withCheckedThrowingContinuation { done in
            web.takeSnapshot(with: config) { image, error in
                if let image { done.resume(returning: image) }
                else { done.resume(throwing: error ?? Failure(message: "Unable to capture screenshot")) }
            }
        }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure(message: "Unable to capture screenshot") }
        context.interpolationQuality = .high
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: pixels))
        context.draw(source, in: CGRect(origin: .zero, size: pixels))
        guard let drawn = context.makeImage() else { throw Failure(message: "Unable to capture screenshot") }
        let format = (p["format"] as? String ?? "png").lowercased()
        let quality = (number(p["quality"]) ?? 80) / 100
        let data = encode(drawn, format: format, quality: quality) ?? encode(drawn, format: "png", quality: 1)
        guard let data else { throw Failure(message: "Unable to capture screenshot") }
        return ["data": data.base64EncodedString()]
    }

    private static func encode(_ image: CGImage, format: String, quality: Double) -> Data? {
        let type: String
        switch format {
        case "jpeg", "jpg": type = "public.jpeg"
        case "webp": type = "org.webmproject.webp"
        default: type = "public.png"
        }
        let data = NSMutableData()
        guard let out = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = type == "public.png" ? [:] : [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(out, image, options as CFDictionary)
        return CGImageDestinationFinalize(out) ? data as Data : nil
    }

    // MARK: - frames

    /// The tab's main frame, named as Chrome names one: 32 hex digits, here
    /// the Chrome tab id's, so the shim names it the same way in the events
    /// it sends (ExtensionShims, `frameOf`).
    static func frameID(_ id: Int) -> String { String(format: "%032X", max(id, 0)) }

    private static func frame(_ web: WKWebView, tab: Tab, id: Int) -> [String: Any] {
        let url = web.url ?? tab.address
        let origin = url.flatMap { u in u.scheme.map { "\($0)://\(u.host() ?? "")" + (u.port.map { ":\($0)" } ?? "") } } ?? "null"
        // Changes with each document, as Chrome's loader does.
        let loader = web.backForwardList.currentItem.map { String(UInt(bitPattern: ObjectIdentifier($0).hashValue), radix: 16) } ?? "0"
        return ["id": frameID(id), "loaderId": loader.uppercased(), "url": url?.absoluteString ?? "about:blank",
                "domainAndRegistry": "", "securityOrigin": origin, "mimeType": "text/html",
                "secureContextType": url?.scheme == "https" ? "Secure" : "InsecureScheme",
                "crossOriginIsolatedContextType": "NotIsolated", "gatedAPIFeatures": [Any]()]
    }

    // MARK: - scripts

    /// A script of Quo's own in the page's world, with `values` as its
    /// arguments. Answers in JSON, so true stays true and 1 stays 1.
    @discardableResult
    private static func script(_ body: String, _ values: [String: Any], in web: WKWebView,
                               timeout: Double? = nil) async throws -> Any? {
        let wrapped = "return JSON.stringify(await (async () => {\n" + body + "\n})());"
        let run: () async throws -> Any? = {
            let raw = try await web.callAsyncJavaScript(wrapped, arguments: values, in: nil, contentWorld: .page)
            guard let text = raw as? String, let data = text.data(using: .utf8) else { return nil }
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
        guard let timeout else { return try await run() }
        // A script that never settles can't be stopped from here; its answer
        // is given up on, and the script left to the page.
        return try await withCheckedThrowingContinuation { (done: CheckedContinuation<Any?, Error>) in
            var answered = false
            let finish: (Result<Any?, Error>) -> Void = { result in
                guard !answered else { return }
                answered = true
                done.resume(with: result)
            }
            Task { @MainActor in
                do { finish(.success(try await run())) } catch { finish(.failure(error)) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(timeout))) {
                MainActor.assumeIsolated { finish(.failure(Timeout())) }
            }
        }
    }

    private struct Timeout: Error {}

    /// The page's helpers for handing out objects and describing values as
    /// Chrome does, kept on the page's window under a name nobody guesses.
    private static let kitName = "__quoDebugger" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

    private static var kitSource: String {
        "const K = (() => { const key = \(json(kitName));\n" + #"""
        if (window[key]) return window[key];
        const ids = new WeakMap(), objects = new Map();
        let next = 1;
        const put = (v) => {
          const known = (typeof v === "object" || typeof v === "function") && v !== null ? ids.get(v) : undefined;
          if (known) return known;
          const id = next++;
          objects.set(id, v);
          if ((typeof v === "object" || typeof v === "function") && v !== null) ids.set(v, id);
          return id;
        };
        const number = (id) => typeof id === "number" ? id : Number(String(id).replace(/^q:/, ""));
        const get = (id) => {
          const n = number(id);
          if (!objects.has(n)) throw new Error("Could not find object with given id");
          return objects.get(n);
        };
        const release = (id) => { const n = number(id); const v = objects.get(n); objects.delete(n); if (v && typeof v === "object") ids.delete(v); };
        const nodeText = (n) => {
          if (!(n instanceof Element)) return n.nodeName.toLowerCase();
          let s = n.localName;
          if (n.id) s += "#" + n.id;
          if (typeof n.className === "string" && n.className.trim()) s += "." + n.className.trim().split(/\s+/).join(".");
          return s;
        };
        const subtype = (v) => {
          if (v === null) return "null";
          if (typeof Node !== "undefined" && v instanceof Node) return "node";
          if (Array.isArray(v)) return "array";
          if (v instanceof Error) return "error";
          if (v instanceof Date) return "date";
          if (v instanceof RegExp) return "regexp";
          if (v instanceof Promise) return "promise";
          if (v instanceof Map) return "map";
          if (v instanceof Set) return "set";
          return undefined;
        };
        const className = (v) => { try { return (v.constructor && v.constructor.name) || "Object"; } catch (e) { return "Object"; } };
        const describe = (v) => {
          const s = subtype(v);
          if (s === "node") return nodeText(v);
          if (s === "array") return "Array(" + v.length + ")";
          if (s === "error") return String(v.name || "Error") + ": " + String(v.message || "") + (v.stack ? "\n" + v.stack : "");
          if (s === "date" || s === "regexp") return String(v);
          return className(v);
        };
        const remote = (v, byValue) => {
          const t = typeof v;
          if (t === "undefined") return { type: "undefined" };
          if (v === null) return { type: "object", subtype: "null", value: null };
          if (t === "string" || t === "boolean") return { type: t, value: v };
          if (t === "number") {
            if (!isFinite(v) || Object.is(v, -0)) return { type: t, unserializableValue: Object.is(v, -0) ? "-0" : String(v), description: String(v) };
            return { type: t, value: v, description: String(v) };
          }
          if (t === "bigint") return { type: t, unserializableValue: v + "n", description: v + "n" };
          if (t === "symbol") return { type: t, description: v.toString(), objectId: "q:" + put(v) };
          if (t === "function") {
            const d = String(v).slice(0, 2000);
            return byValue ? { type: t, className: "Function", description: d } : { type: t, className: "Function", description: d, objectId: "q:" + put(v) };
          }
          const s = subtype(v);
          if (byValue && s !== "node") {
            try {
              const out = { type: "object", value: JSON.parse(JSON.stringify(v) ?? "null") };
              if (s === "error" || s === "date" || s === "regexp") { out.subtype = s; out.className = className(v); out.description = describe(v); }
              return out;
            } catch (e) {
              return { type: "object", className: className(v), description: describe(v) };
            }
          }
          const out = { type: "object", className: className(v), description: describe(v) };
          if (s) out.subtype = s;
          if (!byValue) out.objectId = "q:" + put(v);
          return out;
        };
        const thrown = (e) => ({
          exceptionId: 1, text: "Uncaught", lineNumber: 0, columnNumber: 0, scriptId: "0",
          exception: e instanceof Error
            ? { type: "object", subtype: "error", className: className(e), description: String(e.name || "Error") + ": " + String(e.message || "") }
            : remote(e, true),
        });
        const node = (n, depth) => {
          const out = { nodeId: put(n), backendNodeId: put(n), nodeType: n.nodeType, nodeName: n.nodeName,
            localName: n.localName || "", nodeValue: n.nodeValue || "", childNodeCount: n.childNodes ? n.childNodes.length : 0 };
          if (n.attributes) { out.attributes = []; for (const a of n.attributes) out.attributes.push(a.name, a.value); }
          if (n.nodeType === 9) { out.documentURL = n.URL; out.baseURL = n.baseURI; }
          if (n.nodeType === 10) { out.publicId = n.publicId; out.systemId = n.systemId; }
          if (n.shadowRoot) out.shadowRoots = [node(n.shadowRoot, 0)];
          if (n.contentDocument) { try { out.contentDocument = node(n.contentDocument, 0); } catch (e) {} }
          if (depth !== 0 && n.childNodes) out.children = Array.from(n.childNodes, (c) => node(c, depth < 0 ? -1 : depth - 1));
          return out;
        };
        const quad = (r) => [r.left, r.top, r.right, r.top, r.right, r.bottom, r.left, r.bottom];
        const kit = { put, get, release, remote, thrown, node, quad, describe };
        Object.defineProperty(window, key, { value: kit, enumerable: false, configurable: true });
        return kit;
        })();
        """#
    }

    private static func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8) else { return "null" }
        return String(text.dropFirst().dropLast())
    }

    /// The DOM and object commands, done by the kit in the page.
    private static func kit(_ method: String, _ params: [String: Any], in web: WKWebView, frame: String) async throws -> Any {
        var body = kitSource + "\nconst P = JSON.parse(params);\n"
        body += #"""
        const target = () => P.objectId != null ? K.get(P.objectId) : K.get(P.nodeId != null ? P.nodeId : P.backendNodeId);
        const element = () => { const n = target(); if (!(n instanceof Node)) throw new Error("Could not find node with given id"); return n; };
        const box = (n) => {
          const r = n instanceof Element ? n.getBoundingClientRect() : (() => { const g = document.createRange(); g.selectNodeContents(n); return g.getBoundingClientRect(); })();
          if (!r.width && !r.height && !(n instanceof Element && n.getClientRects().length)) throw new Error("Could not compute box model.");
          return r;
        };
        switch (method) {
        case "Page.getLayoutMetrics": {
          const v = window.visualViewport, d = document.documentElement;
          const w = d.scrollWidth, h = d.scrollHeight;
          const layout = { pageX: scrollX, pageY: scrollY, clientWidth: d.clientWidth || innerWidth, clientHeight: d.clientHeight || innerHeight };
          const visual = { offsetX: v ? v.offsetLeft : 0, offsetY: v ? v.offsetTop : 0, pageX: v ? v.pageLeft : scrollX, pageY: v ? v.pageTop : scrollY,
            clientWidth: v ? v.width : innerWidth, clientHeight: v ? v.height : innerHeight, scale: v ? v.scale : 1, zoom: 1 };
          const content = { x: 0, y: 0, width: w, height: h };
          return { layoutViewport: layout, visualViewport: visual, contentSize: content,
            cssLayoutViewport: layout, cssVisualViewport: visual, cssContentSize: content };
        }
        case "Runtime.getProperties": {
          const o = K.get(P.objectId), out = [];
          if (o === null || (typeof o !== "object" && typeof o !== "function")) return { result: out };
          const names = P.ownProperties === false ? (() => { const s = new Set(); for (let p = o; p; p = Object.getPrototypeOf(p)) Object.getOwnPropertyNames(p).forEach((n) => s.add(n)); return [...s]; })() : Object.getOwnPropertyNames(o);
          for (const name of names.slice(0, 1000)) {
            const d = Object.getOwnPropertyDescriptor(o, name);
            let value; try { value = o[name]; } catch (e) { continue; }
            out.push({ name, value: K.remote(value, false), enumerable: d ? !!d.enumerable : false, configurable: d ? !!d.configurable : false,
              writable: d ? !!d.writable : false, isOwn: !!d });
          }
          return { result: out };
        }
        case "Runtime.releaseObject": K.release(P.objectId); return {};
        case "DOM.getDocument": return { root: K.node(document, P.depth == null ? 1 : P.depth) };
        case "DOM.querySelector": {
          const n = element(), found = (n.querySelector ? n : document).querySelector(P.selector);
          return { nodeId: found ? K.put(found) : 0 };
        }
        case "DOM.querySelectorAll": {
          const n = element();
          return { nodeIds: Array.from((n.querySelectorAll ? n : document).querySelectorAll(P.selector), (f) => K.put(f)) };
        }
        case "DOM.describeNode": return { node: K.node(element(), P.depth == null ? 0 : P.depth) };
        case "DOM.resolveNode": return { object: K.remote(element(), false) };
        case "DOM.requestNode": return { nodeId: K.put(element()) };
        case "DOM.getAttributes": { const n = element(), out = []; for (const a of n.attributes || []) out.push(a.name, a.value); return { attributes: out }; }
        case "DOM.getBoxModel": {
          const n = element(), r = box(n), q = K.quad(r);
          let pad = q, border = q, margin = q;
          if (n instanceof Element) {
            const s = getComputedStyle(n), px = (k) => parseFloat(s[k]) || 0;
            const inset = (r0, t, ri, b) => K.quad({ left: r.left + r0, top: r.top + t, right: r.right - ri, bottom: r.bottom - b });
            border = q;
            pad = inset(px("borderLeftWidth"), px("borderTopWidth"), px("borderRightWidth"), px("borderBottomWidth"));
            const content = inset(px("borderLeftWidth") + px("paddingLeft"), px("borderTopWidth") + px("paddingTop"),
              px("borderRightWidth") + px("paddingRight"), px("borderBottomWidth") + px("paddingBottom"));
            margin = inset(-px("marginLeft"), -px("marginTop"), -px("marginRight"), -px("marginBottom"));
            return { model: { content, padding: pad, border, margin, width: r.width, height: r.height } };
          }
          return { model: { content: q, padding: pad, border, margin, width: r.width, height: r.height } };
        }
        case "DOM.getContentQuads": {
          const n = element();
          const rects = n instanceof Element ? Array.from(n.getClientRects()) : [box(n)];
          return { quads: rects.filter((r) => r.width || r.height).map(K.quad) };
        }
        case "DOM.scrollIntoViewIfNeeded": {
          const n = element(), el = n instanceof Element ? n : n.parentElement;
          if (el) el.scrollIntoView({ block: "center", inline: "center", behavior: "instant" });
          return {};
        }
        case "DOM.focus": { const n = element(); if (typeof n.focus === "function") n.focus(); return {}; }
        case "DOM.getOuterHTML": { const n = element(); return { outerHTML: n.outerHTML != null ? n.outerHTML : new XMLSerializer().serializeToString(n) }; }
        case "DOM.setAttributeValue": element().setAttribute(P.name, P.value); return {};
        case "DOM.removeNode": element().remove(); return {};
        case "DOM.setNodeValue": element().nodeValue = P.value; return {};
        case "DOM.getNodeForLocation": {
          const n = document.elementFromPoint(P.x, P.y);
          if (!n) throw new Error("No node found at given location");
          return { backendNodeId: K.put(n), nodeId: K.put(n), frameId: frameId };
        }
        }
        throw new Error("'" + method + "' wasn't found");
        """#
        do {
            let found = try await script(body, ["method": method, "params": json(params), "frameId": frame], in: web)
            return found ?? [String: Any]()
        } catch {
            throw Failure(message: pageError(error))
        }
    }

    /// The message a script's exception carried, without WebKit's wrapping.
    private static func pageError(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        return info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
    }

    // MARK: - Runtime.evaluate and callFunctionOn

    private static func evaluate(_ p: [String: Any], in web: WKWebView) async throws -> Any {
        let expression = p["expression"] as? String ?? ""
        let byValue = p["returnByValue"] as? Bool ?? false
        switch Compiled.body(for: expression) {
        case .failure(let message):
            return ["result": ["type": "object", "subtype": "error", "className": "SyntaxError",
                               "description": "SyntaxError: " + message],
                    "exceptionDetails": ["exceptionId": 1, "text": "Uncaught", "lineNumber": 0, "columnNumber": 0,
                                         "scriptId": "1",
                                         "exception": ["type": "object", "subtype": "error", "className": "SyntaxError",
                                                       "description": "SyntaxError: " + message]]]
        case .success(let source):
            let body = kitSource + """

            try {
              const v = await (async function () {
            \(source)
            }).call(window);
              return { result: K.remote(v, byValue) };
            } catch (e) {
              return { result: K.remote(e, false), exceptionDetails: K.thrown(e) };
            }
            """
            let limit = (number(p["timeout"])).flatMap { $0 > 0 ? $0 : nil }
            do {
                return try await script(body, ["byValue": byValue], in: web, timeout: limit) ?? [String: Any]()
            } catch is Timeout {
                let gone = "Error: script execution was terminated after \(Int(limit ?? 0)) ms"
                return ["result": ["type": "object", "subtype": "error", "className": "Error", "description": gone],
                        "exceptionDetails": ["exceptionId": 1, "text": "Uncaught", "lineNumber": 0, "columnNumber": 0,
                                             "scriptId": "1", "exception": ["type": "object", "subtype": "error",
                                                                             "className": "Error", "description": gone]]]
            }
        }
    }

    // The call's function is given as source; it goes into the page as
    // source too, after the syntax is checked here, so a page's policy
    // against eval doesn't stop it.
    static func callFunctionOn(_ p: [String: Any], in web: WKWebView) async throws -> Any {
        let declaration = p["functionDeclaration"] as? String ?? ""
        if let problem = Compiled.problem("(async function(){ return (\n" + declaration + "\n); })") {
            throw Failure(message: "Given expression does not evaluate to a function: " + problem)
        }
        let body = kitSource + "\nconst P = JSON.parse(params);\n" + """
        const fn = (
        \(declaration)
        );
        if (typeof fn !== "function") throw new Error("Given expression does not evaluate to a function");
        const self = P.objectId != null ? K.get(P.objectId) : window;
        const args = (P.arguments || []).map((a) => {
          if (a.objectId != null) return K.get(a.objectId);
          if (a.unserializableValue != null) {
            const u = a.unserializableValue;
            if (u === "-0") return -0;
            if (/n$/.test(u)) return BigInt(u.slice(0, -1));
            return Number(u);
          }
          return a.value;
        });
        try {
          let v = fn.apply(self, args);
          if (P.awaitPromise) v = await v;
          return { result: K.remote(v, !!P.returnByValue) };
        } catch (e) {
          return { result: K.remote(e, false), exceptionDetails: K.thrown(e) };
        }
        """
        do {
            return try await script(body, ["params": json(p)], in: web) ?? [String: Any]()
        } catch {
            throw Failure(message: pageError(error))
        }
    }
}

// MARK: - a script's last value

/// Chrome's evaluate answers with the value of a script's last statement, and
/// lets it await at the top. WebKit runs a function's body instead, so the
/// last statement is turned into a return. Which statement is last is found
/// by asking JavaScriptCore, here in the app, whether each way of cutting the
/// script parses: no script of the page's is run to find out.
@MainActor
enum Compiled {
    enum Body { case success(String), failure(String) }

    private static let context = JSContext()!

    /// Nil when `source` parses as a script, or what's wrong with it.
    static func problem(_ source: String) -> String? {
        let text = JSStringCreateWithCFString(source as CFString)
        defer { JSStringRelease(text) }
        var exception: JSValueRef?
        if JSCheckScriptSyntax(context.jsGlobalContextRef, text, nil, 1, &exception) { return nil }
        guard let exception else { return "Unexpected token" }
        let message = JSValue(jsValueRef: exception, in: context)?.forProperty("message")?.toString()
        return message ?? "Unexpected token"
    }

    private static func parses(_ body: String) -> Bool {
        problem("(async function(){\n" + body + "\n})") == nil
    }

    /// The body of an async function that does what `expression` does and
    /// returns what Chrome's evaluate would answer with.
    static func body(for expression: String) -> Body {
        var code = expression
        guard parses(code) else {
            return .failure(problem("(async function(){\n" + code + "\n})") ?? "Unexpected token")
        }
        // One block around it all, as some extensions send: its inside.
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
            let inside = String(trimmed.dropFirst().dropLast())
            if parses(inside), !parses("{" + inside) { code = inside }
        }
        return .success(returning(code) ?? code)
    }

    /// Chars that, starting a line, carry on the line before rather than
    /// begin a statement of their own.
    private static let continuing = Set("([+-*/%.,?:=<>&|^`")

    /// `code` with its last statement returned, when one can be found.
    static func returning(_ code: String) -> String? {
        let chars = Array(code)
        var tries = 0
        var index = chars.count
        while index >= 0, tries < 200 {
            defer { index -= 1 }
            guard index == 0 || [";", "\n", "}"].contains(chars[index - 1]) else { continue }
            var suffix = String(chars[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
            while suffix.hasSuffix(";") { suffix = String(suffix.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !suffix.isEmpty else { continue }
            let prefix = String(chars[..<index])
            if index > 0 {
                // Cut where a statement ends, not inside one that runs on.
                let before = prefix.trimmingCharacters(in: .whitespacesAndNewlines).last
                if before != ";", let first = suffix.first, continuing.contains(first) { continue }
                if before != ";", suffix.hasPrefix("in ") || suffix.hasPrefix("instanceof ") { continue }
            }
            tries += 1
            if index > 0 {
                guard parses(prefix) else { continue }
                // The cut isn't inside a line comment: there, this parses too.
                if parses(prefix + " @@") { continue }
            }
            let candidate = prefix + "\nreturn (\n" + suffix + "\n);"
            if parses(candidate) { return candidate }
        }
        return nil
    }
}
