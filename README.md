# Quo

A personal fork of [Search](https://github.com/driceroland/Search), the small, fast WebKit browser for the Mac by [Office Commun](https://officecommun.com).

Quo keeps everything Search is (tabs down the side or across the top, an ad blocker that runs before the page, passwords in your keychain, Chrome extensions on WebKit, about 10 MB on disk) and goes its own way on a few things Search decided against.

Short, and quick to type: Q-U-O rolls across the top row of the keyboard.

---

## What's different from Search

### An address bar above the page

Off by default. Turn it on in **Settings › Tabs › Address bar above the page**. It only applies with the tabs down the side.

- **The whole address, always.** The site in ink, the path and query dimmed after it, as Chrome and Dia show it. "Not secure" and look-alike domains still show, exactly as in the tab.
- **Back, forward and reload** move from the top of the column into the bar.
- **Extensions move to the bar's far end**, out of the column's foot.
- **The column shows page titles only.** The bar has the address, so the tab no longer swaps its title for it.
- **Click the address, or press ⌘L,** to edit it right there, with the same suggestions and site card as editing in the tab. Right-click for Copy Address.
- It folds away with the column (⌘S) and when a video takes the screen, as the bookmarks bar does.

### Roomier tabs, everywhere

With **Settings › Tabs › Roomier tabs** on, the rest of the chrome follows the taller rows: the address bar's field is as tall as a tab, its buttons are larger, and the ⌘T / ⌘L field and its suggestions are a size up.

### Its own app

Quo runs beside an installed Search without sharing anything with it:

| | Search | Quo |
|---|---|---|
| Bundle ID | `com.officecommun.search` | `com.edinabazi.quo` |
| Tabs, history, pins, extensions | `~/Library/Application Support/Search` | `~/Library/Application Support/Quo` |
| Settings | `com.officecommun.search` | `com.edinabazi.quo` |
| Cookies and site data | WebKit's container for Search | WebKit's container for Quo |
| Updates | Office Commun's feed, signed | None: rebuild it yourself |

Saved passwords are the one thing the two share, through the keychain. The first time Quo reads one that Search saved, macOS asks for your login password, since the two apps are signed by different developers; choose Always Allow.

Passkeys through the browser's own sheet need an entitlement Apple grants only to Search's signed releases, so they don't work in Quo. Passkeys in a password-manager extension still do.

---

## Building it

macOS 14 or later, with Xcode 16 or a Swift 6 toolchain. No dependencies beyond what ships with macOS.

```bash
./quo.sh            # build/Quo.app
./quo.sh install    # the same, then into /Applications (quits Quo first)
```

`quo.sh` is `build.sh` with a name and bundle ID of its own (`SEARCH_NAME=Quo SEARCH_BUNDLE_ID=com.edinabazi.quo`). The app's data folder, settings and WebKit container all follow the bundle ID; the code still says "Search" by default, so upstream changes merge cleanly.

It signs with the first Developer ID certificate in your keychain, or ad hoc if there is none (then the first launch needs right-click › Open).

For quick checks while working, `swift build` compiles, `swift test` runs the unit tests, and `SEARCH_DEV=1 ./build.sh` makes a yellow-icon dev build of Search. To try a dev build without touching anyone's data, open it in a test profile of its own:

```bash
open -n --env SEARCH_PROBE=mytest build/Search.app
```

Test profiles turn a few things off on purpose (links from other apps, mailto:, file pickers), so they're for checking, not for daily use.

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

MIT, as Search is: see [LICENSE](LICENSE). The code is Office Commun's and its contributors', with Quo's changes on top. "Search" and its icon belong to Office Commun; Quo still uses that icon for now, so it isn't one to hand out as is.
