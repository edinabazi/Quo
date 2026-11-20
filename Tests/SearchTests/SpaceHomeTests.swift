import XCTest
@testable import Search

/// An empty tab's home (SpaceHome.swift): the sites' names in its list, and
/// the day under its title.
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

    func testTheDayIsWrittenOut() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 20; parts.hour = 12
        let day = SpaceHomeHeader.day(Calendar.current.date(from: parts)!)
        XCTAssertTrue(day.contains("20") && day.contains("November") && day.contains("Friday"), day)
    }
}
