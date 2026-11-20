import XCTest
@testable import Search

/// Extensions that slow pages down (SlowExtensions): which new installs
/// start On click, and the quarter of an hour their cost is counted over.
@MainActor
final class SlowExtensionsTests: XCTestCase {
    private func manifest(button: Bool = true, matches: [String] = ["<all_urls>"], permissions: [String] = []) -> [String: Any] {
        var manifest: [String: Any] = ["manifest_version": 3, "content_scripts": [["matches": matches, "js": ["c.js"]]]]
        if button { manifest["action"] = ["default_title": "Go"] }
        if !permissions.isEmpty { manifest["permissions"] = permissions }
        return manifest
    }

    func testToolsStartOnClick() {
        XCTAssertTrue(SlowExtensions.startsOnClick(manifest: manifest(), name: "Fonts Ninja", about: "Identify fonts on any website"))
        XCTAssertTrue(SlowExtensions.startsOnClick(manifest: manifest(), name: "Ahrefs SEO Toolbar", about: ""))
        XCTAssertTrue(SlowExtensions.startsOnClick(manifest: manifest(matches: ["https://*/*"]), name: "ColorZilla",
                                                   about: "Advanced eyedropper, color picker"))
        // A Manifest 2 button counts as one.
        var old = manifest(button: false)
        old["browser_action"] = ["default_title": "Go"]
        XCTAssertTrue(SlowExtensions.startsOnClick(manifest: old, name: "Page Ruler", about: ""))
    }

    func testWhatWorksInEveryPageStaysOn() {
        // Blocking requests, dark mode, translation, writing aids: their work
        // is in the page, without a click.
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(permissions: ["declarativeNetRequest"]),
                                                    name: "SEO Blocker", about: ""))
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(), name: "Dark Reader", about: "Dark mode for every website"))
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(), name: "Grammarly", about: "Grammar checker and keyword tips"))
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(), name: "Font Translator", about: ""))
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(), name: "1Password", about: "Password manager font"))
    }

    func testNeedsAButtonAndScriptsEverywhere() {
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(button: false), name: "Fonts Ninja", about: ""))
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(matches: ["https://example.com/*"]), name: "Fonts Ninja", about: ""))
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: ["manifest_version": 3, "action": [:]], name: "Fonts Ninja", about: ""))
        // A name that says nothing of tools: left as it comes.
        XCTAssertFalse(SlowExtensions.startsOnClick(manifest: manifest(), name: "Pointer Watcher", about: ""))
    }

    func testCostIsCountedOverAQuarterOfAnHour() {
        let slow = SlowExtensions()
        let start = Date(timeIntervalSince1970: 1_000_000)
        slow.noted(800, for: "a", at: start)
        slow.noted(700, for: "a", at: start.addingTimeInterval(60))
        slow.noted(-5, for: "a", at: start.addingTimeInterval(61))
        slow.noted(.nan, for: "a", at: start.addingTimeInterval(62))
        XCTAssertEqual(slow.cost(of: "a", at: start.addingTimeInterval(120)), 1500)
        XCTAssertEqual(slow.cost(of: "b", at: start), 0)
        // The first report falls out of the window, the second not yet.
        XCTAssertEqual(slow.cost(of: "a", at: start.addingTimeInterval(SlowExtensions.window + 1)), 700)
        XCTAssertEqual(slow.cost(of: "a", at: start.addingTimeInterval(SlowExtensions.window + 61)), 0)
        // One report counts at most a minute, however long it claims.
        slow.noted(10_000_000, for: "c", at: start)
        XCTAssertEqual(slow.cost(of: "c", at: start), 60_000)
    }

    func testCardSaysSecondsAndMinutes() {
        XCTAssertEqual(SlowExtensionCard.seconds(2.44), "2.4 seconds")
        XCTAssertEqual(SlowExtensionCard.seconds(42), "42 seconds")
        XCTAssertEqual(SlowExtensionCard.seconds(65), "1 minute 5 seconds")
        XCTAssertEqual(SlowExtensionCard.seconds(130), "2 minutes 10 seconds")
    }
}
