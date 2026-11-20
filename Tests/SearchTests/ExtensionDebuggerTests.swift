import XCTest
@testable import Search

/// The part of Chrome's debugger that needs no page (ExtensionDebugger.swift):
/// a script's last statement turned into its answer, as Chrome's evaluate
/// gives it, and an agent's group kept as one across a save.
@MainActor
final class ExtensionDebuggerTests: XCTestCase {
    private func body(_ code: String) -> String? {
        if case .success(let text) = Compiled.body(for: code) { return text }
        return nil
    }

    func testLastExpressionIsReturned() {
        XCTAssertEqual(body("document.title"), "\nreturn (\ndocument.title\n);")
        let two = body("const a = 2;\na * 21")
        XCTAssertNotNil(two)
        XCTAssertTrue(two!.hasSuffix("return (\na * 21\n);"), two!)
    }

    func testBlockAroundItIsOpened() {
        let text = body("{\nconst a = 2;\na * 21\n}")
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("return (\na * 21"), text!)
        XCTAssertFalse(text!.hasPrefix("{"), text!)
    }

    func testTopLevelAwait() {
        let text = body("await new Promise((r) => setTimeout(r, 1));\n7")
        XCTAssertTrue(text?.hasSuffix("return (\n7\n);") == true, text ?? "nil")
    }

    func testCommentAndContinuedLinesAreNotCut() {
        // "5" is inside the comment; "+ 1" carries on the line before.
        XCTAssertTrue(body("// a; 5\n6")?.hasSuffix("return (\n6\n);") == true)
        let sum = body("const x = 1\nconst y = x\n+ 1\ny")
        XCTAssertTrue(sum?.hasSuffix("return (\ny\n);") == true, sum ?? "nil")
        XCTAssertNil(Compiled.returning("const y = 1\n+ 1"))
    }

    func testStatementsAndReturnsAreLeftAlone() {
        XCTAssertEqual(body("if (a) { b }"), "if (a) { b }")
        XCTAssertEqual(body("return 5"), "return 5")
    }

    func testSyntaxErrorIsReported() {
        guard case .failure(let message) = Compiled.body(for: "1 +") else { return XCTFail("parsed") }
        XCTAssertFalse(message.isEmpty)
    }

    func testAgentGroupSurvivesASave() throws {
        let group = TabGroup(id: UUID(), name: "Claude", collapsed: false, agent: "abc")
        let again = try JSONDecoder().decode(TabGroup.self, from: JSONEncoder().encode(group))
        XCTAssertEqual(again, group)
        let old = try JSONDecoder().decode(TabGroup.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Mine"}"#.utf8))
        XCTAssertNil(old.agent)
    }
}
