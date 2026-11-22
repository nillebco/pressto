import AppKit
import AXSwift
import Network
import OSLog

/// Serves the phone remote (see `Remote`) on 127.0.0.1 only.
///
/// One request per connection: read until the request is complete, answer,
/// close. `tailscale serve` is the only intended client.
final class RemoteServer: @unchecked Sendable {

    typealias Executor = @MainActor @Sendable (Remote.Command) -> String

    private let queue = DispatchQueue(label: "co.nillebco.pressto.remote")
    private var listener: NWListener?
    private let allowedLogins: Set<String>
    private let page: Data
    private let execute: Executor

    init(allowedLogins: Set<String>, page: Data, execute: @escaping Executor) {
        self.allowedLogins = Set(allowedLogins.map { $0.lowercased() })
        self.page = page
        self.execute = execute
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Remote.port)!)
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            OSLog.main.log("Remote: listener \(String(describing: state), privacy: .public)")
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Remote.maximumRequestSize) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            switch Remote.parse(buffer) {
            case .incomplete:
                guard !isComplete, error == nil else {
                    connection.cancel()
                    return
                }
                self.receive(on: connection, buffer: buffer)
            case .invalid:
                self.send(Remote.json(status: 400, ["error": "bad request"]), on: connection)
            case .complete(let request):
                self.handle(request, on: connection)
            }
        }
    }

    private func handle(_ request: Remote.Request, on connection: NWConnection) {

        let login: String
        switch Remote.authorize(request, allowedLogins: allowedLogins) {
        case .forbidden(let reason):
            OSLog.main.log("Remote: refused \(request.method, privacy: .public) \(request.path, privacy: .public): \(reason, privacy: .public)")
            send(Remote.json(status: 403, ["error": reason]), on: connection)
            return
        case .allowed(let user):
            login = user
        }

        switch (request.method, request.path) {
        case ("GET", "/"):
            send(Remote.response(status: 200, contentType: "text/html; charset=utf-8", body: page), on: connection)
            return
        case ("GET", "/healthz"):
            send(Remote.json(status: 200, ["ok": true, "user": login]), on: connection)
            return
        case ("POST", _):
            break
        default:
            send(Remote.json(status: 405, ["error": "method not allowed"]), on: connection)
            return
        }

        switch Remote.decode(request) {
        case .failure(.notFound):
            send(Remote.json(status: 404, ["error": "not found"]), on: connection)
        case .failure(.invalid(let message)):
            send(Remote.json(status: 400, ["error": message]), on: connection)
        case .success(let command):
            let execute = self.execute
            DispatchQueue.main.async {
                let detail = MainActor.assumeIsolated { execute(command) }
                self.send(Remote.json(status: 200, ["ok": true, "detail": detail]), on: connection)
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Synthetic keys

/// Posts keys as if typed on this Mac's keyboard: they reach whatever has the
/// keyboard, the palette or an overlay of Pressto's included.
enum RemoteKeys {

    static func post(code: UInt16, modifiers: Remote.Modifiers) {
        var flags = CGEventFlags()
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }

        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    static func type(_ text: String) {
        for stroke in Remote.keystrokes(for: text) {
            if let code = stroke.code {
                post(code: code, modifiers: stroke.modifiers)
            } else {
                var units = Array(String(stroke.character).utf16)
                for keyDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: keyDown)
                    event?.flags = []
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                    event?.post(tap: .cghidEventTap)
                }
            }
            usleep(3000)
        }
    }
}

// MARK: - App integration

/// The running server, when the remote is on.
@MainActor private var remoteServer: RemoteServer?

/// Set once a delayed search-field focus succeeded, so later retries do not
/// select the text the user has started typing.
@MainActor private var searchFocusFlag = false

extension AppDelegate {
    fileprivate var searchFocusedRecently: Bool {
        get { searchFocusFlag }
        set { searchFocusFlag = newValue }
    }
}

extension AppDelegate {

    private static let remoteEnabledKey = "RemoteEnabled"
    private static let remoteAllowedLoginsKey = "RemoteAllowedLogins"
    private static let remoteAddressKey = "RemoteAddress"

    private static let remoteMenuTitle = "Phone Remote (Tailscale)"
    private static let remoteCopyTitle = "Copy Phone Remote Address"

    /// Adds the remote's items above Settings… and starts it if it was on.
    func installRemoteMenuItems() {

        let toggle = NSMenuItem(title: Self.remoteMenuTitle, action: #selector(toggleRemotePressed(_:)), keyEquivalent: "")
        toggle.target = self
        let copy = NSMenuItem(title: Self.remoteCopyTitle, action: #selector(copyRemoteAddressPressed(_:)), keyEquivalent: "")
        copy.target = self

        let index = menu.items.firstIndex { $0.title.hasPrefix("Settings") } ?? menu.items.count
        menu.insertItem(.separator(), at: index)
        menu.insertItem(copy, at: index)
        menu.insertItem(toggle, at: index)

        if UserDefaults.standard.bool(forKey: Self.remoteEnabledKey) {
            startRemote()
        }
        refreshRemoteMenuItems()
    }

    @objc func toggleRemotePressed(_ sender: NSMenuItem) {
        if remoteServer == nil {
            startRemote()
        } else {
            remoteServer?.stop()
            remoteServer = nil
            UserDefaults.standard.set(false, forKey: Self.remoteEnabledKey)
            OSLog.main.log("Remote: stopped")
        }
        refreshRemoteMenuItems()
    }

    @objc func copyRemoteAddressPressed(_ sender: NSMenuItem) {
        guard let address = UserDefaults.standard.string(forKey: Self.remoteAddressKey) else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }

    private func refreshRemoteMenuItems() {
        let on = remoteServer != nil
        menu.items.first { $0.title == Self.remoteMenuTitle }?.state = on ? .on : .off
        menu.items.first { $0.title == Self.remoteCopyTitle }?.isHidden = !on
    }

    /// Starts listening, after learning from Tailscale who is signed in on
    /// this Mac (the default allow list) and its tailnet address.
    private func startRemote() {

        guard let page = Bundle.main.url(forResource: "Remote", withExtension: "html").flatMap({ try? Data(contentsOf: $0) }) else {
            OSLog.main.error("Remote: Remote.html is missing from the bundle")
            NSSound.beep()
            return
        }

        let identity = TailscaleIdentity.current()
        if let address = identity?.address {
            UserDefaults.standard.set(address, forKey: Self.remoteAddressKey)
        }

        var allowed = UserDefaults.standard.stringArray(forKey: Self.remoteAllowedLoginsKey) ?? []
        if allowed.isEmpty, let login = identity?.login {
            allowed = [login]
            UserDefaults.standard.set(allowed, forKey: Self.remoteAllowedLoginsKey)
        }
        guard !allowed.isEmpty else {
            OSLog.main.error("Remote: no allowed login; is Tailscale running and signed in?")
            NSSound.beep()
            return
        }

        let server = RemoteServer(allowedLogins: Set(allowed), page: page) { [weak self] command in
            self?.runRemote(command) ?? "gone"
        }
        do {
            try server.start()
        } catch {
            OSLog.main.error("Remote: cannot listen on 127.0.0.1:\(Remote.port): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
            return
        }
        remoteServer = server
        UserDefaults.standard.set(true, forKey: Self.remoteEnabledKey)
        OSLog.main.log("Remote: listening on 127.0.0.1:\(Remote.port) for \(allowed.joined(separator: ", "), privacy: .public)")
    }

    private func runRemote(_ command: Remote.Command) -> String {
        switch command {
        case let .key(code, modifiers):
            RemoteKeys.post(code: code, modifiers: modifiers)
            return "key"
        case .type(let text):
            RemoteKeys.type(text)
            return "typed"
        case .mode(.palette):
            openPaletteForRemote()
            return "palette"
        case .mode(.labels):
            bringToForeground(using: .element)
            return "labels"
        case .mode(.grid):
            bringToForeground(using: .grid)
            return "grid"
        case .mode(.freestyle):
            bringToForeground(using: .freestyle)
            return "freestyle"
        case .search(let text):
            let wasOpen = palette.isVisible && NSWorkspace.shared.frontmostApplication != .current
            if !wasOpen {
                openPaletteForRemote()
            }
            // Let the panel take the keyboard; replace any earlier query.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if wasOpen {
                    RemoteKeys.post(code: Remote.keyCodes["a"]!, modifiers: .command)
                }
                RemoteKeys.type(text)
            }
            return "search"
        case let .scroll(direction, all):
            scrollForRemote(direction, all: all)
            return all ? "scrolled all the way" : "scrolled"
        case .focusTV:
            return focusTV()
        case .locatePointer:
            PointerLocator.ring(at: NSEvent.mouseLocation)
            return "pointer"
        case .siteHome:
            return goToSiteHome()
        case .volume(let change):
            return MacVolume.change(change)
        case .press(let labels):
            return pressNamed(labels)
        case .siteSearch(let labels):
            if let focused = focusSiteSearch() {
                return focused
            }
            // Sites such as Canal+ only add the search field once their
            // "Rechercher" button is pressed: press it, then focus the field
            // when it appears.
            let pressed = pressNamed(labels)
            guard pressed.hasPrefix("pressed") else {
                return pressed
            }
            for delay in [0.5, 1.0, 1.8] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, !self.searchFocusedRecently else { return }
                    if self.focusSiteSearch() != nil {
                        self.searchFocusedRecently = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.searchFocusedRecently = false }
                    }
                }
            }
            return pressed + "; waiting for the search field"
        }
    }

    /// Focuses the first search field inside the page (`AXSearchField`, which
    /// is how WebKit exposes `<input type=search>` and `role=searchbox`), and
    /// selects its text so a new query replaces the old one. Never Safari's
    /// address bar: only fields below an `AXWebArea` count.
    private func focusSiteSearch() -> String? {
        guard let running = NSWorkspace.shared.frontmostApplication, running != .current,
              let app = Application(running),
              let window: UIElement = try? app.attribute(.focusedWindow) else {
            return nil
        }
        var queue: [(UIElement, Bool, Int)] = [(window, false, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 3000 {
            let (node, inPage, depth) = queue.removeFirst()
            visited += 1
            let role = node.string("AXRole") ?? ""
            if inPage, ["AXTextField", "AXComboBox"].contains(role), node.string("AXSubrole") == "AXSearchField" {
                guard (try? node.setAttribute(.focused, value: true)) != nil else { continue }
                usleep(60000)
                RemoteKeys.post(code: Remote.keyCodes["a"]!, modifiers: .command)
                OSLog.main.log("Remote: focused the page's search field")
                return "search field focused"
            }
            guard depth < 40, let children: [UIElement] = try? node.arrayAttribute(.children) else { continue }
            let nowInPage = inPage || role == "AXWebArea"
            queue += children.filter { $0 != node }.map { ($0, nowInPage, depth + 1) }
        }
        return nil
    }

    /// Opens the palette over the app being watched, never over Pressto's own
    /// overlay (left in front by Labels, Grid or Free): there it would have
    /// no window to sit on and could vanish. Reopens it if already open.
    private func openPaletteForRemote() {
        if palette.isVisible {
            palette.close()
        }
        if NSWorkspace.shared.frontmostApplication == .current || inputWindow.isVisible {
            bringToBackground { [weak self] in
                self?.showPalette()
            }
        } else {
            showPalette()
        }
    }

    /// Loads the front tab's site root (`https://host/`) by script.
    private func goToSiteHome() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              ScriptableBrowsers.supports(id) else {
            return "not a browser"
        }
        let get = id.hasPrefix("com.apple.Safari") ? "URL of current tab of front window" : "URL of active tab of front window"
        let read = Process()
        read.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        read.arguments = ["-e", "tell application id \"\(id)\" to get \(get)"]
        let output = Pipe()
        read.standardOutput = output
        read.standardError = Pipe()
        guard (try? read.run()) != nil else { return "no script" }
        read.waitUntilExit()
        let address = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: address), let scheme = url.scheme, ["http", "https"].contains(scheme),
              let host = url.host, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else {
            return "no page"
        }
        let home = "\(scheme)://\(host)/"
        let set = id.hasPrefix("com.apple.Safari") ? "set URL of current tab of front window to" : "set URL of active tab of front window to"
        let write = Process()
        write.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        write.arguments = ["-e", "tell application id \"\(id)\" to \(set) \"\(home)\""]
        write.standardOutput = Pipe()
        write.standardError = Pipe()
        try? write.run()
        return "home: \(host)"
    }

    /// Presses the first control named one of `labels` in the front window,
    /// trying the names in order: exact match first, then prefix.
    private func pressNamed(_ labels: [String]) -> String {
        guard let app = NSWorkspace.shared.frontmostApplication, app != .current else {
            return "Pressto is in front; tap Back to TV"
        }
        let items = PaletteSource.windowItems(for: app).filter { $0.kind == .element }
        let wanted = labels.map { $0.lowercased() }
        for matches in [{ (l: String, w: String) in l == w }, { (l: String, w: String) in l.hasPrefix(w) }] {
            for name in wanted {
                if let item = items.first(where: { matches($0.label.lowercased(), name) }) {
                    PaletteSource.perform(item)
                    OSLog.main.log("Remote: pressed \(item.label, privacy: .private(mask: .hash))")
                    return "pressed \(item.label)"
                }
            }
        }
        return "nothing named \(labels.first ?? "")"
    }

    /// A remote scroll step: about a third of a TV screen.
    private static let remoteScrollStep: CGFloat = 300

    /// Scrolls at the pointer, after moving it onto the frontmost window if it
    /// is elsewhere (on another screen, or over the menu bar): the scroll goes
    /// to whatever is under it.
    private func scrollForRemote(_ direction: Remote.Direction, all: Bool) {
        let mouse = Mouse()
        var location = NSEvent.mouseLocation
        let app = NSWorkspace.shared.frontmostApplication
        if let app, app != .current,
           let frame = PaletteSource.focusedWindowFrame(of: app),
           !frame.insetBy(dx: 8, dy: 8).contains(location) {
            location = CGPoint(x: frame.midX, y: frame.midY)
        }
        // Always post a move, even on the spot: WebKit picks the view to
        // scroll from the last mouse movement it saw, so a bare wheel event
        // after the pointer sat still does nothing in Safari (other apps
        // scroll anyway). Freestyle never hit this: its pointer always moved.
        mouse.move(to: location)
        usleep(15000)
        OSLog.main.log("Remote: scroll \(direction.rawValue, privacy: .public)\(all ? " all" : "", privacy: .public) at \(Int(location.x)),\(Int(location.y)) in \(app?.bundleIdentifier ?? "?", privacy: .public)")
        let step = all ? KeyboardInputWindow.scrollToEndDistance : Self.remoteScrollStep
        let to: NSPoint.Direction = switch direction {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        }
        mouse.scroll(to, stepSize: step)
    }

    /// The app the remote drives, Safari unless `RemoteTVApp` names another.
    private func focusTV() -> String {
        let bundleIdentifier = UserDefaults.standard.string(forKey: "RemoteTVApp") ?? "com.apple.Safari"
        // Hide Pressto's own overlays first, as Esc would.
        if palette.isVisible || inputWindow.isVisible {
            palette.close()
            bringToBackground()
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return "\(bundleIdentifier) not installed"
        }
        // Opening the app activates it, and macOS switches to its Space (the
        // full-screen one included); `activate()` from a background app may be
        // ignored.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return "back to \(url.deletingPathExtension().lastPathComponent)"
    }
}

/// Who is signed in to Tailscale on this Mac, and the Mac's tailnet address.
enum TailscaleIdentity {

    static let candidates = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
        "/usr/local/bin/tailscale",
    ]

    static func current() -> (login: String, address: String?)? {

        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["status", "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let me = json["Self"] as? [String: Any],
              let userID = me["UserID"] as? Int,
              let users = json["User"] as? [String: Any],
              let user = users[String(userID)] as? [String: Any],
              let login = user["LoginName"] as? String else {
            return nil
        }

        let host = (me["DNSName"] as? String).map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
        return (login.lowercased(), host.map { "https://\($0)/" })
    }
}

/// A ring drawn around the pointer for a second and a half, big enough to
/// find it on a TV across the room.
@MainActor
enum PointerLocator {

    private static var window: NSWindow?

    static func ring(at point: CGPoint) {
        window?.orderOut(nil)

        let size: CGFloat = 220
        let frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: view.bounds.insetBy(dx: 14, dy: 14), transform: nil)
        ring.fillColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        ring.strokeColor = NSColor.systemYellow.cgColor
        ring.lineWidth = 10
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.8
        ring.shadowRadius = 6
        ring.frame = view.bounds
        view.layer?.addSublayer(ring)

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.6
        pulse.toValue = 0.5
        pulse.duration = 0.5
        pulse.repeatCount = 3
        ring.position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        ring.bounds = view.bounds
        ring.add(pulse, forKey: "pulse")

        window.contentView = view
        window.orderFrontRegardless()
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if self.window === window {
                window.orderOut(nil)
                self.window = nil
            }
        }
    }
}

/// The Mac's output volume, through Standard Additions: no private API, no
/// extra permission.
enum MacVolume {

    static let step = 6

    static func change(_ change: Remote.VolumeChange) -> String {
        let script = switch change {
        case .up: """
            set volume output muted false
            set volume output volume ((output volume of (get volume settings)) + \(step))
            """
        case .down: "set volume output volume ((output volume of (get volume settings)) - \(step))"
        case .mute: "set volume output muted (not (output muted of (get volume settings)))"
        }
        let report = """
            set s to get volume settings
            if output muted of s then return "Mac muted"
            return "Mac volume " & (output volume of s)
            """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: script + "\n" + report)?.executeAndReturnError(&error).stringValue else {
            OSLog.main.error("Remote: volume failed: \(String(describing: error), privacy: .public)")
            return "volume failed"
        }
        return result
    }
}
