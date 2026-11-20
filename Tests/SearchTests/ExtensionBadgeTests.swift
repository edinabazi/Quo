import AppKit
import SwiftUI
import XCTest
@testable import Search

/// The badge on an extension's button (ExtensionBadge), drawn off screen at
/// 2× and measured: its text sits in the middle of the capsule, and longer
/// ones stay a size that reads on a 16-point icon.
@MainActor
final class ExtensionBadgeTests: XCTestCase {
    struct Measure { let capsule: CGRect; let ink: CGRect; let size: CGSize }

    /// The capsule (dark pixels on white) and the text in it (light ones).
    func measure(_ text: String, at origin: CGPoint = CGPoint(x: 6, y: 6), dark: Bool = false, save folder: String? = nil) throws -> Measure {
        _ = NSApplication.shared
        // At a point that needn't be whole, as in the toolbar, where the
        // badge hangs off its icon's corner; on white, the badge dark.
        let host = NSHostingView(rootView: ExtensionBadge(text: text)
            .padding(.leading, origin.x).padding(.top, origin.y).padding(.trailing, 6).padding(.bottom, 6)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                   pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        if let folder {
            try rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: folder).appendingPathComponent("badge-\(text).png"))
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var lum = [[CGFloat]](repeating: [CGFloat](repeating: 1, count: w), count: h)
        for y in 0..<h {
            for x in 0..<w {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                lum[y][x] = (c.redComponent + c.greenComponent + c.blueComponent) / 3
            }
        }
        var dark = CGRect.null, light = CGRect.null
        for y in 0..<h { for x in 0..<w where lum[y][x] < 0.35 { dark = dark.union(CGRect(x: x, y: y, width: 1, height: 1)) } }
        // The text: light pixels with the capsule's fill on all four sides,
        // so the white round the capsule's corners isn't taken for it.
        for y in 0..<h {
            for x in 0..<w where lum[y][x] > 0.6 {
                let left = (0..<x).contains { lum[y][$0] < 0.35 }, right = (x + 1..<w).contains { lum[y][$0] < 0.35 }
                let up = (0..<y).contains { lum[$0][x] < 0.35 }, down = (y + 1..<h).contains { lum[$0][x] < 0.35 }
                if left && right && up && down { light = light.union(CGRect(x: x, y: y, width: 1, height: 1)) }
            }
        }
        return Measure(capsule: dark, ink: light, size: CGSize(width: dark.width / scale, height: dark.height / scale))
    }

    /// Wherever the badge lands, between pixels too, its text stays in it.
    func testAnywhereInTheToolbar() throws {
        var report: [String] = []
        for text in ["2", "7", "12"] {
            for x in [6.0, 6.25, 6.5, 6.75] {
                for y in [6.0, 6.25, 6.5, 6.75] {
                    let m = try measure(text, at: CGPoint(x: x, y: y))
                    let dx = (m.ink.midX - m.capsule.midX) / 2, dy = (m.ink.midY - m.capsule.midY) / 2
                    report.append("\(text) at \(x),\(y): off by \(dx), \(dy)")
                    XCTAssertLessThanOrEqual(abs(dx), 0.5, "“\(text)” at \(x),\(y) is \(dx)pt off across")
                    XCTAssertLessThanOrEqual(abs(dy), 0.5, "“\(text)” at \(x),\(y) is \(dy)pt off down")
                }
            }
        }
        print(report.joined(separator: "\n"))
    }

    func testOnlyFourCharactersAsChrome() {
        XCTAssertEqual(ExtensionBadge.shown("12345"), "1234")
        XCTAssertEqual(ExtensionBadge.shown(" 7 "), "7")
    }

    func testTextSitsInTheMiddle() throws {
        let folder = ProcessInfo.processInfo.environment["QUO_RENDER_BADGES"]
        var report: [String] = []
        for text in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "12", "99", "999", "99+", "1234", "NEW", "ON"] {
            // One or two characters a circle or a short capsule; three or
            // four never wider than 24 points.
            XCTAssertLessThanOrEqual(try measure(text).size.width, text.count >= 3 ? 24 : 20, text)
            let m = try measure(text, save: folder)
            let dx = (m.ink.midX - m.capsule.midX) / 2, dy = (m.ink.midY - m.capsule.midY) / 2
            report.append("\(text): \(m.size.width)×\(m.size.height)pt, off by \(dx), \(dy)")
            XCTAssertLessThanOrEqual(abs(dx), 0.5, "“\(text)” is \(dx)pt off across")
            XCTAssertLessThanOrEqual(abs(dy), 0.5, "“\(text)” is \(dy)pt off down")
        }
        print(report.joined(separator: "\n"))
    }
}
