# Pressto

_A keyboard palette for every Mac app: press ⇧⌘H, type a few letters, press ↵._

<img align="right" width="128" alt="App icon" src="./Scoot/Assets.xcassets/AppIcon.appiconset/512.png" />

Pressto lets you reach anything on your Mac's screen from the keyboard: search for it by name, jump to it by a two-letter label, or steer the pointer there. It is built on [Scoot](https://github.com/mjrusso/scoot), Michael Russo's keyboard cursor tool, and keeps everything Scoot does. More at [pressto.app](https://pressto.app).

> The app is `Pressto.app` (`co.nillebco.pressto`); the source folders and Xcode target keep Scoot's names so fixes still apply upstream.

## Why this exists

Keyboard tools for the Mac mostly answer *“where is it?”*: they put labels on what's on screen, or a grid over it, and you type the label you read. That works, but you have to look first, and it can't reach what isn't drawn: a menu item, a tab scrolled out of the sidebar, a button behind a sheet.

Most of the time you already know *what* you want — “Complete merge”, “Export…”, the tab with `sfp-rag-dev` in its address. Pressto lets you type that. A fuzzy matcher ranks every control of the focused window, every menu item and every browser tab as you type, and ↵ presses the one you meant. On the web, [Pagecast](https://labs.nilleb.co/pagecast.html) does this for a page; Pressto does it for every app, through the macOS accessibility tree. Closed-source tools such as Shortcat offer a search like this; no open-source one did.

Search doesn't replace pointing: some things have no name (a spot in a canvas, a map, a drag target). So Pressto keeps Scoot's labels, grid and free cursor movement, and the four modes cover each other.

## Four ways to reach something

| Shortcut | Mode | Use it when |
| --- | --- | --- |
| ⇧⌘H | **Palette** | you know its name: a button, a menu item, a tab, a page action |
| ⇧⌘J | **Element labels** | you can see it and it's a control: type the label that appears on it |
| ⇧⌘K | **Grid** | it's anywhere on any screen, named or not: type the cell, then nudge |
| ⇧⌘L | **Freestyle** | you just want to nudge the pointer, click, drag or scroll |

All shortcuts can be changed in Preferences. In every mode except the palette, the arrow keys (or Emacs / vi bindings) move the pointer, ↵ clicks, `=` starts a drag and ⇧↑/⇧↓ scroll; see [Usage](#usage).

### The palette

Press ⇧⌘H in any app. A search field opens over the focused window, listing:

| Group | What it holds |
| --- | --- |
| Quick actions | copy the page address, as a Markdown link, or the page title (browsers) |
| Window | the focused window's buttons, links, fields and tabs |
| Tabs | browser tabs, matched by address as well as title (Safari, Chrome, Brave, Edge, Vivaldi, Zen, Firefox) |
| Menu | every item of the app's menu bar |

Type to rank all groups together, or narrow to one with a prefix: `>` actions, `#` window, `@` tabs, `/` menu (or `tab:`, `menu:`, …). ↑/↓ to move, ↵ to press. Rows are pressed through the accessibility API (`AXPress`), so they work on sheets and on controls that are covered or scrolled away.

The matcher (`Scoot/Fuzzy.swift`) requires every query token to appear in order and scores the best placement, with bonuses for the start of the string, word boundaries and consecutive runs. `cplmrg` finds “Complete merge” and not “Complete”; `sfprag` finds the tab whose URL holds `sfp-rag-dev` rather than a title that happens to contain those letters scattered.

### Permissions

Pressto asks for two kinds of access, both in **System Settings → Privacy & Security**:

| Permission | Asked | Why |
| --- | --- | --- |
| **Accessibility** | once, at first launch | to see the controls of other apps and to press them, click and move the pointer. Nothing works without it. |
| **Automation** | once per browser, the first time you open the palette over it (Safari, Chrome, Brave, Edge, Vivaldi) | to read the address of each open tab, so a tab can be found by its address and not only by its title |

Automation is optional. If you click *Don't Allow*, tabs are still listed by title; you can change your mind later under Privacy & Security → Automation → Pressto. Zen and Firefox need no Automation access: their tab addresses come from the session file they keep in your profile folder.

Pressto reads tab addresses only for the window you're looking at, only when you open the palette, and never sends them anywhere: everything stays on your Mac.

### Element labels and the grid

These come from Scoot. **Element labels** use the macOS accessibility APIs to find the buttons and links of the focused window and give each a short key sequence. Here the only link on the page _(“More information...”)_ gets “aa”:

<p align="center">
  <img src="./Assets/Examples/element-nav.png" alt="Element labels" />
</p>

The **grid** divides every connected screen into equal cells, each with its own sequence; ⇧⌘= and ⇧⌘- change the cell size (30–200 pt):

<p align="center">
  <img src="./Assets/Examples/grid-nav.png" alt="The grid" />
</p>

Type a sequence and the pointer jumps there; then click, drag or nudge it from the keyboard. **Freestyle** is the same without anything drawn on screen. Pressto also improves these modes. Element labels now reach web page content in Firefox-based browsers, and stacked buttons each keep their own label. Clicks on dialog buttons now register. The grid can't crash at any size (see [Changes from Scoot](#changes-from-scoot)).

## About

* Pressto is _not_ intended to replace the mouse or trackpad entirely. It's here to augment them.

* Pressto runs on macOS 12 (Monterey) and later.

* Pressto is an AppKit app, written in Swift. (There's still some Carbon in here, too! [Yes][carbon-events], [really][carbon-accessibility].)
* Pressto requires MacOS 12 (Monterey) or later.

* Pressto complements mouse-related accessibility tools that ship as part of MacOS, such as [Mouse Keys][mouse-keys] and other [accessibility shortcuts][mac-accessibility-shortcuts], in addition to mouse emulation provided via keyboard firmware ([QMK][qmk-mouse-keys], for example).

## Usage

To activate Pressto in the **element-based navigation mode**, use the ⇧⌘J global keyboard shortcut. Alternatively, to activate Pressto in the **grid-based navigation mode**, use the ⇧⌘K global keyboard shortcut. And for **freestyle mode**, use the ⇧⌘L global keyboard shortcut. The **palette** opens with ⇧⌘H (see [The palette](#the-palette)). (These shortcuts can be customized.)

As long as Pressto is running, any of these hotkeys will bring the app to the foreground, and activate the requested mode.

When Pressto is in the foreground:

* You can jump directly to a cell (a UI element, or a location in the grid, depending on the active navigation mode). Each cell is marked with a label (e.g. “aaa”, “aas”, “aad”); type the characters, one letter at a time, and, as soon as a complete sequence is entered, the mouse cursor will move directly to the center of the corresponding cell. (This approach, including the use of a char-based decision tree, is heavily inspired by [avy][avy].)
  * If you make a mistake while entering a label, hit the escape key (⎋) to cancel and start over. (Alternatively, you can type ⌘. or C-G.)
  * This feature is not available in freestyle mode, which does not present any special UI, or otherwise offer any navigation assistance via a char-based decision tree.

* You can _also_ move the cursor via the standard Mac keyboard shortcuts for [moving the insertion point][mac-keyboard-shortcuts-text]. (This means that keyboard shortcuts intended for navigating around in a document have been re-purposed to control movement on a 2-dimensional grid. Some liberties have been taken with this mapping; hopefully you find these keybindings intuitive.) This feature works in _all_ modes (element-based, grid-based, and freestyle).
    * The equivalent standard Emacs keybindings should also work out-of-the-box, if you have them configured system-wide (for example, via [Karabiner-Elements][karabiner-elements] [[complex modification][karabiner-elements-emacs-mod]], or by augmenting the [system defaults][emacs-keyboard-shortcuts-osx] [[DefaultKeyBinding.dict][defaultkeybinding.dict], [Cocoa Text System][cocoa-text-system], [Text System Defaults and Key Bindings][apple-dev-text-system]]).
    * The equivalent vi bindings are also (optionally) available; see [keybindings](#keybindings) for details.

* You can click with the left mouse button (at the current cursor location) by hitting the Return (↵) key.

* You can hold the left mouse button down by pressing `=`. (To release the button, press ↵.)
  * To perform a drag-and-drop operation: situate the cursor above the object you want to drag and press `=`, then move the mouse cursor to the desired drag destination (using one or more of the mechanisms that Pressto makes available), and then press ↵ to perform the drop.

* You can double-click with the left mouse button (at the current cursor location) by hitting the Shift and Return keys together (⇧↵).

* You can scroll, by pressing the Shift key in conjunction with the arrow key (↑, ↓, ←, →) pointing in the desired scroll direction. Add Command (⇧⌘↑) to scroll all the way, e.g. back to the top: unlike a browser's ⌘↑, this reaches inner scroll containers too.

After clicking, any overlaid UI elements (such as the element view, or the grid) will automatically hide. You can also hide these UI elements (and send Pressto to the background) at any time by pressing ⌘H.

Pressto includes a menu bar icon (an illustration of a Vespa-inspired scooter).

<img align="right" width="256" alt="Pressto Menu Bar Icon" src="./Assets/menu-bar-icon.png" />

* When Pressto is not active (i.e., running in the background), the icon will render in an outlined mode.
* When Pressto is in the foreground, the icon will render with a fill (see screenshot), to make it clearer that Pressto is currently active. (This shouldn't generally be a concern, but it is especially handy when you're in freestyle mode.)
* Additional options are exposed when clicking on the menu bar icon, including a _help_ menu item — which currently opens this README in the user's default browser.

Pressto is fully compatible with Spaces (and can be used in conjunction with apps that are running in native fullscreen mode).

Pressto also works on systems with multiple connected displays.

<p align="center">
  <img src="./Assets/Examples/grid-multiple-displays.jpg" alt="Using Pressto with multiple connected displays" />
</p>

_If you use multiple displays, and experience an issue with Pressto's windows drawing in an incorrect location when the app launches (e.g. all Pressto windows appearing on the same display), please post your findings [in this issue](https://github.com/mjrusso/scoot/issues/18), and note the value of your “Displays have separate Spaces” checkbox in Mission Control._ If you do happen to find yourself in this state, you should be able to fix the window arrangement by clicking Pressto's menu bar icon, then “Debug”, and finally “Rebuild Jump Windows”.

To customize Pressto's settings, click Pressto's menu bar icon, then “Settings…”, or type `⌘,` while Pressto is in the foreground. In addition to modifying keybindings, it is also possible to modify Pressto's appearance (including font sizes, colours, opacity, etc.).

### Keybindings

_Not sure what these symbols mean? See the [symbol reference][what-are-those-mac-symbols], and [Emacs key notation][emacs-key-notation]._

#### Global Keybindings

Global keybindings are always active, as long as Pressto is currently running.


| Default Shortcut | Description                                              |
|------------------|----------------------------------------------------------|
| ⇧⌘J              | Use element-based navigation (bring Pressto to foreground) |
| ⇧⌘K              | Use grid-based navigation (bring Pressto to foreground)    |
| ⇧⌘L              | Use freestyle mode (bring Pressto to foreground)           |
| ⇧⌘H              | Open the command palette over the focused window           |

All global keybindings are fully customizable. To modify the keybindings, click Pressto's menu bar icon, then “Settings…”, and select the “Keybindings” tab.

#### Local Keybindings

Local keybindings are only active when Pressto is active (i.e., when Pressto is in the foreground).

Note that vi keybindings are not enabled by default, and must be explicitly toggled on (click Pressto's menu bar icon, then “Settings…”, select the “Keybindings” tab, and then change the keybinding mode). Emacs keybindings (and most system keybindings) are disabled when vi keybindings are active.

##### General

| Shortcut  | Alternate | Description                                                                                                       |
|-----------|-----------|-------------------------------------------------------------------------------------------------------------------|
| ⌘H        |           | Hide UI (bring Pressto to background)                                                                               |
| ⎋ (or ⌘. or ⌘Q) | C-g | Cancel: if currently typing a label, clears all currently-typed characters; otherwise, brings Pressto to background |


_Note:_ ⎋ signifies the Escape key.

##### Cursor Movement

| System | Emacs | vi  | Description                                                 |
|--------|-------|-----|-------------------------------------------------------------|
| ↑      | C-p   | k   | Move cursor up (partial step)                               |
| ↓      | C-n   | j   | Move cursor down (partial step)                             |
| ←      | C-b   | h   | Move cursor left (partial step)                             |
| →      | C-f   | l   | Move cursor right (partial step)                            |
| ⌥↑     | M-a   | C-k | Move cursor up (full step)                                  |
| ⌥↓     | M-e   | C-j | Move cursor down (full step)                                |
| ⌥←     | M-b   | C-h | Move cursor left (full step)                                |
| ⌥→     | M-f   | C-l | Move cursor right (full step)                               |
| ⌘↑     | M-<   | ⇧-k | Move cursor to top edge of screen                           |
| ⌘↓     | M->   | ⇧-j | Move cursor to bottom edge of screen                        |
| ⌘←     | C-a   | ⇧-h | Move cursor to left edge of screen                          |
| ⌘→     | C-e   | ⇧-l | Move cursor to right edge of screen                         |
| ⌃L     | C-l   | ⇧-m | Move cursor to center, and (on repeat) cycle around corners |

##### Clicking

| Shortcut | Description                                                            |
|----------|------------------------------------------------------------------------|
| ↵        | Click left mouse button (at current cursor location)                   |
| =        | Press and hold left mouse button (once activated, type `↵` to release) |
| \        | Double-click left mouse button (at current cursor location)            |
| [        | Click middle mouse button (at current cursor location)                 |
| ]        | Click right mouse button (at current cursor location)                  |

Pressto will pass along any pressed modifier keys when simulating clicks. This means that Command-click, Option-click, Control-click, and Shift-click are all supported (or any combination thereof). For example, ⌘↵ will Command-click the left mouse button at the current cursor location, ⌥↵ will Option-click, ⌃↵ will Control-click, ⇧↵ will Shift-click, etc.

Pressto can't take control of the mouse cursor when a context menu is active (for example, after right clicking). However, system-provided keyboard shortcuts for selecting the item in a menu (such as ↑, ↓, ←, →, C-n, C-p, ↵) will work as expected.

For simplicity, Pressto only supports simulating holding/ dragging, and double clicking, with the left mouse button. (If you have a use case that requires more exotic click handling, please [file an issue][scoot-issues] with details.)

_Note:_ ↵ signifies the Return (a.k.a Enter) key. _(Sidenote: technically, Return and Enter are [two different keys][return-and-enter-are-two-different-keys].)_

##### Scrolling

| System | Emacs | vi  | Description                               |
|--------|-------|-----|-------------------------------------------|
| ⇧↑     | ⇧-p   | C-b | Scroll up (at current cursor location)    |
| ⇧↓     | ⇧-n   | C-f | Scroll down (at current cursor location)  |
| ⇧←     | ⇧-b   | C-i | Scroll left (at current cursor location)  |
| ⇧→     | ⇧-f   | C-a | Scroll right (at current cursor location) |
| ⇧⌘↑    | ⇧⌘↑   | ⇧⌘↑ | Scroll to the top (of whatever is under the cursor) |
| ⇧⌘↓    | ⇧⌘↓   | ⇧⌘↓ | Scroll to the bottom                      |
| ⇧⌘← / ⇧⌘→ | ⇧⌘← / ⇧⌘→ | ⇧⌘← / ⇧⌘→ | Scroll to the start / end of a carousel |

##### Presentation

| Shortcut | Description                                |
|----------|--------------------------------------------|
| ⌃=       | Toggle visibility of grid lines            |
| ⌃⇧=      | Toggle visibility of grid labels           |
| ⇧⌘=      | Increase size of grid cells (30–200 pt)    |
| ⇧⌘-      | Decrease size of grid cells                |
| ⌘=       | Increase contrast of user interface |
| ⌘-       | Decrease contrast of user interface |

## Installation

There is no release yet. Build it from source (see [Development](#development)), then move the built app into _Applications_.

### Setup

On first run, MacOS asks for permission to let Scoot control your computer. The screenshots in this section show the older System Preferences interface; newer versions use different setting names.

<p align="center">
  <img width="450" src="./Assets/Documentation/accessibility-prompt.png" alt="Scoot.app would like to control this computer using accessibility features" />
</p>

**Pressto will not work unless access is granted.** (Note that Pressto does not collect any user or usage-related information, and does not make any network requests. The app runs entirely locally, and treats its privileged access with the utmost respect.)

Open the permission pane for your MacOS version:

| MacOS version | Permission pane                                                           |
|---------------|---------------------------------------------------------------------------|
| MacOS 27      | System Settings → Privacy & Security → **Device Control and Data Access** |
| MacOS 13–26   | System Settings → Privacy & Security → **Accessibility**                  |
| MacOS 12      | System Preferences → Security & Privacy → Privacy → **Accessibility**     |

Enable **Scoot** in the list. If it is missing, click **+** and select **Scoot.app** from your Applications folder. Restart Scoot after granting access.

On MacOS 12, click the lock in the bottom left corner (_“Click the lock to make changes”_) before changing permissions:

<p align="center">
  <img width="550" src="./Assets/Documentation/privacy-locked.png" alt="Locked accessibility settings" />
</p>

Check _“Pressto.app”_ to give Pressto the ability to move your cursor, and to click, drag, and scroll:

<p align="center">
  <img width="550" src="./Assets/Documentation/accessibility-access-granted.png" alt="Scoot.app granted accessibility access" />
</p>

See the [usage documentation](#usage) for details on how to use Pressto.

To launch Pressto automatically when you log in, add **Pressto.app** to your [login items](https://support.apple.com/guide/mac-help/open-items-automatically-when-you-log-in-mh15189/mac). On MacOS 13 or later, open **System Settings → General → Login Items** (called **Login Items & Extensions** on newer versions).

On MacOS 12, open **System Preferences → Users & Groups → Login Items**:

<p align="center">
  <img width="550" src="./Assets/Documentation/login-items-locked.png" alt="Locked login items settings" />
</p>

On MacOS 12, click the lock in the bottom left corner to unlock this preference pane. Once unlocked, click the “+” button, and select _“Pressto.app”_ from the _Applications_ folder. Checking the _“Hide”_ checkbox is recommended.

<p align="center">
  <img width="550" src="./Assets/Documentation/start-automatically.png" alt="Pressto configured to start automatically" />
</p>

If you encounter any problems, feel free to [file an issue][scoot-issues].

## Demos

### Element-based Navigation

This is what it's like to navigate around Wikipedia in Safari, using the element-based navigation mode:

https://user-images.githubusercontent.com/100451/151269537-627cdccd-b1a1-45e1-82aa-11992ca0dc9a.mp4

### Drag and Drop

Here's what it's like to drag and drop with Pressto, using the grid-based navigation mode:

https://user-images.githubusercontent.com/100451/118299332-9e6a2e00-b4ae-11eb-901d-79a212ce1d37.mp4

For reference, the following key sequence was used to grab the file and drop it in a new location:

- `⇧⌘K` to activate Pressto
- `kh` to jump cursor to cell
- `=` to press and hold the left mouse button
- `fd` to jump cursor to cell
- `↵` to release the left mouse button

## Feature Backlog

See the [issue tracker][scoot-issues]. Fixes that apply to Scoot too are sent upstream ([mjrusso/scoot#61–#69](https://github.com/mjrusso/scoot/pulls?q=is%3Apr+author%3Anilleb)).

## Development

```sh
scripts/make-signing-cert   # once per machine, if you have no Apple Development identity
scripts/dev                 # build, sign, relaunch
scripts/dev --install       # build, sign, copy to /Applications, launch that copy
scripts/dev --dump          # build, relaunch with SCOOT_DUMP_ELEMENTS=1
scripts/test                # unit tests
```

The build needs Xcode, not only the command-line tools: if `xcodebuild` complains, run `sudo xcode-select -s /Applications/Xcode.app` (or set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

#### Signing and the Accessibility grant

macOS ties the Accessibility grant to the app's code signature. Xcode signs the build ad hoc, and an ad-hoc signature changes on every build, so each rebuild would ask for access again. `scripts/dev` therefore re-signs the app, with the first of:

1. `SCOOT_SIGN_IDENTITY`, when set;
2. a valid *Apple Development* identity from your keychain;
3. a certificate named *Pressto Local Signing*, which `scripts/make-signing-cert` creates.

The local certificate is self-signed, generated on your machine and kept in your login keychain; it is not shared and not committed. It need not be trusted, so the script changes no trust settings and asks for no password. Grant Accessibility once after the first build signed with it; later builds keep the grant. Remove it with `security delete-identity -c "Pressto Local Signing"`.

#### Element dumps

To see what the accessibility tree exposes, open the palette over the window and choose *Dump accessibility elements* (type `dump`). It writes every element (role, title, value, frame, link address, DOM classes, actions) to `~/Library/Application Support/Pressto/element-dumps/` and the pasteboard, and chimes when done. The menu bar's Debug → *Dump Accessibility Elements* does the same for the app Pressto was last invoked on.

The unit-test bundle is **host-less**: the sources under test are compiled into the test bundle instead of being injected into the app. A hosted test whose host is a menu-bar agent (`LSUIElement`) makes Xcode 27's LaunchServices launcher abort with `Assertion failed: childPID > 0` before a single test runs; the same happens when a copy of the app is already running, which is why `scripts/test` stops any running instance first.

### Changes from Scoot

Besides the palette:

- the grid builds its cells by index, so no screen or cell size can crash it, and its cell size ranges over 30–200 pt;
- element mode reaches web page content in Firefox-based browsers (frameless `AXWebArea` nodes are descended into; the tree is woken at invoke and rescanned while it fills in);
- stacked buttons a few points apart keep their own labels;
- clicks wait for the target app to activate, so buttons in alerts and sheets are pressed;
- the labels are dismissed when the app is hidden, and ⌘Q dismisses the overlay instead of quitting;
- only the `AXEnhancedUserInterface` flags the app itself switched on are reverted;
- deployment target macOS 12, so it builds on Xcode 27.

## License

Pressto is released under the terms of the [BSD 3-Clause License](LICENSE). It is a fork of [Scoot](https://github.com/mjrusso/scoot) by Michael Russo; the original copyright notice is kept in the licence and in the app's About and Credits screens. The name was changed so the fork is never mistaken for Scoot, or for something its author endorses.

Copyright (c) 2021-2026, [Michael Russo](https://mjrusso.com).
Modifications copyright (c) 2026, nillebco.


[latest-scoot-binary]: https://github.com/mjrusso/scoot/releases/latest/download/Scoot.app.zip
[latest-scoot-release]: https://github.com/mjrusso/scoot/releases/latest
[scoot-issues]: https://github.com/nillebco/pressto/issues

[carbon-events]: https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/Carbon_Event_Manager/Intro/CarbonEventsIntro.html
[carbon-accessibility]: https://developer.apple.com/documentation/applicationservices/carbon_accessibility
[avy]: https://github.com/abo-abo/avy
[qmk-mouse-keys]: https://docs.qmk.fm/#/feature_mouse_keys?id=mouse-keys
[mouse-keys]: https://support.apple.com/en-ca/guide/mac-help/mh27469/mac
[mac-accessibility-shortcuts]: https://support.apple.com/en-ca/HT204434
[mac-keyboard-shortcuts]: https://support.apple.com/en-ca/HT201236
[mac-keyboard-shortcuts-text]: https://support.apple.com/en-ca/HT201236#text
[what-are-those-mac-symbols]: https://support.apple.com/en-ca/guide/mac-help/cpmh0011/mac
[emacs-key-notation]: https://www.emacswiki.org/emacs/EmacsKeyNotation
[karabiner-elements]: https://karabiner-elements.pqrs.org
[karabiner-elements-emacs-mod]: https://ke-complex-modifications.pqrs.org/#emacs_key_bindings
[emacs-keyboard-shortcuts-osx]: https://jblevins.org/log/kbd
[defaultkeybinding.dict]: https://github.com/nileshk/mac-configuration/blob/99eef47cd434fd3d6f4f1f9e2f50321f32179b88/Library/KeyBindings/DefaultKeyBinding.dict
[cocoa-text-system]: https://www.hcs.harvard.edu/~jrus/site/cocoa-text.html
[apple-dev-text-system]: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/TextDefaultsBindings/TextDefaultsBindings.html
[return-and-enter-are-two-different-keys]: https://daringfireball.net/2020/07/return_and_enter
