import AppKit
import Combine
import SwiftUI

// A tab group an agent made to work in — Claude's, ChatGPT's, any extension
// that drives pages through Chrome's debugger (ExtensionDebugger.swift) —
// looks like one: the agent's icon before its name, a wash of colour under
// the heading, a thread down the side of its tabs, and, while the agent is
// at work in one of them, a light passing over the heading. A group of your
// own looks as it always has.

/// Which tabs an agent is working in right now: each command an extension
/// sends through the debugger touches its tab, and a tab left alone for a
/// few seconds is quiet again.
@MainActor
final class AgentActivity: ObservableObject {
    static let shared = AgentActivity()
    @Published private(set) var working: Set<UUID> = []
    private var last: [UUID: Date] = [:]
    private var timer: Timer?

    /// How long after its last command a tab still counts as worked in.
    static let quiet: TimeInterval = 4

    func touched(_ tab: UUID) {
        last[tab] = Date()
        if !working.contains(tab) { working.insert(tab) }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
    }

    func stopped(_ tab: UUID) {
        last[tab] = nil
        working.remove(tab)
    }

    private func settle() {
        let now = Date()
        let gone = last.filter { now.timeIntervalSince($0.value) > Self.quiet }.map(\.key)
        for tab in gone { last[tab] = nil; working.remove(tab) }
        if last.isEmpty { timer?.invalidate(); timer = nil }
    }
}

/// The colours an agent's group wears: the same in every space, so it reads
/// as the agent's and not the space's.
enum AgentTint {
    static let start = Color(red: 0.42, green: 0.42, blue: 0.98)
    static let end = Color(red: 0.78, green: 0.38, blue: 0.92)
    static func wash(_ strength: Double) -> LinearGradient {
        LinearGradient(colors: [start.opacity(strength), end.opacity(strength * 0.55)], startPoint: .leading, endPoint: .trailing)
    }
    static func line(_ strength: Double) -> LinearGradient {
        LinearGradient(colors: [start.opacity(strength), end.opacity(strength)], startPoint: .top, endPoint: .bottom)
    }
}

/// The agent's own icon, from its extension, or sparkles for one with none.
struct AgentGlyph: View {
    let agent: String
    var size: CGFloat = 14

    /// Drawn once an extension: the column asks on every redraw.
    @MainActor private static var icons: [String: NSImage] = [:]

    @MainActor static func icon(for agent: String) -> NSImage? {
        if let known = icons[agent] { return known }
        guard #available(macOS 15.4, *),
              let icon = Extensions.shared.contexts[agent]?.webExtension.icon(for: CGSize(width: 32, height: 32))
        else { return nil }
        icons[agent] = icon
        return icon
    }

    /// The agent's name, as its extension gives it.
    @MainActor static func name(of agent: String) -> String? {
        guard #available(macOS 15.4, *) else { return nil }
        return Extensions.shared.contexts[agent]?.webExtension.displayName
    }

    var body: some View {
        Group {
            if let icon = Self.icon(for: agent) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.78, weight: .semibold))
                    .foregroundStyle(AgentTint.wash(1))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The heading's ground: a wash from one colour to the other, a hairline
/// round it, and while the agent works, a light passing over.
struct AgentGroupGround: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var working: Bool
    var hovering: Bool
    var dropping: Bool
    var radius: CGFloat = 9

    @State private var phase: CGFloat = -1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(AgentTint.wash(dropping ? 0.30 : hovering ? 0.22 : 0.14))
            .overlay {
                if working && !still {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.28), .white.opacity(0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 0.45)
                            .offset(x: phase * geometry.size.width)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(shape)
                    .onAppear {
                        phase = -0.5
                        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1.1 }
                    }
                    .onDisappear { phase = -1 }
                }
            }
            .overlay(shape.strokeBorder(AgentTint.wash(working ? 0.55 : 0.32), lineWidth: 0.75))
    }
}

/// Three dots breathing in turn: the agent is at work in this group.
struct AgentWorkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: still)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(AgentTint.wash(1))
                        .frame(width: 4, height: 4)
                        .opacity(still ? 0.8 : 0.35 + 0.65 * max(0, sin((t * 4) - Double(i) * 0.9)))
                }
            }
        }
        .help("The agent is working in this group")
        .accessibilityLabel("Working")
    }
}

/// The thread an agent's tabs hang on, down the margin they're set in by.
struct AgentThread: View {
    var body: some View {
        Capsule()
            .fill(AgentTint.line(0.55))
            .frame(width: 2)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
