import Foundation

/// The sections of the palette, in display order.
///
/// Mirrors pagecast's Site / Page / Tabs grouping, plus the menu bar, which a
/// browser extension cannot see.
enum PaletteGroup: CaseIterable {
    case commands
    case controls
    case tabs
    case menu

    var title: String {
        switch self {
        case .commands: return "Quick actions"
        case .controls: return "Window"
        case .tabs: return "Tabs"
        case .menu: return "Menu"
        }
    }

    /// Rows shown for this group when nothing is typed, so every section stays
    /// in view. A scope prefix lifts the cap.
    var emptyQueryLimit: Int {
        switch self {
        case .commands: return 10
        case .controls: return 12
        case .tabs: return 8
        case .menu: return 8
        }
    }

    /// Nudges ranking between groups: a command or tab that matches as well as
    /// a menu item is usually the one meant.
    var bias: Double {
        switch self {
        case .commands: return 1.5
        case .tabs: return 0.5
        case .controls: return 0
        case .menu: return -0.5
        }
    }

    /// Single-character scope prefixes, pagecast style (`>` site/commands,
    /// `#` page, `@` tabs), plus `/` for the menu bar.
    static let symbolScopes: [Character: PaletteGroup] = [
        ">": .commands,
        "#": .controls,
        "@": .tabs,
        "/": .menu,
    ]

    /// The same scopes as words, so `tab: azure pull` reads naturally.
    static let wordScopes: [String: PaletteGroup] = [
        "cmd": .commands, "do": .commands, "site": .commands,
        "page": .controls, "win": .controls, "window": .controls,
        "tab": .tabs, "tabs": .tabs,
        "menu": .menu,
    ]
}

/// Grouping, scoping and ranking for the palette, independent of AppKit and of
/// the accessibility tree so it can be unit-tested.
enum PaletteSearch {

    /// A run of rows. `group` is nil for a ranked result list, which is drawn
    /// without headers.
    struct Section<Item> {
        let group: PaletteGroup?
        let rows: [(item: Item, match: Fuzzy.Match)]
    }

    static let maximumResults = 200

    /// Splits a leading scope (`@ azure`, `tab: azure`) from the search text.
    static func parse(_ raw: String) -> (scope: PaletteGroup?, text: String) {
        let trimmed = raw.drop(while: { $0.isWhitespace })

        if let first = trimmed.first, let scope = PaletteGroup.symbolScopes[first] {
            return (scope, String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        }

        if let colon = trimmed.firstIndex(of: ":"),
           let scope = PaletteGroup.wordScopes[trimmed[..<colon].lowercased()] {
            return (scope, String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
        }

        return (nil, raw.trimmingCharacters(in: .whitespaces))
    }

    /// With no text: one section per group, in source order, capped per group
    /// (uncapped inside a scope). With text: a single headerless section,
    /// ranked across the whole pool with a small per-group bias.
    static func filter<Item>(
        _ items: [Item],
        query: String,
        group: (Item) -> PaletteGroup,
        text: (Item) -> String
    ) -> [Section<Item>] {

        let (scope, searchText) = parse(query)
        let pool = scope.map { scope in items.filter { group($0) == scope } } ?? items

        if Fuzzy.tokens(of: searchText).isEmpty {
            let groups = scope.map { [$0] } ?? PaletteGroup.allCases
            let sections = groups.compactMap { current -> Section<Item>? in
                let rows = pool
                    .filter { group($0) == current }
                    .prefix(scope == nil ? current.emptyQueryLimit : maximumResults)
                    .map { (item: $0, match: Fuzzy.Match(score: 0, indices: [])) }
                return rows.isEmpty ? nil : Section(group: current, rows: Array(rows))
            }
            return sections
        }

        typealias Row = (item: Item, match: Fuzzy.Match)

        let biased: [Row] = Fuzzy.rank(pool, query: searchText, text: text).map { row in
            let score = row.match.score + group(row.element).bias
            return (item: row.element, match: Fuzzy.Match(score: score, indices: row.match.indices))
        }

        // Stable re-sort: equal scores keep the matcher's tie-break order.
        let order = biased.indices.sorted { lhs, rhs in
            let left = biased[lhs].match.score
            let right = biased[rhs].match.score
            return left != right ? left > right : lhs < rhs
        }

        let ranked: [Row] = order.prefix(maximumResults).map { biased[$0] }

        return ranked.isEmpty ? [] : [Section(group: nil, rows: Array(ranked))]
    }
}
