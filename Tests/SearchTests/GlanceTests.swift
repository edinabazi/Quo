import XCTest
@testable import Search

/// What a pinned calendar and inbox say (Glance.swift): the countdown, the
/// call to join, the unread count, and Gmail's feed read to its mail.
@MainActor
final class GlanceTests: XCTestCase {
    private func meeting(in minutes: Double, for length: Double = 30, link: String? = nil) -> Meetings.Meeting {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = now.addingTimeInterval(minutes * 60)
        return Meetings.Meeting(id: "m", title: "Standup", start: start, end: start.addingTimeInterval(length * 60),
                                join: link.flatMap(URL.init(string:)), colour: nil)
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testCountdownWithinTheHour() {
        XCTAssertEqual(Meetings.countdown(to: meeting(in: 30), now: now), "30m")
        XCTAssertEqual(Meetings.countdown(to: meeting(in: 0.5), now: now), "1m")
        XCTAssertEqual(Meetings.countdown(to: meeting(in: 60), now: now), "60m")
        XCTAssertNil(Meetings.countdown(to: meeting(in: 61), now: now))
        XCTAssertEqual(Meetings.countdown(to: meeting(in: -10), now: now), "now")
        XCTAssertNil(Meetings.countdown(to: meeting(in: -40), now: now), "over")
    }

    func testCallsFoundInWhatAnEventSays() {
        XCTAssertEqual(Meetings.joinLink(in: "Join: https://meet.google.com/abc-defg-hij\nDial in…")?.host(), "meet.google.com")
        XCTAssertEqual(Meetings.joinLink(in: "https://acme.zoom.us/j/123456?pwd=x")?.host(), "acme.zoom.us")
        XCTAssertNotNil(Meetings.joinLink(in: "https://teams.microsoft.com/l/meetup-join/19%3a"))
        XCTAssertNil(Meetings.joinLink(in: "Agenda: https://docs.google.com/document/d/1"))
        XCTAssertNil(Meetings.joinLink(in: "Room 4"))
    }

    func testUnreadFromTheTitle() {
        XCTAssertEqual(Inbox.unread(in: "Inbox (12) - you@example.com - Gmail"), 12)
        XCTAssertEqual(Inbox.unread(in: "Inbox (1,204) - you@example.com - Gmail"), 1204)
        XCTAssertNil(Inbox.unread(in: "Inbox - you@example.com - Gmail"))
    }

    func testAccountFromTheAddress() {
        XCTAssertEqual(Inbox.account(URL(string: "https://mail.google.com/mail/u/2/#inbox")), 2)
        XCTAssertEqual(Inbox.account(URL(string: "https://mail.google.com/mail/#inbox")), 0)
    }

    func testWhichPinsGlance() {
        XCTAssertEqual(GlanceKind.of(URL(string: "https://calendar.google.com/calendar/u/0/r")), .calendar)
        XCTAssertEqual(GlanceKind.of(URL(string: "https://outlook.office.com/calendar/view/week")), .calendar)
        XCTAssertNil(GlanceKind.of(URL(string: "https://outlook.office.com/mail/inbox")))
        XCTAssertEqual(GlanceKind.of(URL(string: "https://mail.google.com/mail/u/0/#inbox")), .mail)
        XCTAssertNil(GlanceKind.of(URL(string: "https://example.com/calendar")))
    }

    func testGmailsFeedReadToItsMail() {
        let feed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed version="0.3" xmlns="http://purl.org/atom/ns#">
          <title>Gmail - Inbox for you@example.com</title>
          <fullcount>2</fullcount>
          <entry>
            <title>Lunch tomorrow?</title>
            <summary>Are you free at noon</summary>
            <link rel="alternate" href="https://mail.google.com/mail?account_id=you@example.com&amp;message_id=1&amp;view=conv" type="text/html" />
            <modified>2026-11-20T10:00:00Z</modified>
            <issued>2026-11-20T10:00:00Z</issued>
            <id>tag:gmail.google.com,2004:1</id>
            <author><name>Ana</name><email>ana@example.com</email></author>
          </entry>
          <entry>
            <title></title>
            <summary></summary>
            <id>tag:gmail.google.com,2004:2</id>
            <author><name></name><email>ben@example.com</email></author>
          </entry>
        </feed>
        """
        let mails = InboxFeed.read(Data(feed.utf8))
        XCTAssertEqual(mails.count, 2)
        XCTAssertEqual(mails[0].from, "Ana")
        XCTAssertEqual(mails[0].subject, "Lunch tomorrow?")
        XCTAssertEqual(mails[0].summary, "Are you free at noon")
        XCTAssertNotNil(mails[0].when)
        XCTAssertEqual(mails[0].link?.host(), "mail.google.com")
        XCTAssertEqual(mails[1].from, "ben@example.com")
        XCTAssertEqual(mails[1].subject, "(no subject)")
    }
}
