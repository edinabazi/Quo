import AppKit
import QuartzCore

// A mouse wheel's notches, scrolled smoothly, as Chromium scrolls them.
//
// WebKit moves a page the whole of a notch at once, 40 points a line, so a
// wheel turned slowly steps down the page in jerks. A trackpad doesn't,
// since it sends many small steps in pixels. So a notch from a wheel is
// taken here and played out as such steps: its distance, the same 40
// points a line WebKit would have gone, on an ease-out over about a fifth
// of a second, each frame sent on to WebKit as an ordinary scroll in pixels.
// Notches turned quickly add to what is still to go, so a fast spin goes
// further and faster, and a turn the other way starts from where the page
// is. The page still sees real wheel events, only more of them and smaller,
// so a map still zooms and a custom scroller still scrolls.
//
// Only a wheel's notches: a trackpad, a Magic Mouse, or a wheel some other
// app already smooths (LinearMouse, Mos) sends pixels, and is left alone,
// as is a turn with ⌘, ⌥ or ⌃ held, which a page or the browser may read
// as a zoom.

@MainActor
final class SmoothWheel: NSObject {
    /// Settings › Keyboard & Mouse › Smooth scrolling with a mouse wheel.
    nonisolated(unsafe) static var on = true
    /// What WebKit scrolls for one line of a wheel (Scrollbar::pixelsPerLineStep).
    static let perLine: CGFloat = 40
    /// The ease-out's time constant: 90% of the way in about 0.16 s.
    static let tau: CFTimeInterval = 0.07

    private weak var view: PageView?
    /// What is still to go, in points, as the wheel counts them: up is positive.
    private var left = CGVector.zero
    /// Where on the view the notch was turned, in its window: every step
    /// scrolls what that notch was over, as Chromium's do.
    private var spot = NSPoint.zero
    private var flags: CGEventFlags = []
    private var link: CADisplayLink?
    /// For a window not on show, which its display gives no frames.
    private var timer: Timer?
    private var last: CFTimeInterval = 0
    /// When the clock last ticked: one that has stopped (the window went
    /// behind another, or off every screen) is started again.
    private var ticked: CFTimeInterval = 0

    init(view: PageView) {
        self.view = view
    }

    /// A wheel's notch over the page: true when it is taken, to be played
    /// out here, and must not go on to WebKit as it is.
    func take(_ event: NSEvent) -> Bool {
        guard SmoothWheel.on, !event.hasPreciseScrollingDeltas, event.phase == [], event.momentumPhase == [],
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let view, view.window != nil else { return false }
        let dx = event.scrollingDeltaX * SmoothWheel.perLine
        let dy = event.scrollingDeltaY * SmoothWheel.perLine
        guard dx != 0 || dy != 0 else { return false }
        // A turn the other way stops what was left of the last.
        if dy * left.dy < 0 { left.dy = 0; carry.dy = 0 }
        if dx * left.dx < 0 { left.dx = 0; carry.dx = 0 }
        left.dx += dx
        left.dy += dy
        spot = event.locationInWindow
        flags = event.cgEvent?.flags ?? []
        if link != nil || timer != nil, CACurrentMediaTime() - ticked > 0.1 { restart() }
        run()
        return true
    }

    /// Whatever is left goes nowhere: a trackpad took over, or the page went.
    func stop() {
        left = .zero
        carry = .zero
        restart()
    }

    private func restart() {
        link?.invalidate()
        link = nil
        timer?.invalidate()
        timer = nil
        last = 0
    }

    private func run() {
        guard link == nil, timer == nil, let view else { return }
        // A window on show keeps time by its display; one covered or off
        // every screen gets no frames from it, and runs on a timer.
        if view.window?.occlusionState.contains(.visible) == true {
            let link = view.displayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(CACurrentMediaTime()) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        last = 0
        ticked = CACurrentMediaTime()
        // The first step at once: a notch answered on the next frame, not
        // the one after.
        advance(by: 1.0 / 60)
    }

    @objc private func step(_ link: CADisplayLink) { tick(link.timestamp) }

    private func tick(_ now: CFTimeInterval) {
        ticked = CACurrentMediaTime()
        let dt = last == 0 ? 1.0 / 60 : min(now - last, 0.05)
        last = now
        advance(by: dt)
    }

    private func advance(by dt: CFTimeInterval) {
        guard let view, view.window != nil else { return stop() }
        let k = CGFloat(1 - exp(-dt / SmoothWheel.tau))
        var move = CGVector(dx: left.dx * k, dy: left.dy * k)
        // The last half point goes in one, rather than an endless crawl.
        if abs(left.dx - move.dx) < 0.5 { move.dx = left.dx }
        if abs(left.dy - move.dy) < 0.5 { move.dy = left.dy }
        left.dx -= move.dx
        left.dy -= move.dy
        if move.dx != 0 || move.dy != 0 { send(move, to: view) }
        if left == .zero { stop() }
    }

    /// The part of a pixel each step leaves over, carried into the next:
    /// an event can only carry whole ones.
    private var carry = CGVector.zero

    /// One step as WebKit takes a trackpad's: whole pixels, with no phase.
    private func send(_ move: CGVector, to view: PageView) {
        carry.dx += move.dx
        carry.dy += move.dy
        let x = carry.dx.rounded(.towardZero), y = carry.dy.rounded(.towardZero)
        guard x != 0 || y != 0 else { return }
        carry.dx -= x
        carry.dy -= y
        // Made in pixels, the event is continuous and its lines worked out
        // from them: nothing more is set, since setting a line field makes
        // AppKit work the pixels out again from it.
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(y), wheel2: Int32(x), wheel3: 0) else { return }
        // An event made here belongs to no window, and AppKit reads its place
        // as a point in the window it lands in: given one, in the window's
        // own terms, it comes out where the notch was turned.
        cg.location = CGPoint(x: spot.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - spot.y)
        cg.flags = flags
        guard let event = NSEvent(cgEvent: cg) else { return }
        view.scrollSmoothly(event)
    }
}
