import AppKit
import Combine
import XCTest
@testable import Search

/// The Colour… picker's wheel (ColourWheel), a space's grain, and the live
/// preview a drag shows (LookDraft): the colour maths, what is kept in
/// spaces.json and synced, and that a drag draws without writing.
@MainActor
final class SpaceWheelTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "space-wheel-\(getpid())", 1)
        super.setUp()
    }

    override class func tearDown() {
        if let world = Store.world, world.hasPrefix("space-wheel-") {
            try? FileManager.default.removeItem(at: Store.folder)
            UserDefaults.standard.removePersistentDomain(forName: "com.officecommun.search.test.\(world)")
        }
        super.tearDown()
    }

    private var bag: Set<AnyCancellable> = []

    // MARK: - the wheel

    /// The middle is grey, the rim the most sRGB shows of each hue, and
    /// every colour on it is one sRGB can show, at the wheel's lightness.
    func testTheWheelRunsFromGreyToTheRim() {
        XCTAssertEqual(ColourWheel.colour(at: .zero).chroma, 0, accuracy: 1e-9)
        for degrees in stride(from: 0.0, to: 360, by: 7.5) {
            let rim = ColourWheel.rim(exact: degrees)
            XCTAssertGreaterThan(rim, 0.06, "every hue has colour at the rim: \(degrees)")
            XCTAssertLessThanOrEqual(rim, OKLab.mostChroma)
            XCTAssertTrue(OKLab(lightness: ColourWheel.lightness, chroma: rim, hue: degrees).fits, "\(degrees)")
            if rim < OKLab.mostChroma - 1e-6 {
                XCTAssertFalse(OKLab(lightness: ColourWheel.lightness, chroma: rim + 0.005, hue: degrees).fits,
                               "the rim is as far as sRGB goes: \(degrees)")
            }
        }
        for x in stride(from: -1.0, through: 1, by: 0.25) {
            for y in stride(from: -1.0, through: 1, by: 0.25) {
                let colour = ColourWheel.colour(at: CGPoint(x: x, y: y))
                XCTAssertTrue(colour.fits, "\(x), \(y)")
                XCTAssertEqual(colour.L, ColourWheel.lightness, accuracy: 1e-9)
            }
        }
        // Beyond the rim is the rim.
        XCTAssertEqual(ColourWheel.colour(at: CGPoint(x: 3, y: 0)).hex, ColourWheel.colour(at: CGPoint(x: 1, y: 0)).hex)
        // Red at the top, as the picker shows it.
        XCTAssertEqual(ColourWheel.hue(at: CGPoint(x: 0, y: -1)), 25, accuracy: 1e-9)
    }

    /// A colour picked goes back to the spot it was picked at.
    func testAPointAndItsColourGoBothWays() {
        for x in stride(from: -0.9, through: 0.9, by: 0.3) {
            for y in stride(from: -0.9, through: 0.9, by: 0.3) where hypot(x, y) <= 1 && hypot(x, y) > 0.1 {
                let spot = CGPoint(x: x, y: y)
                let back = ColourWheel.point(for: ColourWheel.colour(at: spot))
                XCTAssertEqual(back.x, x, accuracy: 1e-6, "\(spot)")
                XCTAssertEqual(back.y, y, accuracy: 1e-6, "\(spot)")
                // Through "#RRGGBB" too, as it is kept: within a point on the wheel.
                let kept = ColourWheel.point(for: ColourWheel.colour(at: spot).hex)!
                XCTAssertLessThan(hypot(kept.x - x, kept.y - y), 0.02, "\(spot)")
            }
        }
        XCTAssertEqual(ColourWheel.point(for: OKLab(hex: "#808080")!), .zero, "a grey is the middle")
        XCTAssertNil(ColourWheel.point(for: "nonsense"))
    }

    /// Handles snap to the twelve hues the ready-made gradients are made
    /// of and to the grey middle, and a handle let go on one is that colour
    /// exactly, so the ready-made gradients come back as themselves.
    func testHandlesSnapToTheSwatchesAndTheMiddle() {
        XCTAssertEqual(ColourWheel.snaps.count, 13)
        for (at, swatch) in SpaceGradient.swatches.prefix(12).enumerated() {
            let snap = ColourWheel.snaps[at]
            XCTAssertEqual(snap.hex, swatch.hex)
            let near = CGPoint(x: snap.point.x + ColourWheel.pull * 0.6, y: snap.point.y)
            XCTAssertEqual(ColourWheel.snapped(near).snap, at, swatch.name)
            XCTAssertEqual(ColourWheel.snapped(near).point, snap.point)
            XCTAssertEqual(ColourWheel.hex(at: near), swatch.hex, swatch.name)
        }
        XCTAssertEqual(ColourWheel.snapped(CGPoint(x: 0.03, y: -0.02)).snap, 12, "the middle")
        XCTAssertEqual(OKLab(hex: ColourWheel.hex(at: CGPoint(x: 0.03, y: 0)))!.chroma, 0, accuracy: 0.002)
        // Between snaps, the colour under the handle.
        let free = CGPoint(x: 0.3, y: 0.3)
        XCTAssertNil(ColourWheel.snapped(free).snap)
        XCTAssertEqual(ColourWheel.hex(at: free), ColourWheel.colour(at: free).hex)
        // Off the wheel, held to it.
        let out = ColourWheel.snapped(CGPoint(x: 0, y: 2.5)).point
        XCTAssertLessThanOrEqual(hypot(out.x, out.y), 1 + 1e-9)
        // Each preset's colours lie on snaps.
        for (name, preset) in SpaceGradient.presets {
            for hex in preset.colours {
                let spot = ColourWheel.point(for: hex)!
                XCTAssertEqual(ColourWheel.hex(at: spot), hex, name)
            }
        }
    }

    /// A handle added goes round the wheel from the last, out where there
    /// is colour; the first is Blue.
    func testANewHandleIsANeighbourWorthHaving() {
        XCTAssertEqual(ColourWheel.hex(at: ColourWheel.beside([])), SpaceGradient.swatch("Blue"))
        let grey = ColourWheel.beside([CGPoint(x: 0.05, y: 0)])
        XCTAssertGreaterThan(hypot(grey.x, grey.y), 0.5, "from a grey, out to a colour")
        let from = CGPoint(x: 0.8, y: 0)
        let next = ColourWheel.beside([from])
        XCTAssertGreaterThan(hypot(next.x - from.x, next.y - from.y), 0.5, "a hue of its own")
    }

    func testTheWheelImageIsMadeOnceASize() {
        let one = ColourWheel.image(side: 120)
        XCTAssertTrue(one === ColourWheel.image(side: 120))
        XCTAssertEqual(one.size, NSSize(width: 120, height: 120))
        XCTAssertNotNil(one.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    // MARK: - grain, kept

    /// No grain is written as nothing at all: a list from before reads and
    /// writes as it did.
    func testNoGrainIsNotWritten() throws {
        let space = Space(id: UUID(), name: "Plain", colour: 2)
        let written = String(decoding: try JSONEncoder().encode(space), as: UTF8.self)
        XCTAssertFalse(written.contains("grain"), written)
        XCTAssertEqual(space.grainAmount, 0)
    }

    /// Grain goes and comes back with the space, beside its look, in
    /// hundredths, held to 0…1; one that doesn't read is none, and never
    /// costs the list.
    func testGrainGoesAndComesBack() throws {
        var space = Space(id: UUID(), name: "Studio", colour: 3)
        space.gradient = SpaceGradient(colours: [SpaceGradient.swatch("Teal"), SpaceGradient.swatch("Blue")])
        space.grain = SpaceGrain(0.4567)
        XCTAssertEqual(space.grain?.amount, 0.46)
        let back = try JSONDecoder().decode(Space.self, from: JSONEncoder().encode(space))
        XCTAssertEqual(back, space)
        XCTAssertEqual(back.grainAmount, 0.46)
        XCTAssertEqual(SpaceGrain(7).amount, 1)
        XCTAssertEqual(SpaceGrain(-1).amount, 0)
        XCTAssertEqual(SpaceGrain(.nan).amount, 0)
        for damaged in [#""lots""#, "true", "[1]", "{}", "1e400"] {
            let text = #"[{"id":"00000000-0000-0000-0000-000000000001","name":"Personal","colour":4,"grain":"# + damaged + "}]"
            let spaces = try JSONDecoder().decode([Space].self, from: Data(text.utf8))
            XCTAssertEqual(spaces.count, 1, damaged)
            XCTAssertEqual(spaces[0].look, .colour(4), damaged)
            XCTAssertEqual(spaces[0].grainAmount, 0, damaged)
        }
    }

    /// A gradient from before amounts with its grain switched on has the
    /// grain it had: exactly the tile's old strength.
    func testAGradientFromBeforeAmountsKeepsItsGrain() throws {
        let text = ##"{"id":"6F1C2D3E-0000-4000-8000-000000000002","name":"Old","colour":1,"gradient":{"colours":["#4285F5","#F59E33"],"grain":true}}"##
        let space = try JSONDecoder().decode(Space.self, from: Data(text.utf8))
        XCTAssertNil(space.grain)
        XCTAssertEqual(space.grainAmount, Grain.legacy)
        XCTAssertEqual(SpaceStrength.subtle.grain(space.grainAmount, dark: false), Grain.light)
        XCTAssertEqual(SpaceStrength.subtle.grain(space.grainAmount, dark: true), Grain.dark)
        XCTAssertEqual(SpaceStrength.subtle.grain(0, dark: false), 0)
        // More is more, and the most is about two and a half times the old
        // switch: gentler past it than up to it.
        XCTAssertEqual(SpaceStrength.subtle.grain(1, dark: false), Grain.light * 2.4, accuracy: 0.0001)
        XCTAssertGreaterThan(SpaceStrength.subtle.grain(0.6, dark: false), SpaceStrength.subtle.grain(0.4, dark: false))
        XCTAssertLessThan(SpaceStrength.vivid.grain(1, dark: false), 0.14)
    }

    /// Grain is the space's, over a colour or a gradient alike; the
    /// gradient's own switch follows it for a Search from before amounts;
    /// picking a colour keeps it; Escape puts back exactly what was.
    func testGrainIsTheSpacesWhateverItWears() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let oldUsesSpaces = browser.prefs.usesSpaces
        let oldSpaces = browser.spaces
        defer {
            browser.closeAll()
            browser.prefs.usesSpaces = oldUsesSpaces
            browser.spaces = oldSpaces
        }
        browser.prefs.usesSpaces = true
        let id = browser.spaceID
        browser.spaces = [Space(id: id, name: "Home", colour: 2)]
        XCTAssertEqual(browser.washGrain, 0)

        browser.setSpaceGrain(id, to: 0.5)
        XCTAssertEqual(browser.washGrain, 0.5, "over a plain colour too")
        browser.chooseLook(id, .preset(1))
        XCTAssertEqual(browser.space.gradient?.grain, true, "the switch on, for a Search from before amounts")
        XCTAssertEqual(browser.washGrain, 0.5)
        browser.setSpaceGrain(id, to: 0)
        XCTAssertNil(browser.space.grain, "none is kept as none")
        XCTAssertEqual(browser.space.gradient?.grain, false)
        XCTAssertEqual(browser.washGrain, 0)

        // A gradient from before amounts, grain on: a colour picked keeps it.
        browser.spaces = [Space(id: id, name: "Home", colour: 2,
                                gradient: SpaceGradient(colours: SpaceGradient.presets[0].gradient.colours, grain: true))]
        XCTAssertEqual(browser.washGrain, Grain.legacy)
        browser.chooseLook(id, .colour(4))
        XCTAssertEqual(browser.space.grain?.amount, Grain.legacy)
        XCTAssertEqual(browser.washGrain, Grain.legacy)

        browser.setSpaceGrain(id, to: 0.8)
        browser.restoreLook(id, colour: 2, gradient: nil, strength: .rich, grain: SpaceGrain(0.2))
        XCTAssertEqual(browser.space.grainAmount, 0.2)
        XCTAssertEqual(browser.space.washStrength, .rich)
        browser.restoreLook(id, colour: 2, gradient: nil)
        XCTAssertNil(browser.space.grain, "restored to none")

        browser.prefs.usesSpaces = false
        browser.setSpaceGrain(id, to: 0.9)
        XCTAssertEqual(browser.washGrain, 0, "no wash, no grain")
    }

    // MARK: - the wheel's handles

    func testHandlesMakeTheLook() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let oldUsesSpaces = browser.prefs.usesSpaces
        let oldSpaces = browser.spaces
        defer {
            browser.closeAll()
            browser.prefs.usesSpaces = oldUsesSpaces
            browser.spaces = oldSpaces
        }
        browser.prefs.usesSpaces = true
        let id = browser.spaceID
        browser.spaces = [Space(id: id, name: "Home", colour: 0)]
        XCTAssertEqual(browser.space.wheelColours, [], "no colour, no handles")

        XCTAssertEqual(browser.addWheelHandle(id), 0)
        XCTAssertEqual(browser.space.wheelColours, [SpaceGradient.swatch("Blue")])
        XCTAssertEqual(browser.space.lookName, "Custom colour")
        XCTAssertEqual(browser.addWheelHandle(id), 1)
        XCTAssertEqual(browser.addWheelHandle(id), 2)
        XCTAssertNil(browser.addWheelHandle(id), "three at most")
        XCTAssertEqual(browser.space.wheelColours.count, 3)
        XCTAssertEqual(browser.space.lookName, "Custom gradient")

        browser.turnGradient(id)
        XCTAssertEqual(browser.space.gradient?.angle, 180)
        browser.turnGradient(id, by: 225)
        XCTAssertEqual(browser.space.gradient?.angle, 45, "round past 360")
        browser.removeWheelHandle(id, at: 0)
        XCTAssertEqual(browser.space.wheelColours.count, 2)
        XCTAssertEqual(browser.space.gradient?.angle, 45, "its direction kept")
        browser.removeWheelHandle(id, at: 5)
        browser.removeWheelHandle(id, at: 0)
        XCTAssertEqual(browser.space.wheelColours.count, 1, "the last handle stays")

        // Handles on a ready-made gradient's snaps are that gradient.
        let lagoon = SpaceGradient.presets[1].gradient.colours
        browser.setWheel(id, colours: lagoon.compactMap(ColourWheel.point(for:)).map(ColourWheel.hex(at:)))
        XCTAssertEqual(browser.space.lookChoice, .preset(1))
        // A plain colour is one handle where its colour lies.
        browser.chooseLook(id, .colour(1))
        XCTAssertEqual(browser.space.wheelColours.count, 1)
        XCTAssertEqual(browser.space.look, .colour(1))
    }

    // MARK: - the live preview

    /// While a handle or the grain is dragged, the washes show the look at
    /// once and nothing else happens: the browser announces nothing, the
    /// space is untouched, nothing is written. Let go, it is kept, once.
    func testADragDrawsWithoutWriting() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        let oldUsesSpaces = browser.prefs.usesSpaces
        let oldSpaces = browser.spaces
        defer {
            LookDraft.shared.end()
            browser.closeAll()
            browser.prefs.usesSpaces = oldUsesSpaces
            browser.spaces = oldSpaces
        }
        browser.prefs.usesSpaces = true
        let id = browser.spaceID
        browser.spaces = [Space(id: id, name: "Home", colour: 2)]
        Spaces.write(browser.spaces, profile: browser.profileID)
        let file = Store.file("spaces.json")
        let before = try Data(contentsOf: file)
        var heard = 0
        browser.objectWillChange.sink { heard += 1 }.store(in: &bag)
        defer { bag.removeAll() }

        let draft = LookDraft.shared
        let shown = draft.shown
        for step in 0..<30 {
            let spot = CGPoint(x: cos(Double(step) / 5), y: sin(Double(step) / 5))
            let gradient = browser.wheelGradient(id, colours: [ColourWheel.hex(at: spot), SpaceGradient.swatch("Pink")])!
            draft.show(LookDraft.Preview(space: id, look: .gradient(gradient), strength: .vivid, grain: Double(step) / 30))
        }
        XCTAssertGreaterThan(draft.shown - shown, 25, "each step shown")
        XCTAssertEqual(heard, 0, "the browser announces nothing while it is dragged")
        XCTAssertEqual(browser.space.look, .colour(2), "the space untouched")
        XCTAssertEqual(try Data(contentsOf: file), before, "nothing written")
        XCTAssertNotNil(draft.preview(for: browser.washSpace), "the washes of the space on screen show it")
        XCTAssertNil(draft.preview(for: UUID()), "another space's do not")
        XCTAssertNil(draft.preview(for: nil), "nor the small window's")

        guard case .gradient(let last)? = draft.preview?.look else { return XCTFail("a gradient held") }
        draft.end { browser.setWheel(id, colours: last.colours) }
        XCTAssertNil(draft.preview)
        XCTAssertEqual(browser.space.gradient?.colours, last.colours, "kept as let go")
        XCTAssertNotEqual(try Data(contentsOf: file), before, "and written")
        XCTAssertGreaterThan(heard, 0)
    }

    // MARK: - sync

    func testGrainSyncsAsAnItemOfItsOwn() {
        var studio = Space(id: UUID(), name: "Studio", colour: 2, sharesSignIns: true)
        let plain = SyncItems.spaces([Space.first(), studio])
        XCTAssertFalse(plain.keys.contains { $0.hasPrefix("grain:") }, "no grain, no item")
        studio.grain = SpaceGrain(0)
        XCTAssertEqual(SyncItems.spaces([Space.first(), studio]), plain, "none is no item")
        studio.grain = SpaceGrain(0.35)
        let items = SyncItems.spaces([Space.first(), studio])
        XCTAssertEqual(items[SyncItems.spaceKey(studio.id)], plain[SyncItems.spaceKey(studio.id)],
                       "the space's own item reads as an older Search writes it")
        XCTAssertEqual(items[SyncItems.grainKey(studio.id)], "0.35")
        let back = SyncItems.applySpaces(items, to: [], profile: Profile.personalID, home: Space.firstID)
        XCTAssertEqual(back.first { $0.id == studio.id }?.grain, SpaceGrain(0.35))
        XCTAssertEqual(SyncItems.spaces(back), items)
        let gone = SyncItems.applySpaces(plain, to: back, profile: Profile.personalID, home: Space.firstID)
        XCTAssertNil(gone.first { $0.id == studio.id }?.grain, "taken off on one Mac: off on the other")
        XCTAssertTrue(SyncItems.understood(SyncItems.grainKey(studio.id), "0.5"))
        XCTAssertFalse(SyncItems.understood(SyncItems.grainKey(studio.id), "7"), "a newer Search's, carried along")
        XCTAssertFalse(SyncItems.understood(SyncItems.grainKey(studio.id), #""lots""#))
    }

    /// A Search from before amounts carries the item along untouched.
    func testAnOlderSearchCarriesTheGrainAlong() {
        var studio = Space(id: UUID(), name: "Studio", colour: 2, sharesSignIns: true)
        studio.grain = SpaceGrain(0.6)
        let newer = SyncMerge.pass(current: SyncItems.spaces([Space.first(), studio]), base: nil, theirs: [],
                                   device: "new", now: 1000)
        var older = studio
        older.grain = nil
        let olderUnderstood: (String, String) -> Bool = { key, text in
            key.hasPrefix("grain:") ? false : SyncItems.understood(key, text)
        }
        let after = SyncMerge.pass(current: SyncItems.spaces([Space.first(), older]), base: newer, theirs: [newer],
                                   device: "old", now: 2000, understood: olderUnderstood)
        XCTAssertEqual(after[SyncItems.grainKey(studio.id)]?.v, newer[SyncItems.grainKey(studio.id)]?.v)
        XCTAssertEqual(after[SyncItems.spaceKey(studio.id)], newer[SyncItems.spaceKey(studio.id)], "nothing restamped")
    }
}
