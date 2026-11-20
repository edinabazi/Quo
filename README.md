# Quo

A fast, quiet browser for the Mac, with Arc's habits and none of Chromium's weight.

**[Download the latest release →](https://github.com/razegrowth/Quo/releases/latest)** · macOS 14 or later (extensions need 15.4) · free · updates itself

Quo runs on **WebKit**, the engine already inside every Mac, so the app is small, opens instantly and goes easy on the battery: there's no second copy of Chromium to download, update and keep in memory. Tabs sit down the side, the page takes the rest, and nothing asks for your attention.

Quo began as a fork of [Search](https://github.com/driceroland/Search) by [Office Commun](https://officecommun.com) and has grown into its own app. Every change made since is listed in [IMPROVEMENTS.md](IMPROVEMENTS.md).

---

## Tabs, spaces and pins

- **Tabs down the side**, Roomy or Compact, or across the top if you prefer. With the address bar above the page, the column lines up with the page's card. `⌘S` folds the column away.
- **Spaces** keep separate sets of tabs, each in its own colour or gradient picked on a colour wheel, with film grain if you like. Switch with `⌃1`–`⌃9`, `⌥⌘←` and `⌥⌘→`, or a two-finger swipe.
- **Profiles** give spaces their own sign-ins, history and bookmarks, all in one window. Links to sites you choose can always open in their space.
- **Pins that keep their site.** A pin stays on its site: a link elsewhere opens in a new tab beside it, and `⌘W` takes the pin back home. Pins are squares or rows, and rows go in folders, as in Arc.
- **Split View**: two pages side by side. `⌥`-click a tab, drag one onto a page, or press `⌥⌘N`.
- **Tab groups**, a **side panel** for a website you keep beside the page, **Peek** (open a link in a panel over the page you're reading), and **downloads as cards** in the column.
- **An empty tab is your space's home**: its name, the sites you visit most and the tabs you closed last.
- **Tabs that cost nothing when idle.** Tabs from last time come back instantly and load when you click them. Tabs you leave alone sleep, and you can keep chosen sites awake.

## Getting anywhere

- **`⌘T` floats a field over the page**, as Arc's command bar does. Before you type it lists the tabs you were last in, a Switch to Tab away. As you type it offers matching open tabs, your bookmarks, the places you've been, a search, and every menu command and Settings page.
- **An address bar above the page** shows the whole address, with back, forward, reload and your extensions.
- **One field for everything.** Type an address and you go there; type words and you search. It finishes addresses from your own history. A word before your search sends it to a site (`red` and Tab searches Reddit), and you can pick which engine Shift-Return uses.
- **`⌘K`** lists your open tabs by name. **`⌃Tab`** walks between recent tabs.
- **Links from other apps** open in a small window to read and close, or keep with Open in Quo (`⌘O`). It springs open and flies into place in the browser when kept.
- **The address field from any app**, on a key of your own, as Spotlight does.
- **Right-click an address you've selected** to go to it.

## Reading and watching

- **Reading mode** (`⌥⌘R`) strips a page down to the article, light or dark with the window.
- **Hide anything for good.** Press `⇧⌘H`, then click a cookie banner, an overlay or a sidebar of clutter. It stays gone on that site, before the page draws a frame.
- **Float the video** (`⇧⌘P`) in a window above everything, including other apps. A live stream fills it.
- **Translate pages on this Mac.** Nothing is sent anywhere to translate them.
- **Darken pages that stay light**, capture an area or a whole page, add your own CSS to a site, and scroll at 120 Hz.

## Privacy and blocking

- **An ad blocker that runs before the page.** Trackers and ad networks are stopped inside WebKit's networking, so there's nothing to render and nothing to slow down. YouTube's ads too.
- **Filter lists** such as EasyList, EasyPrivacy, Fanboy's Annoyances or your own are compiled into WebKit's rules and kept up to date.
- **Cross-site tracking prevention**, click trackers stripped from links, and Global Privacy Control on every request.
- **Private tabs** (`⇧⌘N`) have their own cookie jar and leave nothing behind.
- **No telemetry, no analytics, no account.** The only things that leave your Mac are the pages you ask for, their icons, a check for updates, and sync if you turn it on.

## Passwords and sign-ins

- **Passwords in your Mac's keychain**, shown with Touch ID. Quo offers to save a sign-in once it has worked, and offers your accounts under a sign-in box when you click it. It never fills anything on its own.
- **Apple's Passwords app**: its accounts and verification codes can come up under their box too.
- **Your contact card** fills name, email, phone and address boxes.

## Extensions

- **Chrome extensions, without Chrome.** Add them from the Chrome Web Store or load your own folder. They run on WebKit's extension engine, and Quo fills in the Chrome APIs WebKit lacks: bookmarks, history, downloads, side panel, notifications, OAuth sign-in and more.
- **Agent extensions can work the page.** Claude, ChatGPT's agent and anything else that uses Chrome's `debugger` can click, type, scroll and take screenshots in a tab.
- **Each extension runs where you say**: on every site, on sites you name, or only when you click its button. One that's slowing pages down is offered On click, and tools like SEO and font inspectors start that way.

## Your things, on every Mac

- **Sync through iCloud**: spaces, pins, bookmarks and settings, in your own private iCloud, with no server or account of ours. Or sync through a folder you choose.
- **Bring things over** from Chrome, Arc, Dia, Brave, Edge, Vivaldi, Firefox or Zen: every profile, with its bookmarks, history, passwords and extensions. Arc's spaces, pins and folders come too.
- **An onboarding** sets it up your way: the look, where the tabs go, a colour, what to bring over, and the default browser.

## For coding agents

Claude Code or Codex can browse in tabs of their own while you watch (Settings › About › Developer). Quo asks each time one connects and shows a Stop button while it's there.

---

## Keyboard

| | |
|---|---|
| `⌘L` address · `⌘T` new tab · `⌘K` switch tab · `⌘W` close · `⇧⌘T` reopen | `⌘[` `⌘]` back, forward · `⌘1`–`⌘9` jump to a tab |
| `⌃1`–`⌃9` spaces · `⌥⌘←` `⌥⌘→` previous, next space | `⌘S` fold the column · `⌥⌘N` split the page |
| `⌘R` reload · `⇧⌘R` reload from the server · `⌥⌘R` reading mode | `⇧⌘P` float the video · `⇧⌘H` hide something · `⇧⌘B` bookmark |
| `⌘F` find · `⇧⌘C` copy address · `⇧⌘V` paste and go | `⌘Y` history · `⇧⌘J` downloads · `⌘,` settings · `⌥⌘L` passwords |

Every shortcut can be changed in Settings › Keyboard & Mouse.

## Privacy, concretely

| What | Where it is | Who can read it |
|---|---|---|
| Passwords | Your login keychain, as items tagged `Quo` | Quo. Any other app gets the system's permission dialog. |
| History, bookmarks, tabs, hidden elements | `~/Library/Application Support/Quo/` | You. |
| Synced spaces, pins, bookmarks, settings | Your private iCloud database, in CloudKit's encrypted fields, if you turn sync on | You, on your Macs. |
| Cookies and site data | WebKit's own store for Quo | The sites that set them, as in any browser. |
| Extensions | `~/Library/Application Support/Quo/Extensions/` and WebKit's extension store | Each extension, within the permissions you gave it. |

---

## Building it

macOS 14 or later, with Xcode 16 or a Swift 6 toolchain. No dependencies beyond what ships with macOS.

```bash
./quo.sh            # build/Quo.app
./quo.sh install    # the same, then into /Applications (quits Quo first)
```

It signs with the first Developer ID certificate in your keychain, or ad hoc if there's none (then the first launch needs right-click › Open).

The code, file names and module still say Search, so changes from upstream merge cleanly. The app takes its name at runtime: `quo.sh` is `build.sh` with Quo's name, bundle ID (`com.edinabazi.quo`), icon and update feed. `./build.sh` on its own makes a plain `build/Search.app`.

For quick checks, `swift build` compiles and `swift test --parallel` runs the unit tests. The `Tests/*.py` scripts drive a hidden copy of the app through its test socket, in a profile of its own that's wiped afterwards; the browser you use is never touched. To try a build without touching your data:

```bash
open -n --env SEARCH_PROBE=mytest build/Search.app
```

### Releases and updates

Every Quo checks `https://github.com/razegrowth/Quo/releases/latest/download/appcast.json.zip`, a feed signed with the app's Developer ID. When it names a newer build, Quo fetches the ZIP, checks its hash and signature, and swaps it in for the next launch.

To release, set `QUO_VERSION`, add a `## <version> · <date>` section to `QUO_NOTES.md` (its first paragraph is the line under the version in Settings), commit and push, then:

```bash
./quo.sh release 0.2.1
```

That builds with the Developer ID and `Quo.provisionprofile` (git-ignored), notarizes the disk image and the ZIP, checks the signed feed, and publishes the GitHub release with `Quo.dmg`, `Quo.zip` and the feed. It refuses to run with uncommitted or unpushed changes, or notes that don't name the version. It needs a notarytool profile called `quo`, made once:

```bash
xcrun notarytool store-credentials quo --apple-id <your Apple ID> --team-id 8B6VFDJHA2
```

`Tests/quo_update.py` checks the whole update path against a local server.

### iCloud sync

Sync through iCloud needs a build signed for the `iCloud.com.edinabazi.quo` container. The App ID `com.edinabazi.quo` needs iCloud (CloudKit) and Push Notifications, and its Developer ID profile is saved here as `Quo.provisionprofile`. The record type is made once in CloudKit's development environment and deployed to Production in the CloudKit Console. Without the profile, Quo builds as before and offers only folder sync. `Tests/sync_icloud.py` plays two Macs against a folder, and `Tests/sync_icloud_real.py` against the real iCloud.

### Keeping up with Search

`origin` is this repository; `upstream` is Search.

```bash
git fetch upstream
git merge upstream/main
./quo.sh install
```

How the code is laid out (one file per concern in `Sources/Search/`, the `./bench` test socket, the extension shims) is in [Search's README](https://github.com/driceroland/Search#for-developers), and still applies.

## License

MIT, as Search is: see [LICENSE](LICENSE). The original code is Office Commun's and its contributors', with Quo's changes on top. "Search" and its icon belong to Office Commun; Quo has its own icon (`Icon/Quo.icon`). `Sources/Search/FilterList.swift` is a port of [adblock-rust](https://github.com/brave/adblock-rust) and stays under its licence, the Mozilla Public License 2.0.
