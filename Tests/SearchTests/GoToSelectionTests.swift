import AppKit
import XCTest
@testable import Search

/// Go to … in a page's menu (PageView.address): the words WebKit's Look Up
/// item names, when they are an address the field would take.
@MainActor
final class GoToSelectionTests: XCTestCase {
    private func menu(_ title: String) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        return menu
    }

    func testAnAddressIsOffered() {
        XCTAssertEqual(PageView.address(in: menu("Look Up “razegrowth.com”"))?.absoluteString, "https://razegrowth.com")
        XCTAssertEqual(PageView.address(in: menu("Look Up “https://example.org/a?b=1”"))?.absoluteString, "https://example.org/a?b=1")
        XCTAssertEqual(PageView.address(in: menu("Look Up “localhost:3000”"))?.absoluteString, "http://localhost:3000")
    }

    func testWordsThatAreNotOneAreNot() {
        XCTAssertNil(PageView.address(in: menu("Look Up “hello world”")))
        XCTAssertNil(PageView.address(in: menu("Look Up “todo”")))
        XCTAssertNil(PageView.address(in: menu("Look Up “ed@razegrowth.com”")))
        XCTAssertNil(PageView.address(in: menu("Look Up “a very long selection that was cut short…”")))
        XCTAssertNil(PageView.address(in: menu("Copy")))
    }

    func testTheItemSaysItShort() {
        XCTAssertEqual(PageView.shown(URL(string: "https://razegrowth.com/")!), "razegrowth.com")
        XCTAssertEqual(PageView.shown(URL(string: "https://razegrowth.com/blog/x")!), "razegrowth.com/blog/x")
    }
}
