import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Pictures of each onboarding step (Welcome.swift), for looking at, not for
/// passing or failing: only with QUO_RENDER_ONBOARDING set to a folder,
/// where step-1.png and the rest go. Drawn in a window off every screen at a
/// browser window's size, once the steps' entrances have played.
@MainActor
final class OnboardingRenderTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "onboarding-render-\(getpid())", 1)
        super.setUp()
    }

    func testRenderEveryStep() async throws {
        guard let out = ProcessInfo.processInfo.environment["QUO_RENDER_ONBOARDING"], !out.isEmpty else {
            throw XCTSkip("set QUO_RENDER_ONBOARDING to a folder to draw the onboarding's steps")
        }
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let size = NSSize(width: 1180, height: 780)
        for step in 0..<WelcomePanel.steps {
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: WelcomePanel(browser: browser, prefs: browser.prefs, step: step)
                .frame(width: size.width, height: size.height))
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(1800))
            let bounds = host.bounds
            guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else { continue }
            host.cacheDisplay(in: bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])
            try png?.write(to: URL(fileURLWithPath: out).appendingPathComponent("step-\(step + 1).png"))
            window.orderOut(nil)
        }
    }
}
