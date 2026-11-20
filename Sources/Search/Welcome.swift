import AppKit
import SwiftUI

// The first time, as Arc and Dia do it: the whole window, a slow living
// gradient behind frosted cards, each step's words and choices rising in one
// after another. Six steps, every one of them skippable, nothing asked twice:
//
//   1. Welcome: the mark, floating.
//   2. Make it yours: light or dark, where the tabs go, Roomy or Compact,
//      the first space's colour, with a small window that changes as you pick.
//   3. Bring your things: Arc's spaces and pins if Arc is here, or another
//      browser's passwords, bookmarks and history.
//   4. Sync: iCloud, end to end encrypted with no account of ours, or a
//      folder, or not now.
//   5. Fewer ads: the blocker and the lists worth adding, and the default
//      browser.
//   6. All set: the six keys worth knowing.
//
// Always drawn dark, whatever the app is set to: the stage is the same for
// everyone, and the window's own look comes back the moment it is done.
// Under Reduce Motion nothing floats or drifts, and steps cross-fade.

struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var sync = Sync.shared
    @ObservedObject private var lists = FilterLists.shared

    @State private var step = 0
    @State private var forward = true

    // Bringing things over. Nil until one is picked, which means the first.
    @State private var source: ImportSource?
    @State private var wantsPasswords = true
    @State private var wantsHistory = true
    @State private var wantsBookmarks = true
    /// Each of its profiles into a profile of its own here (see takeProfiles).
    @State private var wantsProfiles = true
    /// Its store extensions, fresh from the Chrome Web Store, each asked about.
    @State private var wantsExtensions = true
    /// What is on this Mac, found once off the main thread: the browsers
    /// there is something to read in, and those macOS keeps from this app.
    @State private var found: [ImportSource]?
    @State private var refused: [Chromium.Unavailable] = []
    @State private var allowTrouble: String?
    /// What each holds, by browser and profile ("" for all of them).
    @State private var previews: [String: ImportSource.Preview] = [:]
    /// Each browser's profiles and the one it used last, read with the rest.
    @State private var profileLists: [String: [ImportSource.Profile]] = [:]
    @State private var usual: [String: String] = [:]
    @State private var bringing = false
    @State private var brought: String?
    /// Arc's spaces and pins, brought over once this is done: Bring Things
    /// Over is a tab, which would open under this.
    @State private var arcAfter = false

    @State private var isDefault = Links.isDefault
    @State private var askedDefault = false

    static let steps = 6
    private var reduced: Bool { Motion.reduced }

    init(browser: Browser, prefs: Preferences, step: Int = 0) {
        self.browser = browser
        self.prefs = prefs
        _step = State(initialValue: step)
    }

    var body: some View {
        ZStack {
            Stage(step: step, reduced: reduced)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                top
                Spacer(minLength: 12)
                ZStack {
                    switch step {
                    case 0: welcome
                    case 1: yours
                    case 2: bring
                    case 3: syncing
                    case 4: protection
                    default: done
                    }
                }
                .frame(maxWidth: step == 1 ? 860 : 640)
                .id(step)
                .transition(reduced ? .opacity : .asymmetric(
                    insertion: .offset(x: forward ? 60 : -60).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                    removal: .offset(x: forward ? -60 : 60).combined(with: .opacity).combined(with: .scale(scale: 0.98))
                ))
                Spacer(minLength: 12)
                foot
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .environment(\.colorScheme, .dark)
        .animation(reduced ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86), value: step)
        .transition(.opacity)
    }

    // MARK: - around the steps

    /// The steps so far, as a row of short bars; Skip at the far end.
    private var top: some View {
        HStack {
            Spacer().frame(width: 60)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<WelcomePanel.steps, id: \.self) { i in
                    Capsule()
                        .fill(Color.white.opacity(i <= step ? 0.9 : 0.18))
                        .frame(width: i == step ? 26 : 8, height: 4)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            Spacer()
            ZStack(alignment: .trailing) {
                // Held open on the last step too, so the bars stay centred.
                Color.clear
                if step < WelcomePanel.steps - 1 {
                    Button("Skip") { finish() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .keyboardShortcut(.cancelAction)
                }
            }
            .frame(width: 60, height: 20)
        }
    }

    private var foot: some View {
        HStack(spacing: 12) {
            if step > 0 && step < WelcomePanel.steps - 1 {
                Ghost("Back") { go(-1) }
            }
            Spacer()
            if step > 0 && step < WelcomePanel.steps - 1 {
                Primary("Continue") { go(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: 860)
        .frame(height: 44)
        .opacity(step == 0 || step == WelcomePanel.steps - 1 ? 0 : 1)
    }

    private func go(_ by: Int) {
        forward = by > 0
        step = max(0, min(WelcomePanel.steps - 1, step + by))
    }

    // MARK: - 1. welcome

    private var welcome: some View {
        VStack(spacing: 30) {
            Floating(reduced: reduced) {
                AppMark(height: 96)
                    .shadow(color: .white.opacity(0.22), radius: 40)
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 14)
            }
            .rise(0)
            VStack(spacing: 14) {
                Text("Welcome to \(Store.name)")
                    .font(.system(size: 50, weight: .semibold))
                    .tracking(-1)
                    .foregroundStyle(.white)
                    .rise(1)
                Text("A fast, quiet browser for your Mac, with the habits you love from Arc and Chrome, on the engine already inside it.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
                    .rise(2)
            }
            VStack(spacing: 14) {
                Primary("Get Started", large: true) { go(1) }
                    .keyboardShortcut(.defaultAction)
                Text("A minute or so. Everything here can be changed later in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 8)
            .rise(3)
        }
    }

    // MARK: - 2. make it yours

    private var yours: some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(alignment: .leading, spacing: 20) {
                Heading("Make it yours.", "Pick a look to start with. The window on the right follows along.")
                    .rise(0)
                Glass {
                    VStack(alignment: .leading, spacing: 16) {
                        Row("Appearance") {
                            Chips(options: [(Look.light, "Light", "sun.max"), (Look.dark, "Dark", "moon"), (Look.system, "Auto", "circle.lefthalf.filled")],
                                  selection: $prefs.look)
                        }
                        Row("Tabs") {
                            Chips(options: [(TabsLayout.left, "Left", "sidebar.left"), (TabsLayout.right, "Right", "sidebar.right"), (TabsLayout.top, "Top", "rectangle.topthird.inset.filled")],
                                  selection: Binding(get: { prefs.tabsLayout == .icons ? .left : prefs.tabsLayout },
                                                     set: { layout in withAnimation(Motion.glide) { prefs.tabsLayout = layout } }))
                        }
                        Row("Density") {
                            Chips(options: [(true, "Roomy", "rectangle.expand.vertical"), (false, "Compact", "rectangle.compress.vertical")],
                                  selection: Binding(get: { prefs.roomyTabs }, set: { on in withAnimation(Motion.glide) { prefs.roomyTabs = on } }))
                        }
                        Row("Colour") {
                            // A colour is a space's: picked, spaces come on
                            // to wear it. The wheel beside them is the whole
                            // picker, as the space's Colour… has it.
                            HStack(spacing: 10) {
                                Swatches(selection: Binding(get: { browser.space.colour },
                                                            set: { colour in
                                                                if colour > 0, !prefs.usesSpaces { prefs.usesSpaces = true }
                                                                browser.setSpaceColour(browser.spaceID, to: colour)
                                                            }))
                                WheelButton(browser: browser, prefs: prefs)
                            }
                        }
                    }
                }
                .rise(1)
            }
            .frame(width: 420)
            MiniWindow(layout: prefs.tabsLayout, roomy: prefs.roomyTabs, look: prefs.look,
                       tint: browser.space.tint)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.45, contentMode: .fit)
                .rise(2)
        }
    }

    // MARK: - 3. bring your things

    private var bring: some View {
        let sources = found ?? []
        let chosen = source ?? sources.first
        let arcHere = FileManager.default.fileExists(atPath: Arc.file.path)
        let preview = chosen.flatMap { previews[previewKey($0)] }
        return VStack(alignment: .leading, spacing: 20) {
            Heading("Bring your things.", "Nothing in the other browser changes, and nothing leaves your Mac.")
                .rise(0)
            if arcHere {
                Glass(highlight: true) {
                    HStack(spacing: 16) {
                        Badge(symbol: "square.stack.3d.up.fill")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Coming from Arc?")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("Your spaces, pinned tabs and folders, just as you left them.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 8)
                        if arcAfter {
                            Done("Right after this")
                        } else {
                            Primary("Bring Arc Over") { arcAfter = true }
                        }
                    }
                }
                .rise(1)
            }
            if let chosen {
                Glass {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(sources.count > 1 ? "From" : "From \(chosen.name)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                            if sources.count > 1 {
                                Chips(options: sources.prefix(4).map { ($0, $0.name, nil) },
                                      selection: Binding(get: { chosen }, set: { source = $0; brought = nil; count($0) }))
                            }
                            Spacer()
                        }
                        if chosen.importsPasswords {
                            Toggled("Passwords", counted(preview?.passwords, "Into your Mac's keychain; macOS asks once"), on: $wantsPasswords)
                        }
                        Toggled("Bookmarks", counted(preview?.bookmarks, "Folders and all"), on: $wantsBookmarks)
                        Toggled("History", counted(preview?.places, "So the address field already knows where you go"), on: $wantsHistory)
                        if let list = profileLists[chosen.id], list.count > 1 {
                            Toggled("Profiles", "\(list.count) — \(ListFormatter.localizedString(byJoining: list.map(\.name))), each its own profile here with its own bookmarks and history",
                                    on: Binding(get: { wantsProfiles }, set: { wantsProfiles = $0; brought = nil; count(chosen) }))
                        }
                        let fresh = freshExtensions(preview)
                        if !fresh.isEmpty {
                            Toggled("Extensions", "\(fresh.count) — \(ImportSource.Addon.names(fresh)), fresh from the Chrome Web Store; you say yes to each",
                                    on: $wantsExtensions)
                        }
                        if let left = preview?.leftBehind, !left.isEmpty {
                            Text(left.allSatisfy(\.lookFor)
                                 ? "\(chosen.name)'s add-ons can't run here: \(ImportSource.Addon.names(left, first: 4)). Look for them in the Chrome Web Store."
                                 : "Can't come over: " + left.prefix(4).map { "\($0.name) (\($0.skip ?? ""))" }.joined(separator: ", ")
                                    + (left.count > 4 ? " and \(left.count - 4) more — see Settings › Bring Things Over" : ""))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 12) {
                            if let brought {
                                Done(brought)
                            } else {
                                Primary(bringing ? "Bringing…" : "Bring Them In") { bringAll(from: chosen) }
                                    .disabled(bringing || !((chosen.importsPasswords && wantsPasswords) || wantsHistory || wantsBookmarks
                                                            || (wantsExtensions && !fresh.isEmpty)))
                                if bringing { ProgressView().controlSize(.small) }
                            }
                        }
                        .animation(Motion.settle, value: brought)
                    }
                }
                .rise(arcHere ? 2 : 1)
            }
            // Here, but kept from this app by macOS: said by name with the
            // way to allow it, never "no other browser".
            if !refused.isEmpty {
                Glass {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(refused.indices, id: \.self) { index in
                            let missing = refused[index]
                            HStack(spacing: 16) {
                                Badge(symbol: "lock.fill")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(missing.source.name) is on this Mac")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("macOS keeps its data from other apps until you allow \(Store.name) to read it.")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Primary("Allow Access…") { allow(missing.source) }
                            }
                        }
                        if let allowTrouble {
                            Text(allowTrouble)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .rise(arcHere || chosen != nil ? 3 : 1)
            }
            if found != nil, chosen == nil, refused.isEmpty, !arcHere {
                Glass {
                    Text("No other browser found on this Mac, so there's nothing to bring. You can always bring a file another browser exported, from File › Bring Things Over.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .rise(1)
            }
        }
        .onAppear { if found == nil { look() } }
    }

    /// "312 — Folders and all", or the words alone while counting.
    private func counted(_ n: Int?, _ detail: String) -> String {
        guard let n else { return detail }
        return n == 0 ? "None — \(detail.prefix(1).lowercased() + detail.dropFirst())" : "\(n.formatted()) — \(detail)"
    }

    /// Every profile, each into its own, or the one used most recently.
    private func eachProfile(_ source: ImportSource) -> Bool {
        wantsProfiles && (profileLists[source.id]?.count ?? 0) > 1
    }

    /// The profile read: nil for every one.
    private func profile(of source: ImportSource) -> String? {
        eachProfile(source) ? nil : usual[source.id]
    }

    private func previewKey(_ source: ImportSource) -> String {
        "\(source.id)/\(profile(of: source) ?? "")"
    }

    private func freshExtensions(_ preview: ImportSource.Preview?) -> [ImportSource.Addon] {
        guard #available(macOS 15.4, *), let preview else { return [] }
        return ExtensionImport.fresh(preview.addons)
    }

    /// The browsers on this Mac, found off the main thread, and the first counted.
    private func look() {
        DispatchQueue.global(qos: .userInitiated).async {
            let (readable, missing) = Chromium.present()
            let sources = readable.map(ImportSource.chromium) + Mozilla.installed().map(ImportSource.mozilla)
            let lists = sources.map { ($0.id, $0.profiles, $0.usual) }
            DispatchQueue.main.async {
                for (id, list, last) in lists {
                    profileLists[id] = list
                    usual[id] = last
                }
                found = sources
                refused = missing
                if let first = source ?? sources.first { count(first) }
            }
        }
    }

    private func count(_ source: ImportSource) {
        let key = previewKey(source)
        guard previews[key] == nil else { return }
        let profile = profile(of: source)
        DispatchQueue.global(qos: .userInitiated).async {
            let preview = source.preview(profile: profile)
            DispatchQueue.main.async { previews[key] = preview }
        }
    }

    /// The system's folder panel, opened at the browser's data; allowed, it
    /// joins the others and is picked.
    private func allow(_ browser: Chromium.Source) {
        Chromium.ask(for: browser) { trouble in
            allowTrouble = trouble
            guard trouble == nil else { return }
            source = .chromium(browser)
            brought = nil
            look()
        }
    }

    // MARK: - 4. sync

    private var syncing: some View {
        let cloud = SyncCloud.available
        return VStack(spacing: 26) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.35, green: 0.65, blue: 1).opacity(0.55), .clear],
                                         center: .center, startRadius: 2, endRadius: 70))
                    .frame(width: 140, height: 140)
                Image(systemName: "icloud.fill")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(.white)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(red: 0.2, green: 0.45, blue: 1))
                            .padding(6)
                            .background(Circle().fill(.white))
                            .offset(x: 10, y: 6)
                    }
            }
            .rise(0)
            VStack(spacing: 10) {
                Text("Your browser, on every Mac.")
                    .font(.system(size: 36, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                Text("Spaces, pins, bookmarks and settings, kept in step through your own iCloud.")
                    .font(.system(size: 15.5))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .rise(1)
            Glass {
                VStack(alignment: .leading, spacing: 16) {
                    Point("lock.shield.fill", "End-to-end encrypted", "Sealed with a key only your devices hold. Not even Apple can read it, and neither can we.")
                    Point("person.crop.circle.badge.checkmark", "No account to make", "Your Apple ID is all it takes. No password, no email, nothing to sign up for.")
                    Point("hand.raised.fill", "Nothing on our servers", "There aren't any. Everything stays in your own iCloud.")
                    Point("bolt.fill", "In moments", "A pin added on one Mac is on the others before you've switched.")
                }
            }
            .frame(maxWidth: 560)
            .rise(2)
            HStack(spacing: 12) {
                if sync.cloud {
                    Done("Syncing with iCloud")
                } else if sync.folder != nil {
                    Done("Syncing through a folder")
                } else {
                    if cloud {
                        Primary("Sync with iCloud", large: true) { sync.turnOnCloud() }
                    }
                    Ghost(cloud ? "Use a Folder Instead…" : "Sync Through a Folder…") { sync.choose() }
                }
            }
            .animation(Motion.settle, value: sync.way)
            .rise(3)
            if !cloud, !sync.on {
                Text("This copy of \(Store.name) isn't set up for iCloud yet, so a folder in iCloud Drive or Dropbox does the same job for now.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .rise(4)
            }
        }
    }

    // MARK: - 5. fewer ads

    private var protection: some View {
        let popular = FilterLists.suggested.filter { $0.within == nil }.prefix(3)
        return VStack(alignment: .leading, spacing: 20) {
            Heading("Fewer ads, less tracking.", "Blocked before the page even loads: pages come in faster and follow you around less.")
                .rise(0)
            Glass {
                VStack(alignment: .leading, spacing: 14) {
                    Toggled("Block ads and trackers", "\(Store.name)'s own blocker, built into the engine", on: $prefs.shielded)
                    if prefs.shielded {
                        Divider().overlay(Color.white.opacity(0.1))
                        Text("Add the lists other blockers use")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                        ForEach(Array(popular)) { list in
                            Toggled(list.name, list.what, on: Binding(
                                get: { lists.sources.contains { $0.origin == list.origin } },
                                set: { on in
                                    if on { lists.add(list.origin) } else if let added = lists.sources.first(where: { $0.origin == list.origin }) {
                                        lists.remove(added.id)
                                    }
                                }))
                        }
                    }
                }
                .animation(Motion.settle, value: prefs.shielded)
            }
            .rise(1)
            Glass {
                HStack(spacing: 16) {
                    Badge(symbol: "link")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Open links in \(Store.name)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Links from Mail, Slack and everywhere else land here.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 8)
                    if isDefault {
                        Done("Default browser")
                    } else {
                        Primary(askedDefault ? "Asked…" : "Make Default") {
                            askedDefault = true
                            Links.becomeDefault { _ in isDefault = Links.isDefault }
                        }
                    }
                }
                .animation(Motion.settle, value: isDefault)
            }
            .rise(2)
        }
    }

    // MARK: - 6. all set

    private var done: some View {
        ZStack {
            Confetti(reduced: reduced)
                .allowsHitTesting(false)
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Text("You're all set.")
                        .font(.system(size: 50, weight: .semibold))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    Text("Six keys worth knowing. Every other one is in Settings › Keyboard & Mouse.")
                        .font(.system(size: 15.5))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .rise(0)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    Keycap("⌘T", "Go anywhere", delay: 1)
                    Keycap("⌘S", "Hide the sidebar", delay: 2)
                    Keycap("⌃Tab", "Recent tabs", delay: 3)
                    Keycap("⌘K", "Find a tab", delay: 4)
                    Keycap("⌥⌘N", "Split View", delay: 5)
                    Keycap("⇧⌘P", "Float a video", delay: 6)
                }
                .frame(maxWidth: 560)
                Primary("Start Browsing", large: true) { finish() }
                    .keyboardShortcut(.defaultAction)
                    .rise(7)
            }
        }
    }

    // MARK: - doing

    private func bringAll(from source: ImportSource) {
        let each = eachProfile(source)
        let profile = profile(of: source)
        let extensions = wantsExtensions ? freshExtensions(previews[previewKey(source)]) : []
        bringing = true
        var lines: [String] = []
        let group = DispatchGroup()
        if wantsPasswords && source.importsPasswords {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = Result { try source.read(profile: profile) }
                DispatchQueue.main.async {
                    switch outcome {
                    case .success(let found):
                        let kept = browser.keep(found)
                        ImportRecords.note(source.name, passwords: kept)
                        lines.append("\(kept) passwords")
                    case .failure(Chromium.Trouble.noPassphrase):
                        lines.append("passwords need macOS's OK")
                    case .failure:
                        lines.append("no passwords readable")
                    }
                    group.leave()
                }
            }
        }
        if each, wantsBookmarks || wantsHistory {
            group.enter()
            browser.takeProfiles(from: source, bookmarks: wantsBookmarks, history: wantsHistory) { takes in
                let marks = takes.reduce(0) { $0 + $1.bookmarks }
                let places = takes.reduce(0) { $0 + $1.places }
                let made = takes.filter(\.made).count
                if wantsBookmarks { lines.append("\(marks) bookmarks") }
                if wantsHistory { lines.append("\(places) places") }
                if made > 0 { lines.append(made == 1 ? "1 new profile" : "\(made) new profiles") }
                group.leave()
            }
        } else {
            if wantsBookmarks {
                lines.append("\(browser.takeBookmarks(from: source, profile: profile).added) bookmarks")
            }
            if wantsHistory {
                group.enter()
                browser.takePlaces(from: source, profile: profile) { count in
                    lines.append("\(count) places")
                    group.leave()
                }
            }
        }
        if #available(macOS 15.4, *), !extensions.isEmpty {
            // Asked about one at a time; the step can be left meanwhile.
            lines.append(extensions.count == 1 ? "1 extension to confirm" : "\(extensions.count) extensions to confirm")
            Task { @MainActor in
                let result = await ExtensionImport.install(extensions)
                browser.announce(result.said)
            }
        }
        group.notify(queue: .main) {
            bringing = false
            brought = lines.joined(separator: " · ")
            browser.relist()
        }
    }

    private func finish() {
        prefs.welcomed = true
        withAnimation(Motion.settle) { browser.welcoming = false }
        if arcAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                browser.lead(to: InternalPage(.importing, "Arc"))
            }
        }
    }
}

// MARK: - the stage

/// The gradient behind it all: slow, soft, a little different on each step.
private struct Stage: View {
    let step: Int
    let reduced: Bool

    /// Four colours a step, from the deep corner to the bright one.
    static let palettes: [[Color]] = [
        [rgb(0x0B0A1F), rgb(0x2A1B6E), rgb(0x5B3FD6), rgb(0x0F5D7A)],   // welcome: violet into teal
        [rgb(0x140B1E), rgb(0x5A1E5C), rgb(0xD0487C), rgb(0x2B1A6B)],   // make it yours: magenta
        [rgb(0x08141F), rgb(0x0E3B5C), rgb(0x2E86C1), rgb(0x1B2A6B)],   // bring: ocean
        [rgb(0x050B1C), rgb(0x0B2A6B), rgb(0x2F7BFF), rgb(0x5FB8FF)],   // sync: iCloud blue
        [rgb(0x07150F), rgb(0x0D4A3A), rgb(0x1FA67A), rgb(0x1B3B6B)],   // protection: green
        [rgb(0x1A0A12), rgb(0x6B1E3A), rgb(0xF0784C), rgb(0x5B3FD6)],   // all set: sunset
    ]

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    var body: some View {
        let colors = Stage.palettes[min(step, Stage.palettes.count - 1)]
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced)) { time in
            let t = reduced ? 0 : time.date.timeIntervalSinceReferenceDate
            ZStack {
                colors[0]
                field(colors, t: t)
                // A soft shade at the foot, for the buttons to stand on.
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 1.1), value: step)
    }

    @ViewBuilder
    private func field(_ c: [Color], t: Double) -> some View {
        if #available(macOS 15.0, *) {
            let s = Swift.Float(Foundation.sin(t * 0.21)), k = Swift.Float(Foundation.cos(t * 0.17))
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + 0.08 * s, 0], [1, 0],
                [0, 0.5 + 0.1 * k], [0.5 + 0.12 * k, 0.5 + 0.1 * s], [1, 0.5 - 0.1 * k],
                [0, 1], [0.5 - 0.08 * s, 1], [1, 1],
            ], colors: [
                c[0], c[1], c[0],
                c[3], c[2], c[1],
                c[0], c[3], c[0],
            ], smoothsColors: true)
        } else {
            ZStack {
                RadialGradient(colors: [c[2].opacity(0.85), .clear], center: UnitPoint(x: 0.5 + 0.12 * Foundation.cos(t * 0.17), y: 0.45),
                               startRadius: 10, endRadius: 520)
                RadialGradient(colors: [c[3].opacity(0.7), .clear], center: UnitPoint(x: 0.1, y: 0.8 + 0.05 * Foundation.sin(t * 0.21)),
                               startRadius: 10, endRadius: 460)
                RadialGradient(colors: [c[1].opacity(0.8), .clear], center: UnitPoint(x: 0.9, y: 0.1), startRadius: 10, endRadius: 420)
            }
        }
    }
}

// MARK: - pieces

private extension View {
    /// In from a little below, blurred to sharp, the `order`th on its step.
    func rise(_ order: Int) -> some View { modifier(Rise(order: order)) }
}

private struct Rise: ViewModifier {
    let order: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduced ? 0 : 14)
            .blur(radius: shown || Motion.reduced ? 0 : 6)
            .onAppear {
                withAnimation(Motion.reduced ? .easeOut(duration: 0.2)
                              : .spring(response: 0.6, dampingFraction: 0.85).delay(0.08 + Double(order) * 0.07)) {
                    shown = true
                }
            }
    }
}

/// Drifting up and down a few points, forever.
private struct Floating<Content: View>: View {
    let reduced: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduced)) { time in
            let t = time.date.timeIntervalSinceReferenceDate
            content()
                .offset(y: reduced ? 0 : 5 * Foundation.sin(t * 1.3))
                .rotationEffect(.degrees(reduced ? 0 : 1.5 * Foundation.sin(t * 0.9)))
        }
    }
}

private struct Heading: View {
    let title: String
    let line: String
    init(_ title: String, _ line: String) { self.title = title; self.line = line }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 36, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(.white)
            Text(line)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.62))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A frosted card.
private struct Glass<Content: View>: View {
    var highlight = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(Color.white.opacity(highlight ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(highlight ? 0.4 : 0.22), .white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }
}

private struct Row<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control
    init(_ title: String, @ViewBuilder control: @escaping () -> Control) { self.title = title; self.control = control }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 92, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }
}

/// Choices as glass chips; the chosen one lit, the light sliding between.
private struct Chips<Option: Hashable>: View {
    let options: [(Option, String, String?)]
    @Binding var selection: Option
    @Namespace private var lit

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option, title, symbol in
                let on = option == selection
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = option } } label: {
                    HStack(spacing: 5) {
                        if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                        Text(title).font(.system(size: 12.5, weight: .medium))
                    }
                    .foregroundStyle(on ? Color.black : .white.opacity(0.75))
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background {
                        if on {
                            Capsule().fill(.white).matchedGeometryEffect(id: "lit", in: lit)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// The wheel's own swatch, after the five: every hue round a ring. It opens
/// the space's whole picker — the wheel, gradients, grain — in a popover;
/// whatever is picked there turns spaces on to wear it, as a swatch does.
private struct WheelButton: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @State private var open = false
    @State private var hovering = false

    private var custom: Bool {
        let space = browser.space
        return space.gradient != nil || (space.look != nil && space.colour == 0) || space.grain != nil
    }

    var body: some View {
        Button { open = true } label: {
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red],
                                              center: .center))
                Circle().fill(RadialGradient(colors: [.white.opacity(0.85), .white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: 9))
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.55))
                    .opacity(custom ? 0 : 1)
            }
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay(Circle().strokeBorder(.white, lineWidth: custom ? 2 : 0))
            .scaleEffect(hovering || custom ? 1.08 : 1)
            .rotationEffect(.degrees(hovering && !Motion.reduced ? 30 : 0))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { on in withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { hovering = on } }
        .help("More colours, gradients and grain")
        .accessibilityLabel("More colours")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            SpaceLookPicker(browser: browser, id: browser.spaceID)
                // A drag the popover closed under keeps nothing but what was.
                .onDisappear { if LookDraft.shared.preview != nil { LookDraft.shared.end() } }
        }
        .onChange(of: browser.space.look) { _, look in
            if look != nil, !prefs.usesSpaces { prefs.usesSpaces = true }
        }
    }
}

/// The first space's colour: none, then the five.
private struct Swatches: View {
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Spaces.colours.indices, id: \.self) { i in
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = i } } label: {
                    ZStack {
                        if i == 0 {
                            Circle().strokeBorder(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        } else {
                            Circle().fill(Spaces.colours[i])
                        }
                    }
                    .frame(width: 22, height: 22)
                    .padding(3)
                    .overlay(Circle().strokeBorder(.white, lineWidth: selection == i ? 2 : 0))
                    .scaleEffect(selection == i ? 1.08 : 1)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(Spaces.colourNames[i])
            }
        }
    }
}

/// A small drawing of the window, as it will look with what is picked.
private struct MiniWindow: View {
    let layout: TabsLayout
    let roomy: Bool
    let look: Look
    let tint: Color?

    private var dark: Bool { look == .dark || (look == .system && NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua) }
    private var ground: Color { dark ? Color(white: 0.11) : Color(white: 0.96) }
    private var page: Color { dark ? Color(white: 0.16) : .white }
    private var ink: Color { dark ? .white : .black }

    var body: some View {
        GeometryReader { box in
            let w = box.size.width, h = box.size.height
            let side = w * 0.27, row: CGFloat = roomy ? h * 0.075 : h * 0.058
            let strip = row * 1.6 + 10
            let pageRect: CGRect = {
                switch layout {
                case .top: return CGRect(x: 8, y: strip, width: w - 16, height: h - strip - 8)
                case .right: return CGRect(x: 8, y: 8, width: w - side - 12, height: h - 16)
                default: return CGRect(x: side + 4, y: 8, width: w - side - 12, height: h - 16)
                }
            }()
            ZStack(alignment: .topLeading) {
                ground
                if let tint { tint.opacity(dark ? 0.16 : 0.1) }
                // The page, a card beside or under the tabs.
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(page)
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                    .frame(width: pageRect.width, height: pageRect.height)
                    .offset(x: pageRect.minX, y: pageRect.minY)
                // Lines of a page.
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.75)).frame(width: pageRect.width * 0.45, height: 9)
                    ForEach(0..<5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.12)).frame(width: pageRect.width * (i == 4 ? 0.5 : 0.8), height: 5)
                    }
                }
                .offset(x: pageRect.minX + 18, y: pageRect.minY + 22)
                // The tabs.
                if layout == .top {
                    HStack(spacing: 4) {
                        lights.padding(.trailing, 8)
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 5).fill(ink.opacity(i == 0 ? 0.14 : 0.06))
                                .frame(width: (w - 90) / 4.6, height: row)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: strip)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        if layout != .right { lights.padding(.bottom, 6) } else { Spacer().frame(height: 14) }
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.08)).frame(height: roomy ? row * 1.15 : row)
                            }
                        }
                        .padding(.bottom, 4)
                        ForEach(0..<5, id: \.self) { i in
                            HStack(spacing: 6) {
                                Circle().fill(ink.opacity(0.3)).frame(width: row * 0.42, height: row * 0.42)
                                RoundedRectangle(cornerRadius: 2).fill(ink.opacity(0.3)).frame(height: roomy ? 5 : 4)
                            }
                            .padding(.horizontal, 7)
                            .frame(height: row)
                            .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(i == 0 ? 0.12 : 0)))
                        }
                    }
                    .padding(10)
                    .frame(width: side, alignment: .topLeading)
                    .offset(x: layout == .right ? w - side : 0)
                }
                if layout == .right { lights.offset(x: 14, y: 14) }
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 40, y: 24)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: layout)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: roomy)
            .animation(.easeInOut(duration: 0.35), value: look)
        }
    }

    private var lights: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 8, height: 8)
        }
    }
}

private struct Primary: View {
    let title: String
    var large = false
    let act: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    init(_ title: String, large: Bool = false, act: @escaping () -> Void) {
        self.title = title
        self.large = large
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: large ? 15 : 13.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, large ? 26 : 18)
                .frame(height: large ? 46 : 36)
                .background(Capsule().fill(.white))
                .shadow(color: .white.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 18 : 10)
                .scaleEffect(hovering && enabled ? 1.03 : 1)
                .opacity(enabled ? 1 : 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
    }
}

private struct Ghost: View {
    let title: String
    let act: () -> Void
    @State private var hovering = false
    init(_ title: String, act: @escaping () -> Void) { self.title = title; self.act = act }

    var body: some View {
        Button(action: act) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.95 : 0.75))
                .padding(.horizontal, 18)
                .frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.14 : 0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A button that gives a little under the press.
private struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// What was done, said with a tick that pops in.
private struct Done: View {
    let text: String
    @State private var shown = false
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                .scaleEffect(shown ? 1 : 0.3)
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { shown = true } }
    }
}

private struct Toggled: View {
    let title: String
    let detail: String
    @Binding var on: Bool
    init(_ title: String, _ detail: String, on: Binding<Bool>) { self.title = title; self.detail = detail; _on = on }

    var body: some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { on.toggle() } } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 8)
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.white.opacity(0.16))
                        .frame(width: 40, height: 24)
                    Circle().fill(.white).frame(width: 20, height: 20).padding(2)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One of the reasons on the sync step.
private struct Point: View {
    let symbol: String
    let title: String
    let line: String
    init(_ symbol: String, _ title: String, _ line: String) { self.symbol = symbol; self.title = title; self.line = line }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(line).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Badge: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom)))
    }
}

/// A key worth knowing, coming in on its turn.
private struct Keycap: View {
    let keys: String
    let what: String
    let delay: Int
    init(_ keys: String, _ what: String, delay: Int) { self.keys = keys; self.what = what; self.delay = delay }

    var body: some View {
        VStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minWidth: 58, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 0, y: 2)
            Text(what)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.05)))
        .rise(delay)
    }
}

/// A short burst of colour as the last step comes in.
private struct Confetti: View {
    let reduced: Bool
    @State private var start = Date()

    private struct Bit {
        let angle: Double, speed: Double, spin: Double, size: CGFloat, color: Color, delay: Double
    }

    private static let bits: [Bit] = {
        var generator = SystemRandomNumberGenerator()
        let colors: [Color] = [.white, Color(red: 1, green: 0.47, blue: 0.3), Color(red: 0.36, green: 0.25, blue: 0.84),
                               Color(red: 0.36, green: 0.72, blue: 1), Color(red: 1, green: 0.78, blue: 0.3), Color(red: 0.3, green: 0.85, blue: 0.5)]
        return (0..<70).map { _ in
            Bit(angle: Double.random(in: -Double.pi...0, using: &generator),
                speed: Double.random(in: 260...620, using: &generator),
                spin: Double.random(in: -6...6, using: &generator),
                size: CGFloat.random(in: 4...8, using: &generator),
                color: colors.randomElement(using: &generator) ?? .white,
                delay: Double.random(in: 0...0.25, using: &generator))
        }
    }()

    var body: some View {
        if reduced {
            EmptyView()
        } else {
            TimelineView(.animation) { time in
                let elapsed = time.date.timeIntervalSince(start)
                Canvas { context, size in
                    let origin = CGPoint(x: size.width / 2, y: size.height * 0.42)
                    for bit in Confetti.bits {
                        let t = elapsed - bit.delay
                        guard t > 0, t < 2.6 else { continue }
                        let x = origin.x + cos(bit.angle) * bit.speed * t
                        let y = origin.y + sin(bit.angle) * bit.speed * t + 420 * t * t
                        var piece = context
                        piece.opacity = max(0, 1 - t / 2.6)
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(bit.spin * t))
                        piece.fill(Path(roundedRect: CGRect(x: -bit.size / 2, y: -bit.size / 4, width: bit.size, height: bit.size / 2), cornerRadius: 1),
                                   with: .color(bit.color))
                    }
                }
            }
            .onAppear { start = Date() }
        }
    }
}
