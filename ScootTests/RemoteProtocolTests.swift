import XCTest

final class RemoteProtocolTests: XCTestCase {

    private let me: Set<String> = ["me@example.com"]

    private func request(
        _ method: String = "POST",
        _ path: String = "/v1/key",
        headers: [String: String] = [:],
        body: String = ""
    ) -> Remote.Request {
        var all = ["tailscale-user-login": "me@example.com", "content-type": "application/json", "host": "mac.tail.ts.net"]
        all.merge(headers) { $1 }
        return Remote.Request(method: method, path: path, headers: all.filter { !$0.value.isEmpty }, body: Data(body.utf8))
    }

    // MARK: - Parsing

    func testParsesACompleteRequest() {
        let raw = "POST /v1/key?x=1 HTTP/1.1\r\nHost: mac\r\nContent-Type: application/json\r\nContent-Length: 13\r\n\r\n{\"key\":\"up\"}x"
        guard case let .complete(request) = Remote.parse(Data(raw.utf8)) else {
            return XCTFail("expected a complete request")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/key")
        XCTAssertEqual(request.headers["content-type"], "application/json")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "{\"key\":\"up\"}x")
    }

    func testWaitsForTheBody() {
        let raw = "POST /v1/key HTTP/1.1\r\nContent-Length: 20\r\n\r\n{\"key\""
        XCTAssertEqual(Remote.parse(Data(raw.utf8)), .incomplete)
        XCTAssertEqual(Remote.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)), .incomplete)
    }

    func testRejectsGarbageAndOversizedRequests() {
        XCTAssertEqual(Remote.parse(Data("hello\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(Remote.parse(Data("GET / HTTP/1.1\r\nno colon\r\n\r\n".utf8)), .invalid)
        XCTAssertEqual(Remote.parse(Data(repeating: 65, count: Remote.maximumRequestSize + 1)), .invalid)
    }

    // MARK: - Authorization

    func testAllowsListedTailnetUser() {
        XCTAssertEqual(Remote.authorize(request(), allowedLogins: me), .allowed(login: "me@example.com"))
    }

    func testRefusesRequestsWithoutTailnetIdentity() {
        let local = request(headers: ["tailscale-user-login": ""])
        XCTAssertEqual(Remote.authorize(local, allowedLogins: me), .forbidden("not a tailnet request"))
    }

    func testRefusesOtherTailnetUsers() {
        let other = request(headers: ["tailscale-user-login": "guest@example.com"])
        XCTAssertNotEqual(Remote.authorize(other, allowedLogins: me), .allowed(login: "guest@example.com"))
    }

    func testRefusesNonJSONCommands() {
        let form = request(headers: ["content-type": "text/plain"])
        XCTAssertEqual(Remote.authorize(form, allowedLogins: me), .forbidden("commands must be JSON"))
    }

    func testRefusesCrossOriginCommands() {
        let evil = request(headers: ["origin": "https://evil.example"])
        XCTAssertEqual(Remote.authorize(evil, allowedLogins: me), .forbidden("cross-origin request"))

        let own = request(headers: ["origin": "https://mac.tail.ts.net"])
        XCTAssertEqual(Remote.authorize(own, allowedLogins: me), .allowed(login: "me@example.com"))

        let forwarded = request(headers: ["host": "127.0.0.1:8765", "x-forwarded-host": "mac.tail.ts.net", "origin": "https://mac.tail.ts.net"])
        XCTAssertEqual(Remote.authorize(forwarded, allowedLogins: me), .allowed(login: "me@example.com"))
    }

    func testPageNeedsIdentityButNotJSON() {
        let page = request("GET", "/", headers: ["content-type": ""])
        XCTAssertEqual(Remote.authorize(page, allowedLogins: me), .allowed(login: "me@example.com"))
    }

    // MARK: - Commands

    func testDecodesKeysWithModifiers() {
        let command = Remote.decode(request(body: #"{"key":"Up","modifiers":["shift","command"]}"#))
        XCTAssertEqual(command, .success(.key(code: 126, modifiers: [.shift, .command])))
    }

    func testRefusesKeysOutsideTheList() {
        XCTAssertEqual(Remote.decode(request(body: #"{"key":"f12"}"#)), .failure(.invalid("unknown key")))
        XCTAssertEqual(
            Remote.decode(request(body: #"{"key":"up","modifiers":["hyper"]}"#)),
            .failure(.invalid("unknown modifier hyper"))
        )
    }

    func testDecodesModesTextAndSearch() {
        XCTAssertEqual(Remote.decode(request("POST", "/v1/mode", body: #"{"mode":"palette"}"#)), .success(.mode(.palette)))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/type", body: #"{"text":"aa"}"#)), .success(.type("aa")))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/search", body: #"{"text":"skip intro"}"#)), .success(.search("skip intro")))
    }

    func testDecodesScrollAndFocus() {
        XCTAssertEqual(Remote.decode(request("POST", "/v1/scroll", body: #"{"direction":"down"}"#)), .success(.scroll(.down, all: false)))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/scroll", body: #"{"direction":"up","all":true}"#)), .success(.scroll(.up, all: true)))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/scroll", body: #"{"direction":"sideways"}"#)), .failure(.invalid("unknown direction")))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/focus", body: "{}")), .success(.focusTV))
    }

    func testDecodesShortcuts() {
        XCTAssertEqual(Remote.decode(request("POST", "/v1/locate", body: "{}")), .success(.locatePointer))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/sitesearch", body: #"{"labels":["Search"]}"#)), .success(.siteSearch(["Search"])))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/home", body: "{}")), .success(.siteHome))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/press", body: #"{"labels":["Search","Rechercher"]}"#)), .success(.press(["Search", "Rechercher"])))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/press", body: #"{"labels":[]}"#)), .failure(.invalid("labels must be 1–10 names")))
    }

    func testRefusesUnprintableOrLongText() {
        XCTAssertNotEqual(Remote.decode(request("POST", "/v1/type", body: #"{"text":"a\nb"}"#)), .success(.type("a\nb")))
        let long = String(repeating: "a", count: Remote.maximumTextLength + 1)
        XCTAssertNotEqual(Remote.decode(request("POST", "/v1/type", body: "{\"text\":\"\(long)\"}")), .success(.type(long)))
        XCTAssertEqual(Remote.decode(request("POST", "/v1/nope", body: "{}")), .failure(.notFound))
    }

    func testTypesLettersWithRealKeysAndTheRestAsUnicode() {
        let strokes = Remote.keystrokes(for: "aB 1é")
        XCTAssertEqual(strokes.map(\.code), [0, 11, 49, 18, nil])
        XCTAssertEqual(strokes.map(\.modifiers), [[], .shift, [], [], []])
    }
}
