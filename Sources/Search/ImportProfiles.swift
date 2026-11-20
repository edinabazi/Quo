import Foundation
import SwiftUI

// Another browser's profiles, each into a profile of its own here, and its
// extensions, fresh from the Chrome Web Store.
//
// A profile here holds its own bookmarks and history (see Profiles.swift),
// so each of the other browser's comes into the one of the same name, made
// if there is none, as Arc's profiles do (see takeArc). Its first profile —
// Chrome's "Default" — comes into this window's, unless another here goes
// by its name. Passwords and extensions are shared by every profile here,
// as in Safari, so they come once, from all of them.

extension Browser {
    /// What one of the other browser's profiles brought, and where to.
    struct ProfileTake: Equatable {
        /// The other browser's name for it.
        let name: String
        /// The profile here it went into.
        let into: UUID
        let made: Bool
        let bookmarks: Int
        let already: Int
        let places: Int
    }

    /// Every profile of `source` that has bookmarks or history to bring,
    /// each into its own profile here. A profile with nothing to bring
    /// makes nothing. `replacing`: what came from this browser before is
    /// taken out of this window's bookmarks first, only when every profile
    /// read cleanly (see takeBookmarks).
    func takeProfiles(from source: ImportSource, bookmarks wantsMarks: Bool, history wantsPlaces: Bool,
                      replacing: Bool = false, then done: @escaping ([ProfileTake]) -> Void) {
        let list = source.profiles
        let first = source.firstProfile
        DispatchQueue.global(qos: .userInitiated).async {
            let read = list.map { profile in
                (profile: profile,
                 marks: wantsMarks ? source.bookmarkRead(profile: profile.id) : (nodes: [Bookmark](), complete: true),
                 places: wantsPlaces ? source.places(profile: profile.id) : [])
            }
            DispatchQueue.main.async {
                if replacing, wantsMarks, read.allSatisfy(\.marks.complete),
                   let earlier = ImportRecords.of(source.name), !earlier.bookmarkIDs.isEmpty {
                    self.bookmarks.withdraw(earlier.bookmarkIDs)
                    ImportRecords.forgetBookmarks(source.name)
                }
                var out: [ProfileTake] = []
                var noted: [UUID] = []
                var marked = 0, visited = 0
                for (profile, marks, places) in read where !marks.nodes.isEmpty || !places.isEmpty {
                    let (target, made) = self.profileHere(for: profile, first: profile.id == first)
                    let mine = target == self.profileID
                    let (added, already, ids) = (mine ? self.bookmarks : Profiles.bookmarks(target))
                        .takeNoting(marks.nodes, from: source.name)
                    if mine { noted += ids }
                    let history = mine ? self.history : Profiles.history(target)
                    for place in places { history.take(place.url, title: place.title, count: place.count, last: place.last) }
                    history.settle()
                    marked += added
                    visited += places.count
                    out.append(ProfileTake(name: profile.name, into: target, made: made,
                                           bookmarks: added, already: already, places: places.count))
                    let urls = Bookmarks.urls(marks.nodes)
                    if !urls.isEmpty {
                        DispatchQueue.global(qos: .utility).async {
                            let icons = source.icons(profile: profile.id, for: urls)
                            Task { @MainActor in
                                for (host, data) in icons { await Favicons.shared.adopt(data, for: host) }
                                self.objectWillChange.send()
                            }
                        }
                    }
                }
                ImportRecords.note(source.name, bookmarks: noted, bookmarks: marked, places: visited)
                done(out)
            }
        }
    }

    /// The profile here for one of the other browser's: the one that goes
    /// by its name, or for its first this window's, or else a new one of
    /// that name, with a first space of its own.
    func profileHere(for profile: ImportSource.Profile, first: Bool) -> (id: UUID, made: Bool) {
        let same = { (other: Profile) in other.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }
        if same(Profiles.shared.profile(profileID)) { return (profileID, false) }
        if let named = Profiles.shared.list.first(where: same) { return (named.id, false) }
        if first { return (profileID, false) }
        return (Profiles.shared.add(named: profile.name).id, true)
    }

    /// What came of the profiles, in a line: "Work (new): 120 bookmarks,
    /// 900 places · Personal: 40 bookmarks".
    static func said(_ takes: [ProfileTake]) -> String {
        func count(_ n: Int, _ one: String) -> String { n == 1 ? "1 \(one)" : "\(n.formatted()) \(one)s" }
        return takes.map { take in
            var parts: [String] = []
            if take.bookmarks > 0 { parts.append(count(take.bookmarks, "bookmark")) }
            if take.places > 0 { parts.append(count(take.places, "place")) }
            if parts.isEmpty, take.already > 0 { parts.append("bookmarks already here") }
            let into = Profiles.shared.profile(take.into).name
            let name = take.name.localizedCaseInsensitiveCompare(into) == .orderedSame ? into : "\(take.name) → \(into)"
            return "\(name)\(take.made ? " (new profile)" : ""): \(parts.isEmpty ? "nothing new" : parts.joined(separator: ", "))"
        }.joined(separator: " · ")
    }
}

/// Bringing another browser's extensions: each fetched fresh from the
/// Chrome Web Store and asked about, one after another, never copied from
/// the other browser's folder. Then what came of it, in a line.
@available(macOS 15.4, *)
@MainActor
enum ExtensionImport {
    struct Result: Equatable {
        var installed: [String] = []
        var declined: [String] = []
        var failed: [(name: String, why: String)] = []

        static func == (a: Result, b: Result) -> Bool {
            a.installed == b.installed && a.declined == b.declined && a.failed.map(\.name) == b.failed.map(\.name)
        }

        var said: String {
            func count(_ n: Int) -> String { n == 1 ? "1 extension" : "\(n) extensions" }
            var parts: [String] = []
            if !installed.isEmpty { parts.append("\(count(installed.count)) installed") }
            if !declined.isEmpty { parts.append("\(declined.count) not wanted") }
            for (name, why) in failed { parts.append("\(name) couldn't be installed: \(why)") }
            return parts.isEmpty ? "No extensions installed" : parts.joined(separator: "; ")
        }
    }

    static func install(_ addons: [ImportSource.Addon]) async -> Result {
        var result = Result()
        let coming = addons.filter(\.comes)
        let progress = ExtensionImportProgress.shared
        for (index, addon) in coming.enumerated() {
            progress.show(.init(name: addon.name, index: index + 1, total: coming.count, step: .downloading))
            switch await Extensions.shared.install(id: addon.id, step: { progress.step($0) }) {
            case .installed: result.installed.append(addon.name)
            case .declined: result.declined.append(addon.name)
            case .already: break
            case .failed(let why): result.failed.append((addon.name, why))
            }
        }
        progress.finish(coming.isEmpty ? nil : result)
        return result
    }

    /// The ones it has that aren't here already.
    static func fresh(_ addons: [ImportSource.Addon]) -> [ImportSource.Addon] {
        let have = Set(Extensions.shared.installed.map(\.id))
        return addons.filter { $0.comes && !have.contains($0.id) }
    }
}

extension ImportSource.Addon {
    /// Names in a line, the first few and how many more: "uBlock Origin
    /// Lite, 1Password and 3 more".
    static func names(_ addons: [ImportSource.Addon], first: Int = 3) -> String {
        let names = addons.map(\.name)
        guard names.count > first + 1 else { return ListFormatter.localizedString(byJoining: names) }
        return names.prefix(first).joined(separator: ", ") + " and \(names.count - first) more"
    }
}

/// Extensions being brought over, one after another: which, how far along
/// the line, and what is happening to it — fetched from the Chrome Web
/// Store, made ready, or waiting on your answer — so the pause between one
/// question and the next says what it is. Then, for a moment, what came of
/// it (ExtensionImportCard).
@available(macOS 15.4, *)
@MainActor
final class ExtensionImportProgress: ObservableObject {
    static let shared = ExtensionImportProgress()

    struct Now: Equatable {
        var name: String
        var index: Int
        var total: Int
        var step: Extensions.InstallStep
    }

    @Published private(set) var now: Now?
    /// What came of the last run, shown for a few seconds once it ends.
    @Published private(set) var ended: ExtensionImport.Result?
    private var turn = 0

    func show(_ now: Now) {
        turn += 1
        ended = nil
        self.now = now
    }

    func step(_ step: Extensions.InstallStep) { now?.step = step }

    func finish(_ result: ExtensionImport.Result?) {
        now = nil
        guard let result else { return }
        ended = result
        let mine = turn
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.turn == mine else { return }
            self.ended = nil
        }
    }
}

/// The card at the window's bottom corner while extensions come over:
/// "Installing ChatGPT · 2 of 7", what is happening to it, and a bar for
/// the line; then what came of it.
@available(macOS 15.4, *)
struct ExtensionImportCard: View {
    @ObservedObject private var progress = ExtensionImportProgress.shared

    var body: some View {
        ZStack {
            if let now = progress.now {
                card(title: now.name, note: Self.said(now.step), count: "\(now.index) of \(now.total)",
                     fraction: (Double(now.index - 1) + Self.share(now.step)) / Double(max(now.total, 1)), busy: now.step != .asking)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let ended = progress.ended {
                card(title: ended.installed.isEmpty ? "No extensions installed" : "Extensions brought over",
                     note: ended.said, count: nil, fraction: 1, busy: false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.settle, value: progress.now)
        .animation(Motion.settle, value: progress.ended)
    }

    static func said(_ step: Extensions.InstallStep) -> String {
        switch step {
        case .downloading: return "Downloading from the Chrome Web Store…"
        case .preparing: return "Getting it ready…"
        case .asking: return "Waiting for your answer"
        }
    }

    /// How far into one extension each step stands, for the bar.
    static func share(_ step: Extensions.InstallStep) -> Double {
        switch step {
        case .downloading: return 0.15
        case .preparing: return 0.6
        case .asking: return 0.85
        }
    }

    private func card(title: String, note: String, count: String?, fraction: Double, busy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: count == nil ? "checkmark.circle.fill" : "questionmark.circle")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.ink.opacity(0.8))
                    }
                }
                .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(count == nil ? title : "Installing \(title)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let count {
                            Text(count)
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
            }
            if count != nil {
                GeometryReader { box in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.ink.opacity(0.1))
                        Capsule().fill(Palette.ink.opacity(0.7))
                            .frame(width: max(6, box.size.width * min(max(fraction, 0), 1)))
                    }
                }
                .frame(height: 4)
                .animation(Motion.settle, value: fraction)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
    }
}
