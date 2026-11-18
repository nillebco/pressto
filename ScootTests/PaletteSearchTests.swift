import XCTest

class PaletteSearchTests: XCTestCase {

    private struct Item: Equatable {
        let label: String
        let group: PaletteGroup
    }

    private func filter(_ items: [Item], _ query: String) -> [PaletteSearch.Section<Item>] {
        PaletteSearch.filter(items, query: query, group: \.group, text: \.label)
    }

    private let sample = [
        Item(label: "Copy page address", group: .commands),
        Item(label: "Back", group: .controls),
        Item(label: "Reload", group: .controls),
        Item(label: "Azure DevOps pull requests", group: .tabs),
        Item(label: "Inbox", group: .tabs),
        Item(label: "Copy", group: .menu),
    ]

    // MARK: - Parsing

    func testSymbolScopes() {
        XCTAssertEqual(PaletteSearch.parse("@ azure").scope, .tabs)
        XCTAssertEqual(PaletteSearch.parse("@ azure").text, "azure")
        XCTAssertEqual(PaletteSearch.parse(">copy").scope, .commands)
        XCTAssertEqual(PaletteSearch.parse("#").scope, .controls)
        XCTAssertEqual(PaletteSearch.parse("  / export").scope, .menu)
    }

    func testWordScopes() {
        XCTAssertEqual(PaletteSearch.parse("tab: azure pull").scope, .tabs)
        XCTAssertEqual(PaletteSearch.parse("tab: azure pull").text, "azure pull")
        XCTAssertEqual(PaletteSearch.parse("Menu:export").scope, .menu)
    }

    func testUnknownWordBeforeColonIsSearchText() {
        let parsed = PaletteSearch.parse("http://example")
        XCTAssertNil(parsed.scope)
        XCTAssertEqual(parsed.text, "http://example")
    }

    // MARK: - Empty query

    func testEmptyQueryGroupsInDisplayOrderWithHeaders() {
        let sections = filter(sample, "")
        XCTAssertEqual(sections.map(\.group), [.commands, .controls, .tabs, .menu])
        XCTAssertEqual(sections[1].rows.map(\.item.label), ["Back", "Reload"])
    }

    func testEmptyQueryCapsEachGroup() {
        let many = (0..<50).map { Item(label: "Control \($0)", group: .controls) }
        let sections = filter(many, "")
        XCTAssertEqual(sections.first?.rows.count, PaletteGroup.controls.emptyQueryLimit)
    }

    func testScopeAloneListsTheWholeGroup() {
        let many = (0..<50).map { Item(label: "Control \($0)", group: .controls) }
        let sections = filter(many, "#")
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.rows.count, 50)
    }

    // MARK: - Ranked

    func testTypedQueryIsOneHeaderlessRankedSection() {
        let sections = filter(sample, "copy")
        XCTAssertEqual(sections.count, 1)
        XCTAssertNil(sections.first?.group)
        XCTAssertEqual(Set(sections.first?.rows.map(\.item.label) ?? []), ["Copy page address", "Copy"])
    }

    func testScopeRestrictsRankedResults() {
        let rows = filter(sample, "@ in").first?.rows.map(\.item.label)
        XCTAssertEqual(rows, ["Inbox"])
    }

    func testCommandBiasBeatsMenuItemOnEqualMatch() {
        let items = [
            Item(label: "Export", group: .menu),
            Item(label: "Export", group: .commands),
        ]
        XCTAssertEqual(filter(items, "exp").first?.rows.first?.item.group, .commands)
    }
}
