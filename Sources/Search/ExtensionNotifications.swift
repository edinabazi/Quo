import AppKit
import UserNotifications
import WebKit

// chrome.notifications, as Chrome has it.
//
// WebKit has no chrome.notifications, so the shim's calls come here and an
// extension's notification is posted as a Mac notification. Its buttons (two
// at most, as in Chrome) are the notification's actions, under Options: a
// category for each set of button titles an extension uses, kept beside the
// ones Search already has — the site category, for one (see
// NotificationCategories).
//
// What is done with it comes back to the extension as Chrome tells it: a
// click as onClicked, a button as onButtonClicked, a dismissal as onClosed.
// WebKit has no way for Search to raise an event in an extension, so the
// shim, while it listens, opens a port here as it does for tab groups and
// idleness (ExtensionWatch), and the news is said on it. A worker is
// usually asleep by the time anyone clicks: the news waits, the worker is
// woken, and its shim hears what it missed as its port opens. Each piece of
// news is said until the extension's background says it has it, and no
// longer than a few minutes.
//
// A test run posts nothing, as for sites (SiteNotifications): it keeps what
// it would have posted, for the bench.

@available(macOS 15.4, *)
@MainActor
enum ExtensionNotifications {
    static let port = ExtensionShims.application + ".notifications"
    /// The kind written in a notification's info, read when it is answered.
    nonisolated static let kind = "extension"

    /// What a test run would have posted, newest last.
    private(set) static var recorded: [[String: Any]] = []

    // MARK: - posting

    /// Each notification's options as last posted, for update(): Chrome
    /// keeps what an update leaves out.
    private static var shown: [String: [String: Any]] = [:]

    static func identifier(_ extensionID: String, _ key: String) -> String { "\(extensionID).\(key)" }

    /// The button titles an extension's options give, as Chrome takes them:
    /// the first two.
    nonisolated static func buttons(_ options: [String: Any]) -> [String] {
        (options["buttons"] as? [Any] ?? []).prefix(2).map { ($0 as? [String: Any])?["title"] as? String ?? "" }
    }

    /// One category per extension and set of buttons, named the same from
    /// one launch to the next: a notification still in Notification Centre
    /// after a restart keeps its buttons.
    nonisolated static func categoryIdentifier(_ extensionID: String, buttons: [String]) -> String {
        guard !buttons.isEmpty else { return "ext.\(extensionID)" }
        // FNV-1a: Swift's own hash changes with every launch.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in buttons.joined(separator: "\u{1F}").utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "ext.\(extensionID).\(String(hash, radix: 16))"
    }

    nonisolated static func category(_ extensionID: String, buttons: [String]) -> UNNotificationCategory {
        let actions = buttons.enumerated().map { index, title in
            UNNotificationAction(identifier: "button.\(index)", title: title, options: [])
        }
        return UNNotificationCategory(identifier: categoryIdentifier(extensionID, buttons: buttons), actions: actions,
                                      intentIdentifiers: [], options: [.customDismissAction])
    }

    /// What the Mac shows for an extension's options: Chrome's title,
    /// message and context line become the title, body and subtitle, and
    /// the extension's name stands in for a missing context line.
    nonisolated static func content(_ options: [String: Any], extensionID: String, key: String, name: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = options["title"] as? String ?? name
        content.body = options["message"] as? String ?? ""
        let context = options["contextMessage"] as? String ?? ""
        content.subtitle = context.isEmpty ? name : context
        content.threadIdentifier = "ext.\(extensionID)"
        content.categoryIdentifier = categoryIdentifier(extensionID, buttons: buttons(options))
        content.userInfo = ["search.kind": kind, "search.extension": extensionID, "search.key": key]
        if options["silent"] as? Bool != true { content.sound = .default }
        return content
    }

    /// notifications.create: posted, and its key given back.
    static func create(_ key: String, options: [String: Any], context: WKWebExtensionContext) async -> String {
        let id = context.uniqueIdentifier
        shown[identifier(id, key)] = options
        await post(key, options: options, context: context)
        return key
    }

    /// notifications.update: only one still showing, with what is given
    /// laid over what it had.
    static func update(_ key: String, options: [String: Any], context: WKWebExtensionContext) async -> Bool {
        let id = context.uniqueIdentifier, name = identifier(id, key)
        guard !Store.testing else {
            guard var old = shown[name] else { return false }
            old.merge(options) { $1 }
            shown[name] = old
            recorded.append(["key": key, "extension": id, "updated": true])
            return true
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        guard delivered.contains(where: { $0.request.identifier == name }) else { return false }
        var merged = shown[name] ?? [:]
        merged.merge(options) { $1 }
        shown[name] = merged
        await post(key, options: merged, context: context)
        return true
    }

    /// notifications.getAll: those of this extension still showing.
    static func all(_ context: WKWebExtensionContext) async -> [String: Any] {
        let id = context.uniqueIdentifier
        guard !Store.testing else {
            return Dictionary(shown.keys.filter { $0.hasPrefix(id + ".") }.map { (String($0.dropFirst(id.count + 1)), true as Any) }) { a, _ in a }
        }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        var out: [String: Any] = [:]
        for note in delivered {
            let info = note.request.content.userInfo
            guard info["search.kind"] as? String == kind, info["search.extension"] as? String == id,
                  let key = info["search.key"] as? String else { continue }
            out[key] = true
        }
        return out
    }

    static func clear(_ key: String, context: WKWebExtensionContext) {
        let name = identifier(context.uniqueIdentifier, key)
        shown[name] = nil
        guard !Store.testing else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [name])
    }

    private static func post(_ key: String, options: [String: Any], context: WKWebExtensionContext) async {
        let id = context.uniqueIdentifier
        let name = context.webExtension.displayName ?? ""
        let content = content(options, extensionID: id, key: key, name: name)
        guard !Store.testing else {
            recorded.append(["key": key, "extension": id, "title": content.title, "body": content.body,
                             "subtitle": content.subtitle, "category": content.categoryIdentifier, "buttons": buttons(options)])
            return
        }
        // Answers come to Search's delegate even if no site was ever allowed.
        SiteNotifications.shared.listen()
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await NotificationCategories.add(category(id, buttons: buttons(options)))
        try? await center.add(UNNotificationRequest(identifier: identifier(id, key), content: content, trigger: nil))
    }

    // MARK: - answered

    /// An answer to a notification, if it was an extension's: told to that
    /// extension. False for anyone else's.
    static func answered(_ info: [AnyHashable: Any], action: String) -> Bool {
        guard info["search.kind"] as? String == kind, let extensionID = info["search.extension"] as? String,
              let key = info["search.key"] as? String else { return false }
        guard let news = news(for: action, key: key) else { return true }
        if news["event"] as? String != "button" { shown[identifier(extensionID, key)] = nil }
        tell(news, to: extensionID)
        return true
    }

    /// What Chrome would tell for an action on the Mac's notification.
    nonisolated static func news(for action: String, key: String) -> [String: Any]? {
        switch action {
        case UNNotificationDefaultActionIdentifier: return ["event": "clicked", "key": key]
        case UNNotificationDismissActionIdentifier: return ["event": "closed", "key": key, "byUser": true]
        default:
            guard action.hasPrefix("button."), let index = Int(action.dropFirst("button.".count)) else { return nil }
            return ["event": "button", "key": key, "index": index]
        }
    }

    private struct Pending {
        let id: String
        let news: [String: Any]
        let at: Date
    }

    /// What each extension has yet to say it has heard.
    private static var pending: [String: [Pending]] = [:]
    private static var ears: [ObjectIdentifier: ExtensionEar] = [:]
    /// Extensions being reminded, so there is one reminder at a time.
    private static var reminding: Set<String> = []
    private static let keptFor: TimeInterval = 300

    /// What is waiting, for the bench.
    static var status: [String: Any] {
        ["ports": ears.count, "pending": pending.mapValues(\.count)]
    }

    /// News for an extension: said now to whatever of it listens, and its
    /// background woken to hear it if it isn't up.
    static func tell(_ news: [String: Any], to extensionID: String) {
        var news = news
        let id = UUID().uuidString
        news["id"] = id
        var list = (pending[extensionID] ?? []).filter { Date().timeIntervalSince($0.at) < keptFor }
        list.append(Pending(id: id, news: news, at: Date()))
        pending[extensionID] = Array(list.suffix(50))
        say(to: extensionID)
        remind(extensionID, round: 0)
    }

    private static func waiting(_ extensionID: String) -> [[String: Any]] {
        (pending[extensionID] ?? []).filter { Date().timeIntervalSince($0.at) < keptFor }.map(\.news)
    }

    private static func say(to extensionID: String) {
        sweep()
        let news = waiting(extensionID)
        guard !news.isEmpty else { return }
        for ear in ears.values where ear.extensionID == extensionID { ear.say(["events": news]) }
    }

    /// Woken, and told again, until the background says it heard: a worker
    /// can be gone though its port looks open, and an extension still
    /// loading has no worker yet.
    private static func remind(_ extensionID: String, round: Int) {
        if round == 0 {
            guard !reminding.contains(extensionID) else { return wake(extensionID) }
            reminding.insert(extensionID)
        } else {
            say(to: extensionID)
        }
        wake(extensionID)
        guard round < 20, !waiting(extensionID).isEmpty else {
            reminding.remove(extensionID)
            if waiting(extensionID).isEmpty { pending[extensionID] = nil }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (round < 5 ? 1 : 3)) {
            MainActor.assumeIsolated { remind(extensionID, round: round + 1) }
        }
    }

    /// The background started, if it isn't running: WebKit does nothing
    /// for one that is.
    private static func wake(_ extensionID: String) {
        guard !Store.testing, let context = Extensions.shared.contexts[extensionID], context.isLoaded,
              context.webExtension.hasBackgroundContent else { return }
        context.loadBackgroundContent { _ in }
    }

    // MARK: - the port

    /// A port the shim opened to hear of its notifications. Only for an
    /// extension that asked for them.
    static func connect(_ port: WKWebExtension.MessagePort, from context: WKWebExtensionContext) throws {
        let id = context.uniqueIdentifier
        guard ExtensionShims.allowed(id, context: context).contains("notifications") else {
            throw ExtensionShims.Unsupported(what: "The extension never asked for \u{201C}notifications\u{201D}")
        }
        sweep()
        let ear = ExtensionEar(
            extensionID: id,
            say: { message in if !port.isDisconnected { port.sendMessage(message, completionHandler: nil) } },
            hears: { !port.isDisconnected },
            close: {
                port.messageHandler = nil
                port.disconnectHandler = nil
                if !port.isDisconnected { port.disconnect() }
            })
        ears[ObjectIdentifier(ear)] = ear
        port.messageHandler = { message, _ in
            MainActor.assumeIsolated {
                guard let message = message as? [String: Any] else { return }
                if let heard = message["ack"] as? [String] {
                    pending[id]?.removeAll { heard.contains($0.id) }
                    if pending[id]?.isEmpty == true { pending[id] = nil }
                    return
                }
                guard message["listen"] as? Bool == true else { return }
                ear.worker = message["worker"] as? Bool == true
                // What it missed while it slept comes with the answer.
                ear.say(["listening": true, "events": waiting(id)])
            }
        }
        port.disconnectHandler = { _ in
            MainActor.assumeIsolated { release(ear) }
        }
        ear.say(["ready": true])
    }

    private static func release(_ ear: ExtensionEar) {
        ears[ObjectIdentifier(ear)] = nil
        ear.close()
    }

    private static func sweep() {
        for ear in ears.values where !ear.hears() { release(ear) }
    }

    /// A worker's ports go with it (see ExtensionWatch.workerGone).
    static func workerGone(of extensionID: String) {
        for ear in ears.values where ear.worker && ear.extensionID == extensionID { release(ear) }
    }
}

/// The Mac's notification categories, Search's and its extensions', set
/// together: setting them replaces every one set before.
@MainActor
enum NotificationCategories {
    private static var known: [String: UNNotificationCategory]?

    static func add(_ category: UNNotificationCategory) async {
        let center = UNUserNotificationCenter.current()
        if known == nil {
            // Those set in an earlier launch, kept by the Mac.
            let earlier = await center.notificationCategories()
            if known == nil { known = Dictionary(earlier.map { ($0.identifier, $0) }) { a, _ in a } }
        }
        guard known?[category.identifier] != category else { return }
        known?[category.identifier] = category
        center.setNotificationCategories(Set(known?.values.map { $0 } ?? []))
        // Read back, so a notification posted next finds its buttons.
        _ = await center.notificationCategories()
    }
}
