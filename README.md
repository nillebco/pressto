# Pressto

_A keyboard palette for every Mac app: press ⇧⌘H, type a few letters, press ↵._

Pressto makes the controls of any app searchable, the way [Pagecast](https://labs.nilleb.co/pagecast.html) does for web pages. It is a fork of [Scoot](https://github.com/mjrusso/scoot), Michael Russo's keyboard cursor tool, and keeps everything Scoot does: hint labels, the grid, freestyle mode. More at [labs.nilleb.co/pressto](https://labs.nilleb.co/pressto.html).

> The rename is in progress: the source, the app bundle (`Scoot.app`, `co.nillebco.scoot`) and the menu bar still say Scoot.

## The palette

Press ⇧⌘H in any app. A search field opens over the focused window, listing:

| Group | What it holds |
| --- | --- |
| Quick actions | copy the page address, as a Markdown link, or the page title (browsers) |
| Window | the focused window's buttons, links, fields and tabs |
| Tabs | browser tabs; in Zen and Firefox, matched by URL as well as title |
| Menu | every item of the app's menu bar |

Type to rank all groups together, or narrow to one with a prefix: `>` actions, `#` window, `@` tabs, `/` menu (or `tab:`, `menu:`, …). ↑/↓ to move, ↵ to press. Rows are pressed through the accessibility API (`AXPress`), so they work on sheets and on controls that are covered or scrolled away.

The matcher (`Scoot/Fuzzy.swift`) requires every query token to be a subsequence and scores the best placement, with bonuses for the start of the string, word boundaries and consecutive runs: `cplmrg` finds "Complete merge", and `sfprag` finds the tab whose URL holds `sfp-rag-dev`.

## Development

```sh
scripts/dev                 # build, sign, relaunch
scripts/dev --dump          # build, relaunch with SCOOT_DUMP_ELEMENTS=1
scripts/test                # unit tests
```

Grant Accessibility to the built app once; signing with an Apple Development identity keeps the grant across rebuilds (`SCOOT_SIGN_IDENTITY` overrides it). Debug → *Dump Accessibility Elements* writes every element of the focused window to `~/Library/Application Support/Scoot/element-dumps/` and the pasteboard.

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

---

<img align="right" width="128" alt="App icon" src="./Scoot/Assets.xcassets/AppIcon.appiconset/512.png" />

Pressto is a small utility app that provides fast, keyboard-driven control over the mouse pointer. Pressto lets you move your mouse—and click and drag, too—all from the comfort of your keyboard.

Pressto supports two primary navigation modes: **element-based**, and **grid-based**.

* **Element-based navigation:** MacOS accessibility APIs are used to find user interface elements, such as buttons and links, on the user's screen. (In this mode, Pressto will look for elements in the focused window of the frontmost app.) Here, for example, Pressto has identified the only link on the page _("More information...")_, and assigned it the key sequence "aa":

<p align="center">
  <img src="./Assets/Examples/element-nav.png" alt="Pressto using the element-based navigation mode" />
</p>

* **Grid-based navigation:** all connected screens are subdivided into a grid of equally-sized cells.

<p align="center">
  <img src="./Assets/Examples/grid-nav.png" alt="Pressto using the grid-based navigation mode" />
</p>

Each location is identified by a unique character sequence, making each element (or cell) uniquely addressable with the keyboard — simply type the associated key sequence to teleport your mouse cursor to that location.

Pressto also supports moving the mouse cursor using text editing keyboard shortcuts that you're likely already familiar with (specifically, those for moving the insertion point). Pressto supports standard MacOS text editing shortcuts, as well as Emacs and vi keybindings. For a full breakdown, see the [usage documentation](#usage).

There's also a supplementary usage mode:

* **Freestyle:** a freeform usage mode that offers no special navigation assistance. It's like using the grid-based navigation mode, but _without_ bringing up the grid.

Freestyle mode is particularly handy for those cases where you want to quickly nudge the cursor using the (re-purposed) text editing keyboard shortcuts, and would prefer to not have the grid or element-based views on screen.

## About

* Scoot, which Pressto is built on, started as an experiment: an attempt to craft a keyboard-driven mouse movement utility that's efficient, and (more importantly) that users will actually _want_ to use. Pressto adds search on top, for the controls you know by name rather than by position.

* Pressto is _not_ intended to replace the mouse or trackpad entirely. It's here to augment them.

* Pressto runs on macOS 12 (Monterey) and later.

* Pressto is an AppKit app, written in Swift. (There's still some Carbon in here, too! [Yes][carbon-events], [really][carbon-accessibility].)

* Pressto complements mouse-related accessibility tools that ship as part of MacOS, such as [Mouse Keys][mouse-keys] and other [accessibility shortcuts][mac-accessibility-shortcuts], in addition to mouse emulation provided via keyboard firmware ([QMK][qmk-mouse-keys], for example).

## Usage

To activate Pressto in the **element-based navigation mode**, use the ⇧⌘J global keyboard shortcut. Alternatively, to activate Pressto in the **grid-based navigation mode**, use the ⇧⌘K global keyboard shortcut. And for **freestyle mode**, use the ⇧⌘L global keyboard shortcut. (These shortcuts can be customized.)

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

* You can scroll, by pressing the Shift key in conjunction with the arrow key (↑, ↓, ←, →) pointing in the desired scroll direction.

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

To customize Pressto's settings, click Pressto's menu bar icon, then “Preferences…”, or type `⌘,` while Pressto is in the foreground. In addition to modifying keybindings, it is also possible to modify Pressto's appearance (including font sizes, colours, opacity, etc.).

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

All global keybindings are fully customizable. To modify the keybindings, click Pressto's menu bar icon, then “Preferences…”, and select the “Keybindings” tab.

#### Local Keybindings

Local keybindings are only active when Pressto is active (i.e., when Pressto is in the foreground).

Note that vi keybindings are not enabled by default, and must be explicitly toggled on (click Pressto's menu bar icon, then “Preferences…”, select the “Keybindings” tab, and then change the keybinding mode). Emacs keybindings (and most system keybindings) are disabled when vi keybindings are active.

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

On first run, you'll be presented with a prompt like the following:

<p align="center">
  <img width="450" src="./Assets/Documentation/accessibility-prompt.png" alt="Scoot.app would like to control this computer using accessibility features" />
</p>

**Pressto will not work unless access is granted.** (Note that Pressto does not collect any user or usage-related information, and does not make any network requests. The app runs entirely locally, and treats its privileged access with the utmost respect.)

To grant this permission, click _“Open System Preferences”_. Next, click the lock in the bottom left corner (_“Click the lock to make changes”_).

<p align="center">
  <img width="550" src="./Assets/Documentation/privacy-locked.png" alt="Locked accessibility settings" />
</p>

Finally, check _“Scoot.app”_ (the bundle still carries the old name) to give Pressto the ability to move your cursor, and to click, drag, and scroll.

<p align="center">
  <img width="550" src="./Assets/Documentation/accessibility-access-granted.png" alt="Scoot.app granted accessibility access" />
</p>

See the [usage documentation](#usage) for details on how to use Pressto.

If you're finding Pressto helpful, you may want to configure the app to launch automatically when you log in. To set this up, open System Preferences again, click _“Users & Groups”_, and then _“Login Items”_:

<p align="center">
  <img width="550" src="./Assets/Documentation/login-items-locked.png" alt="Locked login items settings" />
</p>

As before, you'll need to click the lock in the bottom left corner to unlock this preference pane. Once unlocked, click the “+” button, and select _“Scoot.app”_ from the _Applications_ folder. Checking the _“Hide”_ checkbox is recommended.

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
