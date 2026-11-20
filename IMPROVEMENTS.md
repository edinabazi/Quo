# What Quo does better than Search

Everything Quo has added to or fixed in [Search](https://github.com/driceroland/Search) since forking it, kept up to date as Quo changes. Newest first within each section. Naming and branding (Quo's name, icon, `quo://`, its own data) aren't listed; see the README for those.

## Looks and feel

- **A space's colour on a wheel, as in Arc**: the space's menu › Colour… is a colour wheel where you drag one, two or three handles to pick a colour or a gradient, with + and − for a handle more or less and an arrow to turn it. Handles snap to the ready-made hues and spring as they go, and the window shows the look live as you drag. A grain slider lays film grain over any space's colour, and the window's Light, Dark or Auto is a click away there too. Search had rows of swatches, a folded custom section and a grain switch for gradients only. *Nov 2026*
- **The small window for links, as Arc's Little Arc**: larger, it springs open, fades away, and kept, flies into its place in the browser's window; the page is a card on a frame in the space's colour; its bar has the site's icon, the site and the rest of the address dimmed, Back once you follow a link, Copy Link, a light while it loads, and Open in the space you're on, with the others on an arrow beside it. Search's had the site's name and Open in Search. *Nov 2026*
- **An agent's tab group looks like one**: the group Claude or another agent makes to work in shows the agent's icon before its name, a soft wash of colour and a thread down the side of its tabs, and, while the agent is working there, moving dots and a light passing over the heading. Your own groups look as before. *Nov 2026*
- **Group headings fit Roomy**: taller, with larger names, so they sit in proportion with Roomy's taller tabs instead of looking squeezed between them, and a folded group shows its fold mark. *Nov 2026*
- **An onboarding to match Arc's and Dia's**: six full-window steps on a slowly moving gradient, with frosted cards that rise in. Pick the look, where the tabs go, Roomy or Compact and a colour, with a live preview; bring Arc's spaces or another browser's things over; set up sync, the blocker and its lists, and the default browser; and finish on the six keys worth knowing. Search had four plain pages. *Nov 2026*
- **Roomy or Compact** (Settings › Appearance › Size), Roomy by default. Taller tabs and rows and larger text in the column, a larger address bar and ⌘T field, and more room in Settings, every built-in page (History, Downloads, Bookmarks, Passwords, Archived Tabs), the small window for links and website pop-ups. Pin squares are taller, as Arc's are. *Nov 2026*
- **The window's buttons stay on the left with the column on the right**, in a row across the top: the address bar, or with it off, a slim row with back, forward and reload. Search moved them into the column's far corner. *Nov 2026*
- **The address field takes a space's colour** instead of sitting on it as a grey slab. *Nov 2026*
- **Smooth scrolling with a mouse wheel**, as in Chrome: each notch eased out instead of jumping (Settings › Keyboard & Mouse). *Nov 2026*
- **A tab's whole title on hover** when the row cuts it short, in Quo's own tooltip: quicker, larger, and in the app's own style. *Nov 2026*
- **An address bar above the page**, on by default: the whole address, back, forward and reload, and the extensions' buttons at its far end. *Nov 2026*

## Habits from Arc and Chrome

- **Downloads as cards in the column**, as in Arc: progress and time left while they come in, then the file itself, to open, show in Finder or drag out to another app. Search had a small ring in the column's foot. *Nov 2026*
- **Arc's habits on from the start**: spaces, ⌘T's floating field with recent places and commands, pinned rows and folders in them. Search has them all but starts with them off. *Nov 2026*
- **A pin keeps its site, and what leaves it opens in a new tab**: a link in a pin to another site, or another site's address typed into it, opens a new tab beside it, as Dia does, and the pin stays where it was. Search opened such links in a Peek over the pin, which is still a choice (Settings › Spaces & Pins). *Nov 2026*
- **Chrome's reload keys**: ⇧⌘R reloads skipping the cache, and Reading Mode moves to ⌥⌘R. *Nov 2026*

## Blocking

- **Popular filter lists a click away** (EasyList, EasyPrivacy, Fanboy's Annoyances, the cookie notice list). *Nov 2026*
- **Filter lists for the built-in blocker**: the lists every other blocker uses, by address or file, compiled into WebKit's own rules. Search closed this ([driceroland/Search#738](https://github.com/driceroland/Search/pull/738)). *Oct 2026*

## Extensions

- **Agent extensions can work the page, not just read it**: Claude, ChatGPT's agent and any other extension that asks for Chrome's `debugger` can click, drag, type, press keys (Return submits, Tab moves on, ⌘A selects all), scroll, take screenshots and run scripts in a tab, as they do in Chrome. The clicks and keys are real events handed to the page, never to Quo's own menus, and your pointer doesn't move. Search refused the debugger outright, so these extensions could read a page but every action failed or silently did nothing. *Nov 2026*
- **Extensions hear about their errors**: a failed call now sets `chrome.runtime.lastError` for its callback, as in Chrome. Before, every failure looked like success to an extension written with callbacks. *Nov 2026*
- **Lighter on every page**: the part of Quo's extension helper that content scripts carry is about 120 KB, not 275 KB, in every frame. 1Password's buttons and menus feel smoother. *Nov 2026*
- **Popups open at their settled size** instead of opening small and jumping (Ahrefs, Cookie-Editor), or growing and morphing as they open. *Nov 2026*
- **Notifications work as in Chrome**: an extension's buttons under the notification's Options, and clicks, buttons and dismissals going back to the extension. *Nov 2026*
- **⌘-drag the pinned extension buttons to reorder them**, as the Mac's menu bar does. *Nov 2026*

## Video

- **A floating live stream fills its window**: YouTube's live player sat a quarter size in the window's corner. *Nov 2026*

## Fixes

- **Extension badges sit in the middle**: a count was a little low and off to one side, and three or four characters made a wide slab across the icon. Now a circle for one character, a short capsule for more, in a condensed cut for three or four, cut at four as Chrome does. *Nov 2026*
- **A page from the small window for links keeps its address**: Open in Quo moved it into the row with an empty address bar until it was reloaded, and the small window's own bar never named the site. *Nov 2026*
