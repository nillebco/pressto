import AXSwift
import AppKit
import OSLog

/// One searchable, actionable entry of the palette: a control of the focused
/// window, or an item of the frontmost app's menu bar.
///
/// The palette is the system-wide counterpart of the pagecast browser
/// extension: instead of hinting every element with a label (element mode), it
/// lists them by accessible name and lets the user fuzzy-search and press one.
struct PaletteItem {

    enum Kind {
        case element
        case menuItem
        /// A browser tab (Zen, Safari, Chromium all tag them AXTabButton).
        case tab
        /// A macro Scoot runs itself ("Copy page address"), not a control.
        case command
    }

    let kind: Kind

    var group: PaletteGroup {
        switch kind {
        case .command: return .commands
        case .element: return .controls
        case .tab: return .tabs
        case .menuItem: return .menu
        }
    }

    /// What the user reads and types against ("Save", "Back", "Reply all").
    let label: String

    /// Where the item lives ("File › Export", "button"), shown dimmed and also
    /// searchable, so `file exp` finds the menu item.
    let context: String

    /// Accessibility role, used for the glyph.
    let role: String

    /// The control to press; nil for commands.
    let element: UIElement?


    /// The element's frame in Cocoa screen coordinates, when it has one: the
    /// fallback click target for elements that do not support `AXPress`.
    let frame: CGRect?

    /// What a command does; nil for controls and menu items.
    var run: (() -> Void)? = nil

    /// A second line under the label: a tab's address. Searchable.
    var detail: String? = nil

    /// The text the fuzzy matcher scores. The label comes first, so match
    /// indices below `label.count` can be highlighted in the label.
    var searchText: String {
        [label, context, detail].compactMap { $0 }.joined(separator: " ")
    }
}

enum PaletteSource {

    /// Roles worth offering from the window. Cells, rows and static text are
    /// left out: they flood the list without being something one "presses".
    static let elementRoles: Set<String> = [
        Role.button.rawValue,
        Role.link.rawValue,
        Role.checkBox.rawValue,
        Role.radioButton.rawValue,
        Role.popUpButton.rawValue,
        Role.menuButton.rawValue,
        Role.textField.rawValue,
        Role.textArea.rawValue,
        Role.comboBox.rawValue,
        Role.slider.rawValue,
        Role.disclosureTriangle.rawValue,
    ]

    /// Bounds the walk on heavy pages; the palette has to open fast.
    static let maximumElements = 1500
    static let maximumDepth = 64

    /// Controls of the focused window that are actually on screen.
    ///
    /// Safe to call off the main thread: the AX API is thread-agnostic, and
    /// this is the slow half (~150 ms on a busy Zen window), so the palette
    /// opens first and fills in when it returns.
    static func windowItems(for runningApp: NSRunningApplication) -> [PaletteItem] {

        guard let app = Application(runningApp) else {
            OSLog.main.error("Palette: cannot open an accessibility application for \(runningApp.bundleIdentifier ?? "<unknown>", privacy: .public)")
            return []
        }

        // Chromium/Electron apps (Teams, Slack, VS Code) keep their tree nearly
        // empty until an assistive client asks for it. VoiceOver's attribute
        // (AXEnhancedUserInterface) is already set by Scoot at launch; this one
        // is the Electron-specific switch.
        try? app.setAttribute("AXManualAccessibility", value: true)

        let started = Date()
        var items = elementItems(of: app)

        if let bundleIdentifier = runningApp.bundleIdentifier, BrowserSessions.supports(bundleIdentifier) {
            items = withTabAddresses(items, from: BrowserSessions.urlsByTitle(for: bundleIdentifier))
        }

        OSLog.main.log("Palette: \(items.count) element(s), \(items.filter { $0.kind == .tab }.count) tab(s), page commands: \(items.contains { $0.kind == .command } ? "yes" : "no", privacy: .public) for \(runningApp.bundleIdentifier ?? "<unknown>", privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")

        return items
    }

    /// Gives each tab its address, matched by title. Duplicate titles are
    /// consumed in session order, which follows the sidebar order closely
    /// enough for "Sign out" × 2 to land on the right rows most of the time.
    private static func withTabAddresses(_ items: [PaletteItem], from urlsByTitle: [String: [URL]]) -> [PaletteItem] {
        var queues = urlsByTitle
        return items.map { item in
            guard item.kind == .tab, var queue = queues[item.label], !queue.isEmpty else {
                return item
            }
            let url = queue.removeFirst()
            queues[item.label] = queue
            var item = item
            item.detail = displayAddress(url)
            return item
        }
    }

    /// host + path, without scheme, query or fragment — what pagecast shows.
    private static func displayAddress(_ url: URL) -> String {
        guard let host = url.host else {
            return url.absoluteString
        }
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    /// Every enabled leaf item of the app's menu bar. Changes rarely, so the
    /// caller caches it per process and refreshes it in the background.
    static func menuItems(for runningApp: NSRunningApplication) -> [PaletteItem] {
        guard let app = Application(runningApp) else {
            return []
        }
        return menuBarItems(of: app)
    }

    /// The focused window's frame in Cocoa screen coordinates: where the
    /// palette should appear, regardless of where the mouse is.
    static func focusedWindowFrame(of runningApp: NSRunningApplication) -> CGRect? {
        guard let app = Application(runningApp),
              let window: UIElement = try? app.attribute(.focusedWindow),
              let frame: CGRect = try? window.attribute(.frame) else {
            return nil
        }
        return frame.convertToCocoa()
    }

    // MARK: - Window elements

    private static func elementItems(of app: Application) -> [PaletteItem] {

        guard let window: UIElement = try? app.attribute(.focusedWindow),
              let windowFrame: CGRect = try? window.attribute(.frame) else {
            return []
        }

        var items = [PaletteItem]()
        var pageURL: URL?

        /// `clip` is the horizontal extent every ancestor allows (raw AX
        /// coordinates); `inTabGroup` is set below an AXTabGroup.
        func traverse(_ node: UIElement, depth: Int, clip: ClosedRange<CGFloat>, inTabGroup: Bool) {

            guard depth < maximumDepth, items.count < maximumElements,
                  let children: [UIElement] = try? node.arrayAttribute(.children) else {
                return
            }

            for child in children where child != node {

                // Prune what is not on screen, subtree included — this is what
                // keeps the walk fast (~750 → ~150 ms on a busy Zen window).
                //
                // Horizontally, an element must fall inside every ancestor:
                // Zen keeps the tabs of *all* workspaces in one list and parks
                // the inactive ones sideways, beside the sidebar (some even
                // inside the window, over the page), so the window alone is not
                // a tight enough bound.
                //
                // Vertically, the window is the bound, except inside a tab
                // group: there, below the fold just means "scroll the tab list",
                // and those tabs are as reachable as the visible ones.
                //
                // A node *without* a frame is kept: Firefox's AXWebArea can
                // report none, yet holds the whole page.
                let rawFrame: CGRect? = try? child.attribute(.frame)
                var childClip = clip

                if let rawFrame {
                    guard !rawFrame.isEmpty,
                          rawFrame.maxX > clip.lowerBound, rawFrame.minX < clip.upperBound,
                          inTabGroup || rawFrame.intersects(windowFrame) else {
                        continue
                    }
                    childClip = max(clip.lowerBound, rawFrame.minX)...min(clip.upperBound, rawFrame.maxX)
                }

                // Read the raw string: AXSwift's `Role` enum has no case for
                // roles it does not know (AXWebArea among them), so `role()`
                // returns nil for exactly the node holding the page URL.
                let role: String = (try? child.attribute(.role)) ?? ""

                // The visible page of a browser (Safari, Chromium, Firefox/Zen
                // all expose AXURL on it). Off-screen pages were pruned above,
                // so the first one is the page the user is looking at.
                if pageURL == nil, role == "AXWebArea",
                   let url = try? child.attribute("AXURL") as NSURL? {
                    pageURL = url as URL
                }

                if elementRoles.contains(role),
                   (try? child.attribute(.enabled) as Bool?) ?? true,
                   let label = label(of: child, role: role) {

                    let frame = rawFrame.map { $0.convertToCocoa() }
                    let subrole: String? = role == Role.radioButton.rawValue ? (try? child.attribute(.subrole)) : nil
                    let isTab = subrole == "AXTabButton"

                    items.append(PaletteItem(
                        kind: isTab ? .tab : .element,
                        label: label,
                        context: isTab ? "tab" : roleName(role),
                        role: role,
                        element: child,
                        frame: frame
                    ))
                }

                traverse(child, depth: depth + 1, clip: childClip, inTabGroup: inTabGroup || role == Role.tabGroup.rawValue)
            }
        }

        traverse(window, depth: 0, clip: windowFrame.minX...windowFrame.maxX, inTabGroup: false)

        if let pageURL {
            let title: String = (try? window.attribute(.title)) ?? ""
            items.insert(contentsOf: pageCommands(url: pageURL, title: clean(title)), at: 0)
        }

        return deduplicated(items)
    }

    /// The best human-readable name of an element, or nil when it has none
    /// (an unlabeled icon button is useless in a text palette).
    private static func label(of element: UIElement, role: String) -> String? {

        let candidates: [String?] = [
            try? element.attribute(.title),
            try? element.attribute(.description),
            try? element.attribute(.help),
            try? element.attribute("AXPlaceholderValue"),
        ]

        if let text = candidates.lazy.compactMap({ $0 }).map(clean).first(where: { !$0.isEmpty }) {
            return text
        }

        // Web links usually carry their text in a static-text child, not in
        // their own title.
        if role == Role.link.rawValue || role == Role.button.rawValue,
           let children: [UIElement] = try? element.arrayAttribute(.children) {
            for child in children.prefix(4) {
                if let value: String = try? child.attribute(.value), !clean(value).isEmpty {
                    return clean(value)
                }
            }
        }

        return nil
    }

    /// Pages often repeat the same link (logo + nav + footer); keep the first.
    private static func deduplicated(_ items: [PaletteItem]) -> [PaletteItem] {
        var seen = Set<String>()
        return items.filter { $0.kind == .tab || seen.insert("\($0.role)|\($0.label)").inserted }
    }

    // MARK: - Page commands

    /// Macros offered whenever the focused window shows a web page.
    private static func pageCommands(url: URL, title: String) -> [PaletteItem] {

        let address = url.absoluteString
        let name = title.isEmpty ? (url.host ?? address) : title

        func command(_ label: String, _ run: @escaping () -> Void) -> PaletteItem {
            PaletteItem(kind: .command, label: label, context: "page", role: "", element: nil, frame: nil, run: run)
        }

        return [
            command("Copy page address") { copy(address) },
            command("Copy page link as Markdown") { copy("[\(name)](\(address))") },
            command("Copy page title") { copy(name) },
        ]
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Menu bar

    private static func menuBarItems(of app: Application) -> [PaletteItem] {

        guard let menuBar: UIElement = try? app.attribute(.menuBar),
              let topLevel: [UIElement] = try? menuBar.arrayAttribute(.children) else {
            return []
        }

        var items = [PaletteItem]()

        // Skip the Apple menu: it is the same in every app.
        for menu in topLevel.dropFirst() {
            let title: String = (try? menu.attribute(.title)) ?? ""
            collectMenuItems(in: menu, path: [title], into: &items)
        }

        return items
    }

    private static func collectMenuItems(in node: UIElement, path: [String], into items: inout [PaletteItem]) {

        guard path.count < 6,
              let children: [UIElement] = try? node.arrayAttribute(.children) else {
            return
        }

        for child in children {

            let role: String = (try? child.attribute(.role)) ?? ""

            if role == Role.menu.rawValue {
                collectMenuItems(in: child, path: path, into: &items)
                continue
            }

            guard role == Role.menuItem.rawValue else {
                continue
            }

            let title = clean((try? child.attribute(.title)) ?? "")

            guard !title.isEmpty else {
                continue // separator
            }

            let submenu: [UIElement] = (try? child.arrayAttribute(.children)) ?? []

            if submenu.isEmpty {
                guard (try? child.attribute(.enabled) as Bool?) ?? true else {
                    continue
                }
                items.append(PaletteItem(
                    kind: .menuItem,
                    label: title,
                    context: path.joined(separator: " › "),
                    role: role,
                    element: child,
                    frame: nil
                ))
            } else {
                collectMenuItems(in: child, path: path + [title], into: &items)
            }
        }
    }

    // MARK: - Acting

    /// Presses the item: `AXPress` when supported, focus for text inputs, and a
    /// synthesized click at the element's center as a last resort.
    @discardableResult
    static func perform(_ item: PaletteItem) -> Bool {

        if let run = item.run {
            run()
            return true
        }

        guard let element = item.element else {
            return false
        }

        let actions = (try? element.actionsAsStrings()) ?? []

        if actions.contains(Action.press.rawValue) {
            do {
                try element.performAction(.press)
                return true
            } catch {
                OSLog.main.error("Palette: AXPress failed on \(item.label, privacy: .private(mask: .hash)): \(String(describing: error), privacy: .public)")
            }
        }

        if [Role.textField.rawValue, Role.textArea.rawValue, Role.comboBox.rawValue].contains(item.role),
           (try? element.setAttribute(.focused, value: true)) != nil {
            return true
        }

        if let frame = item.frame {
            let mouse = Mouse()
            mouse.move(to: CGPoint(x: frame.midX, y: frame.midY))
            usleep(20000)
            mouse.click(button: .left)
            return true
        }

        return false
    }

    // MARK: - Helpers

    private static func clean(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func roleName(_ role: String) -> String {
        switch role {
        case Role.link.rawValue: return "link"
        case Role.button.rawValue: return "button"
        case Role.checkBox.rawValue: return "checkbox"
        case Role.radioButton.rawValue: return "option"
        case Role.popUpButton.rawValue, Role.menuButton.rawValue: return "menu"
        case Role.textField.rawValue, Role.textArea.rawValue, Role.comboBox.rawValue: return "field"
        case Role.slider.rawValue: return "slider"
        case Role.disclosureTriangle.rawValue: return "disclosure"
        default: return role.replacingOccurrences(of: "AX", with: "").lowercased()
        }
    }
}
