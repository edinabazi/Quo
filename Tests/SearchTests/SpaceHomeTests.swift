import XCTest
@testable import Search

/// An empty tab's home (SpaceHome.swift): the sites' names on its tiles, and
/// its greeting.
final class SpaceHomeTests: XCTestCase {
    private func name(_ host: String, _ title: String) -> String {
        History.Site(host: host, url: URL(string: "https://\(host)/")!, title: title).name
    }

    func testSiteNamesFromTitles() {
        XCTAssertEqual(name("github.com", "GitHub"), "GitHub")
        XCTAssertEqual(name("mail.google.com", "Inbox (3) - me@example.com - Gmail"), "Gmail")
        XCTAssertEqual(name("notion.so", "Notion – Home"), "Notion")
        XCTAssertEqual(name("x.com", "Home / X"), "X")
        XCTAssertEqual(name("linear.app", "My issues · Linear"), "Linear")
        XCTAssertEqual(name("news.ycombinator.com", "Hacker News"), "Hacker News")
        // No title, or one too long to be a name: the address.
        XCTAssertEqual(name("figma.com", ""), "Figma")
        XCTAssertEqual(name("docs.example.org", ""), "docs.example.org")
        XCTAssertEqual(name("example.com", "A very long article title that goes on and on"), "Example")
    }

    @MainActor
    func testGreetingFollowsTheHour() {
        func at(_ hour: Int) -> Date { Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())! }
        XCTAssertEqual(SpaceHomeHeader.greeting(at: at(9), name: "Edin"), "Good morning, Edin")
        XCTAssertEqual(SpaceHomeHeader.greeting(at: at(14), name: nil), "Good afternoon")
        XCTAssertEqual(SpaceHomeHeader.greeting(at: at(19), name: ""), "Good evening")
        XCTAssertEqual(SpaceHomeHeader.greeting(at: at(2), name: "Edin"), "Up late, Edin")
    }
}
