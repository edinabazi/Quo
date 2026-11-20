import XCTest
@testable import Search

/// A fork's own release notes (QUO_NOTES.md, in the bundle as
/// ReleaseNotes.md): read into versions for Settings › About › What's New.
final class ForkNotesTests: XCTestCase {
    func testVersionsAndTheirParagraphs() {
        let text = """
        # What's new in Quo

        Newest first, and this intro is the file's own.

        ## 0.2.0 · 1 December 2026

        Two lines that
        run together.

        A second paragraph.

        ## 0.1.0 · 20 November 2026

        The first one.
        """
        let found = WhatsNew.parse(text)
        XCTAssertEqual(found.map(\.version), ["0.2.0", "0.1.0"])
        XCTAssertEqual(found[0].date, "1 December 2026")
        XCTAssertEqual(found[0].paragraphs, ["Two lines that run together.", "A second paragraph."])
        XCTAssertEqual(found[1].paragraphs, ["The first one."])
    }

    func testAHeadingWithoutADate() {
        let found = WhatsNew.parse("## 0.3.0\nJust this.")
        XCTAssertEqual(found, [WhatsNew.Own(version: "0.3.0", date: "", paragraphs: ["Just this."])])
    }

    func testNothingWithoutHeadings() {
        XCTAssertEqual(WhatsNew.parse("One paragraph a version, as Search's NOTES.md."), [])
    }

    func testQuoNotesInTheRepoHaveThisVersion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let notes = try String(contentsOf: root.appendingPathComponent("QUO_NOTES.md"), encoding: .utf8)
        let version = try String(contentsOf: root.appendingPathComponent("QUO_VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(WhatsNew.parse(notes).first?.version, version, "QUO_NOTES.md's newest section is QUO_VERSION's")
    }
}
