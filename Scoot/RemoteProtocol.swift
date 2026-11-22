import Foundation

/// The phone remote's wire format: HTTP parsing, who may call, and the closed
/// set of commands. Free of AppKit, so the test bundle compiles it as is.
///
/// The remote listens on the loopback interface only and is published to the
/// tailnet with `tailscale serve`, which adds the caller's identity to every
/// request (`Tailscale-User-Login`). Nothing else on the network reaches it.
enum Remote {

    static let port: UInt16 = 8765

    /// Requests are a line of JSON; anything bigger is refused unread.
    static let maximumRequestSize = 16 * 1024

    /// Text typed or searched in one request.
    static let maximumTextLength = 200

    // MARK: - HTTP

    struct Request: Equatable {
        let method: String
        /// Without the query string.
        let path: String
        /// Names lowercased.
        let headers: [String: String]
        let body: Data
    }

    enum ParseResult: Equatable {
        case incomplete
        case invalid
        case complete(Request)
    }

    static func parse(_ data: Data) -> ParseResult {

        let data = Data(data) // indices from 0

        guard data.count <= maximumRequestSize else {
            return .invalid
        }
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
            return .incomplete
        }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid
        }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .invalid
        }

        var headers = [String: String]()
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                return .invalid
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else {
            return .invalid
        }
        let body = data[headerEnd.upperBound...]
        guard body.count >= length else {
            return .incomplete
        }

        let target = String(requestLine[1])
        let path = String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])

        return .complete(Request(
            method: String(requestLine[0]).uppercased(),
            path: path,
            headers: headers,
            body: Data(body.prefix(length))
        ))
    }

    static func response(status: Int, contentType: String = "application/json; charset=utf-8", body: Data) -> Data {
        let reason: String = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 413: "Payload Too Large"
        default: "Error"
        }
        let head = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Connection: close",
            "", "",
        ].joined(separator: "\r\n")
        return Data(head.utf8) + body
    }

    static func json(status: Int, _ object: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return response(status: status, body: body)
    }

    // MARK: - Who may call

    enum Verdict: Equatable {
        case allowed(login: String)
        case forbidden(String)
    }

    /// Only tailnet users on the allow list, and, for commands, only the
    /// remote page itself.
    ///
    /// The identity header is set by `tailscale serve`; a request reaching the
    /// loopback port without it came from this Mac, not from the tailnet.
    /// Commands must be JSON: a cross-site page can only send JSON with a CORS
    /// preflight, which this server never answers, so another site open on the
    /// phone cannot drive the Mac with the user's tailnet identity. A browser's
    /// Origin, when sent, must be the remote's own host.
    static func authorize(_ request: Request, allowedLogins: Set<String>) -> Verdict {

        guard let login = request.headers["tailscale-user-login"]?.lowercased(), !login.isEmpty else {
            return .forbidden("not a tailnet request")
        }
        guard allowedLogins.contains(login) else {
            return .forbidden("\(login) is not allowed")
        }

        if request.method == "POST" {
            guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
                return .forbidden("commands must be JSON")
            }
            if let origin = request.headers["origin"] {
                let hosts = [request.headers["host"], request.headers["x-forwarded-host"]].compactMap { $0 }
                guard let originHost = URL(string: origin)?.host, hosts.contains(where: { hostOnly($0) == originHost }) else {
                    return .forbidden("cross-origin request")
                }
            }
        }

        return .allowed(login: login)
    }

    private static func hostOnly(_ host: String) -> String {
        String(host.split(separator: ":", maxSplits: 1)[0])
    }

    // MARK: - Commands

    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        static let names: [String: Modifiers] = [
            "shift": .shift, "control": .control, "option": .option, "command": .command,
        ]
    }

    enum Mode: String, CaseIterable, Sendable {
        case palette, labels, grid, freestyle
    }

    enum Command: Equatable, Sendable {
        /// One key from `keyCodes`, with modifiers.
        case key(code: UInt16, modifiers: Modifiers)
        /// Text typed into whatever has the keyboard (a palette query, labels).
        case type(String)
        case mode(Mode)
        /// Opens the palette and types the query.
        case search(String)
        /// Scrolls whatever is under the pointer, in any mode; `all` goes to
        /// the end (back to the top, a carousel's start).
        case scroll(Direction, all: Bool)
        /// Brings the TV app (Safari) forward, and with it its Space.
        case focusTV
        /// Rings the pointer on screen for a moment.
        case locatePointer
        /// Goes to the home page of the site in the front tab.
        case siteHome
        /// Presses the first control of the front window named one of these
        /// (case-insensitive), without opening the palette.
        case press([String])
    }

    enum Direction: String, Sendable {
        case up, down, left, right
    }

    enum DecodeError: Error, Equatable {
        case notFound
        case invalid(String)
    }

    /// The keys a remote may press, as macOS virtual key codes (ANSI layout).
    /// A closed list: no function keys, no media keys, no ⌘-anything beyond
    /// what the modifiers allow on these.
    static let keyCodes: [String: UInt16] = {
        var codes: [String: UInt16] = [
            "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
            "home": 115, "pageup": 116, "end": 119, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "equal": 24, "minus": 27, "leftbracket": 33, "rightbracket": 30, "backslash": 42,
        ]
        let letters: [(Character, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7),
            ("c", 8), ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15),
            ("y", 16), ("t", 17), ("o", 31), ("u", 32), ("i", 34), ("p", 35), ("l", 37),
            ("j", 38), ("k", 40), ("n", 45), ("m", 46),
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23),
            ("9", 25), ("7", 26), ("8", 28), ("0", 29),
        ]
        for (character, code) in letters {
            codes[String(character)] = code
        }
        return codes
    }()

    static func decode(_ request: Request) -> Result<Command, DecodeError> {

        let routes = ["/v1/key", "/v1/type", "/v1/mode", "/v1/search", "/v1/scroll", "/v1/focus", "/v1/locate", "/v1/home", "/v1/press"]
        guard routes.contains(request.path) else {
            return .failure(.notFound)
        }
        guard let object = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return .failure(.invalid("body must be a JSON object"))
        }

        switch request.path {

        case "/v1/key":
            guard let name = (object["key"] as? String)?.lowercased(), let code = keyCodes[name] else {
                return .failure(.invalid("unknown key"))
            }
            var modifiers = Modifiers()
            for modifier in (object["modifiers"] as? [String]) ?? [] {
                guard let flag = Modifiers.names[modifier.lowercased()] else {
                    return .failure(.invalid("unknown modifier \(modifier)"))
                }
                modifiers.insert(flag)
            }
            return .success(.key(code: code, modifiers: modifiers))

        case "/v1/scroll":
            guard let name = object["direction"] as? String, let direction = Direction(rawValue: name) else {
                return .failure(.invalid("unknown direction"))
            }
            return .success(.scroll(direction, all: object["all"] as? Bool ?? false))

        case "/v1/focus":
            return .success(.focusTV)

        case "/v1/locate":
            return .success(.locatePointer)

        case "/v1/home":
            return .success(.siteHome)

        case "/v1/press":
            guard let labels = object["labels"] as? [String], !labels.isEmpty, labels.count <= 10,
                  labels.allSatisfy({ !$0.isEmpty && $0.count <= 60 }) else {
                return .failure(.invalid("labels must be 1–10 names"))
            }
            return .success(.press(labels))

        case "/v1/mode":
            guard let name = object["mode"] as? String, let mode = Mode(rawValue: name) else {
                return .failure(.invalid("unknown mode"))
            }
            return .success(.mode(mode))

        default: // type, search
            guard let text = object["text"] as? String,
                  !text.isEmpty, text.count <= maximumTextLength,
                  !text.contains(where: { $0.isNewline || ($0.asciiValue.map { $0 < 0x20 } ?? false) }) else {
                return .failure(.invalid("text must be 1–\(maximumTextLength) printable characters"))
            }
            return .success(request.path == "/v1/type" ? .type(text) : .search(text))
        }
    }

    /// How to type each character: a real key where there is one (so element
    /// labels, which read the key, work), else nil, to be sent as Unicode.
    static func keystrokes(for text: String) -> [(code: UInt16?, modifiers: Modifiers, character: Character)] {
        text.map { character in
            if character == " " {
                return (keyCodes["space"], [], character)
            }
            let lower = String(character).lowercased()
            if character.isASCII, (character.isLetter || character.isNumber), let code = keyCodes[lower] {
                return (code, character.isUppercase ? .shift : [], character)
            }
            return (nil, [], character)
        }
    }
}
