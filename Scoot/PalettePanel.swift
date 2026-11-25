import AppKit
import OSLog

/// A borderless panel that can still take keyboard focus.
///
/// It is non-activating, like Spotlight's: it takes the keyboard without
/// making Pressto the active app, so showing it does not depend on
/// `NSApp.activate`, which macOS may refuse under cooperative activation.
private final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The palette UI: a search field over a ranked list, Raycast/pagecast style.
///
/// Keys: type to filter, ↑/↓ (or ⌃P/⌃N) to move, ↵ to press, ⎋ to dismiss.
@MainActor
final class PaletteController: NSObject {

    /// Called with the chosen item after the panel has closed.
    var onChoose: ((PaletteItem) -> Void)?

    /// Called when the palette is dismissed without a choice.
    var onCancel: (() -> Void)?

    /// A line of the list: a section header (empty query only) or an item.
    private enum Row {
        case header(String)
        case item(PaletteItem, Fuzzy.Match)

        var item: PaletteItem? {
            if case let .item(item, _) = self {
                return item
            }
            return nil
        }
    }

    private var items = [PaletteItem]()
    private var rows = [Row]()

    private lazy var panel: PalettePanel = makePanel()

    /// Bumped on every `show` and `close`, so a late visibility check can tell
    /// whether it still concerns the palette the user asked for.
    private var showGeneration = 0
    private let searchField = NSTextField()
    private let tableView = NSTableView()

    var isVisible: Bool {
        panel.isVisible
    }

    // MARK: - Showing

    /// Shows the palette centred horizontally over `windowFrame` (Cocoa screen
    /// coordinates), a little below its top edge, clamped to that window's
    /// display. Without a window frame, falls back to the main screen.
    func show(items: [PaletteItem], over windowFrame: CGRect?) {
        self.items = items
        searchField.stringValue = ""
        filter()

        let screen = windowFrame.flatMap { frame in
            NSScreen.screens.max {
                $0.frame.intersection(frame).area < $1.frame.intersection(frame).area
            }
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let anchor = windowFrame ?? screen.visibleFrame
        let size = panel.frame.size
        let visible = screen.visibleFrame

        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.maxY - size.height - min(anchor.height * 0.15, 120)
        )
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)

        panel.setFrameOrigin(origin)
        present()

        showGeneration += 1
        verifyVisible(generation: showGeneration, rebuilt: false)
    }

    private func present() {
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(searchField)
    }

    /// A moment after showing, checks that the panel really reached the screen.
    /// If it did not, logs a fault and rebuilds the panel once: a palette that
    /// silently never appears is worse than a glitch that leaves a trace.
    private func verifyVisible(generation: Int, rebuilt: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.showGeneration else { return }
                if self.panel.isVisible && self.panel.isKeyWindow {
                    return
                }
                OSLog.main.fault("Palette: panel not on screen after show (visible: \(self.panel.isVisible, privacy: .public), key: \(self.panel.isKeyWindow, privacy: .public), rebuilt: \(rebuilt, privacy: .public))")
                guard !rebuilt else { return }
                let frame = self.panel.frame
                self.panel.delegate = nil
                self.panel.orderOut(nil)
                self.panel = self.makePanel()
                self.panel.setFrame(frame, display: false)
                self.present()
                self.verifyVisible(generation: generation, rebuilt: true)
            }
        }
    }

    /// Replaces the items while the palette is open (the window scan landing
    /// after the panel was shown), keeping what the user already typed.
    func update(items: [PaletteItem]) {
        self.items = items
        filter()
    }

    func close() {
        showGeneration += 1
        closing = true
        panel.orderOut(nil)
        closing = false
    }

    /// Set while `close()` orders the panel out, so losing key on the way is
    /// not mistaken for the user clicking away.
    private var closing = false

    // MARK: - Filtering

    private func filter() {
        let sections = PaletteSearch.filter(
            items,
            query: searchField.stringValue,
            group: \.group,
            text: \.searchText
        )

        rows = sections.flatMap { section -> [Row] in
            let items = section.rows.map { Row.item($0.item, $0.match) }
            guard let group = section.group else {
                return items
            }
            return [.header(group.title)] + items
        }

        tableView.reloadData()
        select(row: 0, direction: 1)
    }

    /// Selects `row`, or the nearest item row in `direction` when `row` is a
    /// header. Clamps at both ends.
    private func select(row: Int, direction: Int) {
        var row = min(max(row, 0), rows.count - 1)
        while rows.indices.contains(row), rows[row].item == nil {
            row += direction
        }
        guard rows.indices.contains(row) else {
            // Ran past the end looking for an item: try the other way once.
            if direction > 0, let last = rows.lastIndex(where: { $0.item != nil }) {
                select(row: last, direction: -1)
            } else if direction < 0, let first = rows.firstIndex(where: { $0.item != nil }) {
                select(row: first, direction: 1)
            }
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func chooseSelected() {
        let row = tableView.selectedRow
        guard rows.indices.contains(row), let item = rows[row].item else {
            return
        }
        close()
        onChoose?(item)
    }

    private func cancel() {
        close()
        onCancel?()
    }

    // MARK: - Layout

    private func makePanel() -> PalettePanel {

        let panel = PalettePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
            // Non-activating, like Spotlight: the panel takes the keyboard
            // without activating Pressto. Activating it would make macOS leave
            // a full-screen Space (Safari playing a video) for a Space where
            // Pressto has a window — the desktop — and the palette would flash
            // there and vanish.
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Pressto is never activated, so it never deactivates either: close
        // when the panel loses the keyboard instead (a click elsewhere).
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        searchField.placeholderString = "Search…    > actions   # window   @ tabs   / menu"
        searchField.font = .systemFont(ofSize: 20)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self

        let column = NSTableColumn(identifier: .init("item"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 30
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let separator = NSBox()
        separator.boxType = .separator

        for view in [searchField, separator, scrollView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: background.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
        ])

        panel.contentView = background
        return panel
    }

    @objc private func rowDoubleClicked() {
        chooseSelected()
    }

    private static func glyph(for item: PaletteItem) -> String {
        switch item.kind {
        case .menuItem: return "≡"
        case .command: return "⚡︎"
        case .tab: return "▭"
        case .element: break
        }
        switch item.role {
        case "AXLink": return "↗"
        case "AXTextField", "AXTextArea", "AXComboBox": return "⌨"
        case "AXCheckBox": return "☑"
        case "AXPopUpButton", "AXMenuButton": return "▾"
        default: return "●"
        }
    }

    /// The label with matched characters in bold, followed by the dimmed context.
    private static func attributedTitle(for item: PaletteItem, match: Fuzzy.Match) -> NSAttributedString {

        let text = NSMutableAttributedString(
            string: item.label,
            attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
        )

        let labelLength = Array(item.label).count
        for range in match.ranges where range.lowerBound < labelLength {
            // Match offsets count Characters; NSAttributedString counts UTF-16
            // units, so go through String indices (labels may hold emoji).
            let start = item.label.index(item.label.startIndex, offsetBy: range.lowerBound)
            let end = item.label.index(item.label.startIndex, offsetBy: min(range.upperBound, labelLength))
            text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(start..<end, in: item.label))
        }

        text.append(NSAttributedString(
            string: "   \(item.context)",
            attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        ))

        return text
    }
}

extension PaletteController {

    /// The detail line, dimmed, with matched characters brightened. Match
    /// offsets index `searchText` (label, context, detail joined by spaces).
    fileprivate static func attributedDetail(_ detail: String, for item: PaletteItem, match: Fuzzy.Match) -> NSAttributedString {

        let font = NSFont.systemFont(ofSize: 11.5)
        let text = NSMutableAttributedString(
            string: detail,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        )

        let offset = item.label.count + 1 + item.context.count + 1
        let length = detail.count

        for range in match.ranges {
            let lower = range.lowerBound - offset
            let upper = min(range.upperBound - offset, length)
            guard lower >= 0, lower < upper else {
                continue
            }
            let start = detail.index(detail.startIndex, offsetBy: lower)
            let end = detail.index(detail.startIndex, offsetBy: upper)
            text.addAttributes(
                [.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold)],
                range: NSRange(start..<end, in: detail)
            )
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))

        return text
    }
}

/// A row: one title line, plus an optional dimmed detail line (a tab's URL).
private final class PaletteCellView: NSTableCellView {

    let detailField = PaletteCellView.makeLabel()

    override init(frame: NSRect) {
        super.init(frame: frame)

        let title = PaletteCellView.makeLabel()
        textField = title

        let stack = NSStackView(views: [title, detailField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            // Detail lines start under the label, past the glyph column.
            detailField.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 22),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private static func makeLabel() -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}

// MARK: - Search field

extension PaletteController: NSWindowDelegate {

    func windowDidResignKey(_ notification: Notification) {
        guard !closing, panel.isVisible else {
            return
        }
        cancel()
    }
}

extension PaletteController: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        filter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            select(row: tableView.selectedRow - 1, direction: -1)
        case #selector(NSResponder.moveDown(_:)):
            select(row: tableView.selectedRow + 1, direction: 1)
        case #selector(NSResponder.insertNewline(_:)):
            chooseSelected()
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
        default:
            return false
        }
        return true
    }
}

// MARK: - Results list

extension PaletteController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        rows[row].item != nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = rows[row].item else {
            return 24
        }
        return item.detail == nil ? 30 : 44
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        let identifier = NSUserInterfaceItemIdentifier("PaletteCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PaletteCellView ?? {
            let cell = PaletteCellView()
            cell.identifier = identifier
            return cell
        }()

        cell.detailField.isHidden = true

        guard case let .item(item, match) = rows[row] else {
            if case let .header(title) = rows[row] {
                cell.textField?.attributedStringValue = NSAttributedString(
                    string: title.uppercased(),
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .kern: 0.6,
                    ]
                )
            }
            return cell
        }

        let title = NSMutableAttributedString(
            string: "\(Self.glyph(for: item))  ",
            attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.tertiaryLabelColor]
        )
        title.append(Self.attributedTitle(for: item, match: match))

        // Attributed strings carry their own line breaking, which overrides
        // the label's: without this, a long tab title wraps onto the next row.
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))

        cell.textField?.attributedStringValue = title

        if let detail = item.detail {
            cell.detailField.attributedStringValue = Self.attributedDetail(detail, for: item, match: match)
            cell.detailField.isHidden = false
        }

        return cell
    }
}
