import AppKit
import SwiftUI

// An empty tab is the space's home: the card wears the space's colour and
// grain in full, and around the field that stands on it, its icon and a
// greeting above, and below, the sites you visit most as tiles and the tabs
// you closed last. What you type takes the room: the tiles step aside for
// the field's suggestions. Nothing here is sent anywhere or kept: the tiles
// are History's own, worked out when the tab is shown.
//
// The parts above and below the field hang from the field itself (see
// Omnibox), so they are always where it is, whatever the window's chrome.

/// The ground of an empty tab: the space's colour or gradient, as the
/// chrome wears it but stronger, with its grain, and a soft light from above.
struct SpaceHomeGround: View {
    @ObservedObject var browser: Browser
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Palette.ground
            SpaceWash(look: browser.wash)
                .environment(\.washStrength, browser.washStrength == .subtle ? .rich : browser.washStrength)
                .opacity(0.9)
            // Light from above, so the page reads as a place, not a fill.
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.06 : 0.35), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 700)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Above the field: the space's icon on a tile of its colour, a greeting
/// for the time of day, and the space's name when there are spaces.
struct SpaceHomeHeader: View {
    @ObservedObject var browser: Browser
    @State private var shown = false

    private var tint: Color { browser.space.tint ?? Palette.ink }

    static func greeting(at date: Date = Date(), name: String? = SpaceHomeHeader.firstName) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let part: String = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Up late"
        }
        guard let name, !name.isEmpty else { return part }
        return part + ", " + name
    }

    /// The Mac's own name for whoever is signed in: the first word of it.
    static let firstName: String? = NSFullUserName().split(separator: " ").first.map { word in
        word.prefix(1).uppercased() + word.dropFirst()
    }

    var body: some View {
        VStack(spacing: 14) {
            if browser.prefs.usesSpaces {
                Image(systemName: browser.space.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(tint.opacity(0.22), lineWidth: 1))
                    .scaleEffect(shown ? 1 : 0.8)
            }
            VStack(spacing: 4) {
                Text(SpaceHomeHeader.greeting())
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                if browser.prefs.usesSpaces {
                    Text(browser.space.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 8)
        .onAppear {
            guard !Motion.reduced else { return shown = true }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { shown = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Below the field: the sites you visit most, as tiles, and the tabs you
/// closed last. A click loads the site in this tab, or brings the tab back.
struct SpaceHomeBelow: View {
    @ObservedObject var browser: Browser
    @State private var shown = false

    static let columns = 4
    static let tile: CGFloat = 92

    private var sites: [History.Site] { browser.history.mostVisited(limit: 8) }
    private var closed: [Browser.Ghost] { Array(browser.recentlyClosed.prefix(3)) }

    var body: some View {
        let sites = self.sites, closed = self.closed
        VStack(spacing: 26) {
            if !sites.isEmpty {
                Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                    ForEach(0..<((sites.count + SpaceHomeBelow.columns - 1) / SpaceHomeBelow.columns), id: \.self) { row in
                        GridRow {
                            ForEach(Array(sites.enumerated()).filter { $0.offset / SpaceHomeBelow.columns == row }, id: \.element.id) { index, site in
                                SiteTile(site: site, order: index, shown: shown) { go(site.url) }
                            }
                        }
                    }
                }
            }
            if !closed.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recently closed")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.faint)
                        .padding(.leading, 10)
                        .padding(.bottom, 4)
                    ForEach(closed) { ghost in
                        ClosedRow(title: browser.closedTitle(for: ghost) == "Closed Tab" ? ghost.title : browser.closedTitle(for: ghost),
                                  url: ghost.url) { browser.reopen(ghost) }
                    }
                }
                .frame(width: SpaceHomeBelow.tile * CGFloat(SpaceHomeBelow.columns) + 14 * CGFloat(SpaceHomeBelow.columns - 1),
                       alignment: .leading)
                .opacity(shown ? 1 : 0)
            }
        }
        .onAppear {
            guard !Motion.reduced else { return shown = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.05)) { shown = true }
        }
    }

    private func go(_ url: URL) {
        guard let tab = browser.active, tab.isBlank else {
            browser.open(url, foreground: true)
            return
        }
        browser.dismiss()
        tab.go(to: url)
    }
}

/// A site's tile: its icon on a soft card, its name under it.
private struct SiteTile: View {
    let site: History.Site
    let order: Int
    let shown: Bool
    let open: () -> Void
    @State private var hovering = false

    private var name: String { site.name }

    /// A colour of its own for a site with no icon yet, the same each time.
    private var hue: Color {
        let sum = site.host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.55, brightness: 0.85)
    }

    var body: some View {
        Button(action: open) {
            VStack(spacing: 8) {
                Group {
                    if let icon = Favicons.shared.cached(for: site.url) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                            .frame(width: 26, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(hue.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .frame(width: 52, height: 52)
                .background(Palette.ground.opacity(hovering ? 0.95 : 0.75), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 10 : 4, y: hovering ? 4 : 1)
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: SpaceHomeBelow.tile)
            .contentShape(Rectangle())
            .scaleEffect(hovering ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .onHover { on in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { hovering = on } }
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 10)
        .animation(Motion.reduced ? nil : .spring(response: 0.5, dampingFraction: 0.8).delay(Double(order) * 0.03), value: shown)
        .help(site.host)
        .accessibilityLabel(site.host)
    }
}

/// A tab closed lately: its icon and title, and back with a click.
private struct ClosedRow: View {
    let title: String
    let url: URL
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 9) {
                Group {
                    if let icon = Favicons.shared.cached(for: url) {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                }
                .frame(width: 14, height: 14)
                Text(title.isEmpty ? (url.host() ?? url.absoluteString) : title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hovering ? Palette.ground.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Reopen \(url.absoluteString)")
    }
}
