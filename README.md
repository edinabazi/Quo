# Quo

A personal fork of [Search](https://github.com/driceroland/Search), the small, fast WebKit browser for the Mac by [Office Commun](https://officecommun.com).

Quo keeps everything Search is (tabs down the side or across the top, an ad blocker that runs before the page, passwords in your keychain, Chrome extensions on WebKit, about 10 MB on disk) and goes its own way on a few things Search decided against.

Short, and quick to type: Q-U-O rolls across the top row of the keyboard.

---

## What's different from Search

The running list of everything Quo improves on Search is in [IMPROVEMENTS.md](IMPROVEMENTS.md); the main things are below.

### An address bar above the page

On for a new install, along with the tabs down the side and Roomy. Switch it in **Settings › Tabs › Address bar above the page**. It only applies with the tabs down the side. A Quo that ran before this keeps what it had.

- **The whole address, always.** The site in ink, the path and query dimmed after it, as Chrome and Dia show it. "Not secure" and look-alike domains still show, exactly as in the tab.
- **Back, forward and reload** move from the top of the column into the bar.
- **Extensions move to the bar's far end**, out of the column's foot.
- **The column shows page titles only.** The bar has the address, so the tab no longer swaps its title for it.
- **Click the address, or press ⌘L,** to edit it right there, with the same suggestions and site card as editing in the tab. Right-click for Copy Address.
- It folds away with the column (⌘S) and when a video takes the screen, as the bookmarks bar does.

### Roomy or Compact

**Settings › Appearance › Size › Density**: Roomy, the default for a new install, or Compact, as Search is. Roomy gives the column taller tabs with larger titles, and the rest of the chrome follows: the address bar's field is as tall as a tab, its buttons are larger, the ⌘T / ⌘L field and its suggestions are a size up, and Settings itself has taller rows, larger words and more space between its sections. (It was Roomier tabs, under Tabs; a choice made there is kept.)

### Arc's habits, on from the start

Search has most of what Arc taught people, but starts plain and leaves them off. A new install of Quo starts with them on, for anyone coming from Arc or Dia:

- **Spaces**, switched with ⌃1–9 or a two-finger swipe over the tabs.
- **⌘T in a floating field** over the page, like Arc's command bar, with your **last three places** in it before you type, and **commands** ("settings", "new tab") typed into the address field.
- **Pinned rows** under the pin squares, and **folders** in them.

Already on in Search too: pins that keep their site, Peek (shift-click a link), the small window for links from other apps, Tab to search a site, Split View and ⌃Tab. Closing tabs you leave alone stays off: Arc's 12 hours surprises anyone from Chrome, and it's one choice away in Settings › Tabs. A Quo that ran before keeps what it had; Settings › Spaces & Pins › Set Up Like Arc turns the main ones on in one go.

### Filter lists for the built-in blocker

Search's blocker is a short hand-written list. Quo's can also take the lists every other blocker uses: **Settings › Privacy › Filter lists › Add…**, then an address or a file. Good ones to start with:

- `https://easylist.to/easylist/easylist.txt` (ads)
- `https://easylist.to/easylist/easyprivacy.txt` (trackers)

Each list is turned into WebKit's own rules and compiled once, a few seconds for a big one, then loads instantly at launch. It updates as often as the list asks. The site card's switch turns them off for one site along with the rest of the blocker. What WebKit's rules can't express (scriptlets, redirects, `:has-text()` and the like) is skipped and counted on the list's row. So a page that fights ad blockers can still get its way where uBlock Origin Lite's scriptlets would stop it.

This is [driceroland/Search#738](https://github.com/driceroland/Search/pull/738) by [@oddharsh](https://github.com/oddharsh), which Search closed to stay small.

### Pins keep their site

A link in a pinned tab that leads to another site, or another site's address typed into it (in its row, the address bar or ⌘L), opens in a new tab beside it, and the pin stays where it was, as in Dia. Search opens such links in a Peek over the pin instead; that is still a choice in **Settings › Spaces & Pins › Links to other sites open in**. A page of the pin's own site still loads in the pin.

### Chrome's reload keys

**⇧⌘R** reloads the page from the server, skipping the cache, as in Chrome. Reading Mode moves to **⌥⌘R**. Search has them the other way round, as Safari does. Both can be changed in Settings › Keyboard & Mouse.

### Its own app

Quo runs beside an installed Search without sharing anything with it:

| | Search | Quo |
|---|---|---|
| Name in the app | Search | Quo: menus, Settings, alerts, permission prompts, the AppleScript dictionary, its own pages' addresses (`quo://settings`; an old `search://` one still opens) |
| Bundle ID | `com.officecommun.search` | `com.edinabazi.quo` |
| Tabs, history, pins, extensions | `~/Library/Application Support/Search` | `~/Library/Application Support/Quo` |
| Settings | `com.officecommun.search` | `com.edinabazi.quo` |
| Cookies and site data | WebKit's container for Search | WebKit's container for Quo |
| Keychain items | Search's | Quo's own |
| Updates | Office Commun's feed, signed | None: rebuild it yourself |

They share nothing, the keychain included: Quo keeps its passwords, AI keys and proxy password under its own name, apart from Search's.

Passkeys through the browser's own sheet need an entitlement Apple grants only to Search's signed releases, so they don't work in Quo. Passkeys in a password-manager extension still do.

---

## Building it

macOS 14 or later, with Xcode 16 or a Swift 6 toolchain. No dependencies beyond what ships with macOS.

```bash
./quo.sh            # build/Quo.app
./quo.sh install    # the same, then into /Applications (quits Quo first)
```

Everything the app says about itself reads `Store.name`, so it says Quo here and Search in a plain build. Code, comments and file names still say Search, so upstream merges stay clean; what Quo shows or leaves behind while it runs (keychain items, error messages, log subsystems, temporary folders) is named for Quo. The sync folder is "Quo Sync"; one made as "Search Sync" is moved to the new name the first time Quo syncs. "A fork of Search by Office Commun" in About, Search's own release notes and the copyright line keep the credit.

`quo.sh` is `build.sh` with a name, a bundle ID and an icon mark of its own (`SEARCH_NAME=Quo SEARCH_BUNDLE_ID=com.edinabazi.quo SEARCH_MARK=Icon/quo-mark.svg`). The app's data folder, settings and WebKit container all follow the bundle ID; the code still says "Search" by default, so upstream changes merge cleanly.

It signs with the first Developer ID certificate in your keychain, or ad hoc if there is none (then the first launch needs right-click › Open).

For quick checks while working, `swift build` compiles, `swift test --parallel` runs the unit tests in about a minute (one after another, `swift test` takes over twelve), and `SEARCH_DEV=1 ./build.sh` makes a yellow-icon dev build of Search. To try a dev build without touching anyone's data, open it in a test profile of its own:

```bash
open -n --env SEARCH_PROBE=mytest build/Search.app
```

Test profiles turn a few things off on purpose (links from other apps, mailto:, file pickers), so they're for checking, not for daily use.

### Sync through iCloud

Settings › General › Sync can go through iCloud: each Mac's spaces, pins, bookmarks and settings are a record in the person's own private iCloud, in CloudKit's encrypted fields, with no account or server of ours (`SyncCloud.swift`). It needs a build signed for an iCloud container, set up once in the Apple Developer account:

1. **Identifiers › iCloud Containers**: `iCloud.com.edinabazi.quo`.
2. **Identifiers › App IDs**: `com.edinabazi.quo`, with iCloud (CloudKit, that container) and Push Notifications.
3. **Profiles › Developer ID**: for that App ID, saved here as `Quo.provisionprofile` (git-ignored). `quo.sh` then embeds it with `Quo.entitlements`.
4. The first time only: `SEARCH_ICLOUD_ENV=Development ./quo.sh install`, turn sync to iCloud so the record type is made, then **Deploy Schema Changes** to Production in the CloudKit Console, and build normally.

Without the profile, Quo builds as before and offers only the folder. `Tests/sync_icloud.py` plays two Macs against a folder standing in for iCloud.

### Moving your Search data into Quo

Quo starts empty. To bring over everything from an installed Search (settings, tabs, pins, history, bookmarks, extensions, cookies), quit Quo and copy it across once:

```bash
L=~/Library; S=com.officecommun.search; Q=com.edinabazi.quo
cp -Rp "$L/Application Support/Search" "$L/Application Support/Quo"
defaults export $S - | defaults import $Q -
mkdir -p "$L/WebKit/$Q"
cp -Rp "$L/WebKit/$S/WebsiteData" "$L/WebKit/$S/WebExtensions" "$L/WebKit/$Q/"
cp -Rp "$L/HTTPStorages/$S" "$L/HTTPStorages/$Q"
cp -p "$L/HTTPStorages/$S.binarycookies" "$L/HTTPStorages/$Q.binarycookies"
```

Some sites, Google among them, may ask you to sign in again in Quo.

---

## Keeping up with Search

`origin` is this repository; `upstream` is Search.

```bash
git fetch upstream
git merge upstream/main
./quo.sh install
```

How Search is put together (one file per concern in `Sources/Search/`, the `./bench` test socket, the extension shims) is in [Search's README](https://github.com/driceroland/Search#for-developers), and still applies here.

## License

MIT, as Search is: see [LICENSE](LICENSE). The code is Office Commun's and its contributors', with Quo's changes on top. "Search" and its icon belong to Office Commun. Quo has its own icon, a dark Q on a white tile, made in Icon Composer (`Icon/Quo.icon`; the build turns it into the Dock's styles and the flat `.icns` with Icon Composer's `ictool`, and falls back to the older drawn mark, `Icon/quo-mark.svg`, on a Mac without it). Settings › About and the welcome screen show it too. `Sources/Search/FilterList.swift` is a port of [adblock-rust](https://github.com/brave/adblock-rust) and stays under its licence, the Mozilla Public License 2.0.
