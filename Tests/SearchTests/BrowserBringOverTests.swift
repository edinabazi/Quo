import Foundation
import XCTest
@testable import Search

/// Bringing things over from a Mac with one browser, its profiles and its
/// extensions: every browser's data made up here, never a real one's.
final class BrowserBringOverTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "browser-import-\(ProcessInfo.processInfo.processIdentifier)", 1)
        super.setUp()
    }

    private var folders: [URL] = []

    override func tearDown() {
        for folder in folders {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        folders = []
        super.tearDown()
    }

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func json(_ object: Any) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    // MARK: - one browser on the Mac

    /// Chrome alone, with only "Profile 1" — its Default deleted — is a
    /// browser to bring from, named as Chrome names the profile.
    func testChromeAloneWithOnlyProfileOneIsOffered() throws {
        let root = try root()
        try write("", to: root.appendingPathComponent("Profile 1/History"))
        try write(json(["profile": ["info_cache": ["Profile 1": ["name": "Work"]], "last_used": "Profile 1"]]),
                  to: root.appendingPathComponent("Local State"))
        let chrome = try XCTUnwrap(Chromium.known.first { $0.name == "Chrome" })
        var source = chrome
        source.rootOverride = root
        XCTAssertEqual(source.profiles.map(\.lastPathComponent), ["Profile 1"])
        let offered = ImportSource.chromium(source)
        XCTAssertEqual(offered.profiles.map(\.name), ["Work"])
        XCTAssertEqual(offered.usual, "Profile 1")
        XCTAssertEqual(offered.firstProfile, "Profile 1")
        XCTAssertTrue(Chromium.unreadable(among: [source], installed: { _ in true }).isEmpty)
    }

    /// The friend's Mac: Chrome's folder is there but macOS won't let it be
    /// listed. That is a browser on this Mac, refused, never "none found" —
    /// whether or not its app is in /Applications.
    func testRefusedChromeFolderIsOfferedAsRefusedNotMissing() throws {
        let root = try root()
        try write("{}", to: root.appendingPathComponent("Default/Bookmarks"))
        var source = try XCTUnwrap(Chromium.known.first { $0.name == "Chrome" })
        source.rootOverride = root
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: root.path)

        XCTAssertTrue(source.profiles.isEmpty)
        let refused = Chromium.unreadable(among: [source], installed: { _ in false })
        XCTAssertEqual(refused.map(\.source.name), ["Chrome"])
        XCTAssertTrue(refused[0].message.contains("Chrome is on this Mac"), refused[0].message)
        XCTAssertTrue(refused[0].message.contains("until you allow"), refused[0].message)

        // Allowed again, it reads.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        XCTAssertEqual(source.profiles.map(\.lastPathComponent), ["Default"])
        XCTAssertTrue(Chromium.unreadable(among: [source], installed: { _ in false }).isEmpty)
    }

    /// No folder and no app: nothing to say.
    func testMissingBrowserWithoutAppIsNotMentioned() throws {
        var source = try XCTUnwrap(Chromium.known.first { $0.name == "Chrome" })
        source.rootOverride = try root().appendingPathComponent("missing")
        XCTAssertTrue(Chromium.unreadable(among: [source], installed: { _ in false }).isEmpty)
        XCTAssertEqual(Chromium.unreadable(among: [source], installed: { _ in true }).count, 1)
    }

    /// Every Chromium browser the import knows is found the same way, from
    /// a Profile 1 alone or, as Opera keeps it, from the folder itself.
    func testEveryKnownChromiumBrowserIsFoundFromAnyProfileFolder() throws {
        for known in Chromium.known {
            for layout in ["Profile 1/History", "Profile 3/Bookmarks", "Default/Login Data", "History"] {
                let root = try root()
                try write("", to: root.appendingPathComponent(layout))
                var source = known
                source.rootOverride = root
                XCTAssertFalse(source.profiles.isEmpty, "\(known.name) with \(layout)")
                XCTAssertFalse(ImportSource.chromium(source).profiles.isEmpty, "\(known.name) with \(layout)")
            }
        }
    }

    // MARK: - extensions

    func testChromiumExtensionsComeWithNamesAndTheRestSayWhy() throws {
        let root = try root()
        let profile = root.appendingPathComponent("Default")
        let store = "cjpalhdlnbpafiamejdnhcphjbkeiagm"   // made up in the store's shape
        let localized = "aeblfdkhhhdcdjpifhhbdiojplfjncoa"
        let theme = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        let off = "cccccccccccccccccccccccccccccccc"
        let builtIn = "dddddddddddddddddddddddddddddddd"
        let unpacked = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        let policy = "ffffffffffffffffffffffffffffffff"
        let edge = "gggggggggggggggggggggggggggggggg"
        let defaulted = "hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh"
        let google = "https://clients2.google.com/service/update2/crx"
        let settings: [String: Any] = [
            store: ["location": 1, "from_webstore": true, "manifest": ["name": "uBlock Origin Lite", "version": "2025.1", "update_url": google]],
            // No manifest kept in the settings, as newer Chrome does: read from its folder.
            localized: ["location": 1, "from_webstore": true],
            theme: ["location": 1, "manifest": ["name": "Just Black", "version": "3", "theme": [:], "update_url": google]],
            off: ["location": 1, "disable_reasons": [1], "manifest": ["name": "Old Helper", "version": "1", "update_url": google]],
            builtIn: ["location": 5, "manifest": ["name": "Chrome PDF Viewer", "version": "1"]],
            unpacked: ["location": 4, "path": "/Users/someone/dev/ext", "manifest": ["name": "My Dev Thing", "version": "0.1"]],
            policy: ["location": 9, "manifest": ["name": "Work Guard", "version": "4", "update_url": google]],
            edge: ["location": 1, "manifest": ["name": "Edge Only", "version": "1", "update_url": "https://edge.microsoft.com/extensionwebstorebase/v1/crx"]],
            defaulted: ["location": 1, "was_installed_by_default": true, "manifest": ["name": "Docs Offline", "version": "1", "update_url": google]],
        ]
        try write(json(["extensions": ["settings": settings]]), to: profile.appendingPathComponent("Secure Preferences"))
        let folder = profile.appendingPathComponent("Extensions/\(localized)/5.2.1_0")
        try write(json(["name": "__MSG_appName__", "version": "5.2.1", "default_locale": "en", "update_url": google]),
                  to: folder.appendingPathComponent("manifest.json"))
        try write(json(["appName": ["message": "Dark Reader"]]), to: folder.appendingPathComponent("_locales/en/messages.json"))

        var source = Chromium.Source(name: "Chrome", folder: "", service: "", account: "", app: "")
        source.rootOverride = root
        let addons = Chromium.addons(in: source, profile: nil)
        let by = Dictionary(uniqueKeysWithValues: addons.map { ($0.id, $0) })

        XCTAssertEqual(Set(Chromium.extensions(in: source, profile: nil)), [store, localized])
        XCTAssertEqual(by[store]?.name, "uBlock Origin Lite")
        XCTAssertEqual(by[localized]?.name, "Dark Reader")
        XCTAssertEqual(by[localized]?.version, "5.2.1")
        XCTAssertEqual(by[theme]?.skip, "a theme")
        XCTAssertEqual(by[off]?.skip, "turned off in Chrome")
        XCTAssertEqual(by[builtIn]?.builtIn, true)
        XCTAssertEqual(by[defaulted]?.builtIn, true)
        XCTAssertTrue(by[unpacked]?.skip?.contains("loaded from a folder") == true)
        XCTAssertEqual(by[policy]?.skip, "put there by a policy")
        XCTAssertTrue(by[edge]?.skip?.contains("edge.microsoft.com") == true)

        let preview = Chromium.preview(of: source, profile: nil)
        XCTAssertEqual(Set(preview.extensions), [store, localized])
        // The browser's own aren't listed as left behind; the rest are, with why.
        XCTAssertEqual(Set(preview.leftBehind.map(\.id)), [theme, off, unpacked, policy, edge])
        // The ones that come lead.
        XCTAssertEqual(Set(addons.prefix(2).map(\.id)), [store, localized])
    }

    /// Two profiles with the same extension: one of it, from both.
    func testExtensionsFromEveryProfileComeOnce() throws {
        let root = try root()
        let id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"
        for name in ["Default", "Profile 1"] {
            try write(json(["extensions": ["settings": [id: ["location": 1, "from_webstore": true,
                                                             "manifest": ["name": "One", "version": "1"]]]]]),
                      to: root.appendingPathComponent("\(name)/Preferences"))
            try write("{}", to: root.appendingPathComponent("\(name)/Bookmarks"))
        }
        var source = Chromium.Source(name: "Dia", folder: "", service: "", account: "", app: "")
        source.rootOverride = root
        XCTAssertEqual(Chromium.extensions(in: source, profile: nil), [id])
        XCTAssertEqual(Chromium.extensions(in: source, profile: "Profile 1"), [id])
    }

    func testFirefoxAddOnsAreListedToLookForNeverInstalled() throws {
        let base = Chromium.base
        let folder = "fixture-\(UUID().uuidString)"
        folders.append(base.appendingPathComponent(folder))
        let profile = base.appendingPathComponent("\(folder)/Profiles/abcd.default-release")
        try write("", to: profile.appendingPathComponent("places.sqlite"))
        try write(json(["addons": [
            ["id": "uBlock0@raymondhill.net", "type": "extension", "location": "app-profile", "active": true,
             "version": "1.60", "defaultLocale": ["name": "uBlock Origin"]],
            ["id": "off@example", "type": "extension", "location": "app-profile", "active": false, "userDisabled": true,
             "defaultLocale": ["name": "Turned Off"]],
            ["id": "theme@example", "type": "theme", "location": "app-profile", "active": true, "defaultLocale": ["name": "Dark"]],
            ["id": "screenshots@mozilla.org", "type": "extension", "location": "app-system-defaults", "active": true,
             "defaultLocale": ["name": "Screenshots"]],
        ]]), to: profile.appendingPathComponent("extensions.json"))

        let source = Mozilla.Source(name: "Firefox", folders: ["\(folder)/Profiles"])
        let addons = Mozilla.addons(in: source, profile: nil)
        XCTAssertEqual(addons.map(\.name), ["uBlock Origin"])
        XCTAssertEqual(addons.first?.lookFor, true)
        XCTAssertFalse(addons.first?.comes ?? true)
        XCTAssertEqual(addons.first?.search?.absoluteString, "https://chromewebstore.google.com/search/uBlock%20Origin")
        let preview = Mozilla.preview(of: source, profile: nil)
        XCTAssertTrue(preview.extensions.isEmpty)
        XCTAssertEqual(preview.leftBehind.map(\.name), ["uBlock Origin"])
    }

    func testSafariExtensionsAreReadFromPluginkitsListing() {
        let listing = """
        +    com.bitwarden.desktop.safari(2025.1.0)\t1A2B\t2026-01-01 10:00:00 +0000\t/Applications/Bitwarden.app/Contents/PlugIns/safari.appex
        -    com.example.off(1.0)\t3C4D\t2026-01-01 10:00:00 +0000\t/Applications/Off.app/Contents/PlugIns/off.appex
             com.example.named(2.0)\t5E6F\t2026-01-01 10:00:00 +0000\t/Applications/Named.app/Contents/PlugIns/n.appex

        """
        let addons = ImportSource.safariAddons(listing: listing) { path in path.contains("Named") ? "Named Helper" : nil }
        XCTAssertEqual(addons.map(\.name), ["Bitwarden", "Named Helper"])
        XCTAssertEqual(addons.first?.version, "2025.1.0")
        XCTAssertTrue(addons.allSatisfy { $0.lookFor && !$0.comes })
    }

    func testAddonNamesReadShort() {
        let addons = ["A", "B", "C", "D", "E"].map { ImportSource.Addon(id: $0, name: $0, version: "", skip: nil) }
        XCTAssertEqual(ImportSource.Addon.names(Array(addons.prefix(2))), ListFormatter.localizedString(byJoining: ["A", "B"]))
        XCTAssertEqual(ImportSource.Addon.names(Array(addons.prefix(4))), ListFormatter.localizedString(byJoining: ["A", "B", "C", "D"]))
        XCTAssertEqual(ImportSource.Addon.names(addons), "A, B, C and 2 more")
    }
}
