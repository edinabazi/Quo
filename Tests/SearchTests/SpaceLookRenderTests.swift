import AppKit
import SwiftUI
import XCTest
@testable import Search

/// Pictures of the Colour… picker and of a window wearing a space's grained
/// gradient, light and dark, for looking at, not for passing or failing:
/// only with QUO_RENDER_SPACE_LOOK set to a folder, where the PNGs go.
/// Drawn in windows off every screen.
@MainActor
final class SpaceLookRenderTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "space-look-render-\(getpid())", 1)
        super.setUp()
    }

    override class func tearDown() {
        if let world = Store.world, world.hasPrefix("space-look-render-") {
            try? FileManager.default.removeItem(at: Store.folder)
            UserDefaults.standard.removePersistentDomain(forName: "com.officecommun.search.test.\(world)")
        }
        super.tearDown()
    }

    private var folder: URL?
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        try await super.tearDown()
    }

    private func browserWithSpaces() -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.prefs.usesSpaces = true
        browser.prefs.sidebar = true
        browser.welcoming = false
        let id = browser.spaceID
        browser.spaces = [Space(id: id, name: "Studio", colour: 0, icon: "paintpalette")]
        return browser
    }

    private func draw<V: View>(_ view: V, size: NSSize, dark: Bool, name: String, wait: Int = 900) async throws {
        guard let folder else { return }
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        try await Task.sleep(for: .milliseconds(wait))
        let bounds = host.bounds
        guard let rep = host.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        host.cacheDisplay(in: bounds, to: rep)
        try rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name).png"))
    }

    func testRenderThePickerAndAGrainedWindow() async throws {
        guard let out = ProcessInfo.processInfo.environment["QUO_RENDER_SPACE_LOOK"], !out.isEmpty else {
            throw XCTSkip("set QUO_RENDER_SPACE_LOOK to a folder to draw the Colour… picker")
        }
        folder = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: folder!, withIntermediateDirectories: true)
        let browser = browserWithSpaces()
        defer { browser.closeAll() }
        let id = browser.spaceID
        let prefs = browser.prefs
        let look = prefs.look
        defer { prefs.look = look }

        let dusk = SpaceGradient.presets[3].gradient.colours
        let wheel = [ColourWheel.hex(at: CGPoint(x: 0.55, y: -0.62)), ColourWheel.hex(at: CGPoint(x: -0.35, y: 0.7)),
                     ColourWheel.hex(at: CGPoint(x: -0.8, y: -0.2))]
        let pickerSize = NSSize(width: SpaceLookPicker.width, height: 520)
        for dark in [false, true] {
            prefs.look = dark ? .dark : .light
            let tone = dark ? "dark" : "light"
            browser.setWheel(id, colours: wheel)
            browser.setSpaceGrain(id, to: 0.45)
            browser.setSpaceStrength(id, to: .rich)
            try await draw(SpaceLookPicker(browser: browser, id: id)
                .fixedSize(horizontal: false, vertical: true).background(Palette.ground), size: pickerSize, dark: dark,
                           name: "picker-gradient-\(tone)")
            browser.setWheel(id, colours: [wheel[0]])
            try await draw(SpaceLookPicker(browser: browser, id: id)
                .fixedSize(horizontal: false, vertical: true).background(Palette.ground), size: pickerSize, dark: dark,
                           name: "picker-one-\(tone)")
            browser.chooseLook(id, .none)
            try await draw(SpaceLookPicker(browser: browser, id: id)
                .fixedSize(horizontal: false, vertical: true).background(Palette.ground), size: pickerSize, dark: dark,
                           name: "picker-none-\(tone)")

            // The window itself, on Dusk with grain, Rich and Vivid.
            for strength in [SpaceStrength.rich, .vivid] {
                browser.setSpaceGradient(id, to: SpaceGradient(colours: dusk, angle: 135))
                browser.setSpaceGrain(id, to: 0.6)
                browser.setSpaceStrength(id, to: strength)
                try await draw(ContentView(browser: browser), size: NSSize(width: 1100, height: 700), dark: dark,
                               name: "window-\(strength.rawValue)-grain-\(tone)", wait: 1500)
            }
        }
        // The grain alone, close: the column's top corner, Vivid, most grain.
        browser.setSpaceGrain(id, to: 1)
        try await draw(ContentView(browser: browser), size: NSSize(width: 1100, height: 700), dark: false,
                       name: "window-vivid-most-grain-light", wait: 1500)
        browser.setSpaceGrain(id, to: 0)
    }
}
