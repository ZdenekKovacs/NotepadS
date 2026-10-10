import AppKit
import NotepadSCore

/// View › Show Function List: the document's functions, types and headings in a sidebar at the
/// right edge of the window, like Notepad++'s Function List. Click one to jump to it; the
/// search field filters the list. The row of the function the caret is in is selected.
///
/// The view only shows what it is given (`setSymbols`) and reports clicks (`onSelect`);
/// EditorViewController finds the symbols (`FunctionList` in NotepadSCore).
final class FunctionListView: NSView, NSTableViewDataSource, NSTableViewDelegate {

    static let width: CGFloat = 220

    /// Called when the user clicks a symbol.
    var onSelect: ((CodeSymbol) -> Void)?

    private var allSymbols: [CodeSymbol] = []
    /// `allSymbols` filtered by the search field.
    private var shownSymbols: [CodeSymbol] = []
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Content

    /// Shows new symbols, keeping the search text. `isSupported` is false for languages without
    /// patterns (plain text, JSON …), which shows a hint instead of an empty list.
    func setSymbols(_ symbols: [CodeSymbol], isSupported: Bool) {
        allSymbols = symbols
        applyFilter()
        emptyLabel.stringValue = isSupported
            ? String(localized: "No functions found", comment: "Function list: empty")
            : String(localized: "No function list for this language", comment: "Function list: language without patterns")
    }

    /// Selects the last symbol at or before `line` (the one the caret is in), without jumping.
    func showCaret(atLine line: Int) {
        guard let row = shownSymbols.lastIndex(where: { $0.line <= line }) else {
            tableView.deselectAll(nil)
            return
        }
        guard tableView.selectedRow != row else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)   // sends no action
        tableView.scrollRowToVisible(row)
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        shownSymbols = query.isEmpty
            ? allSymbols
            : allSymbols.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        tableView.reloadData()
        emptyLabel.isHidden = !shownSymbols.isEmpty
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        applyFilter()
    }

    @objc private func rowClicked(_ sender: NSTableView) {
        let row = tableView.clickedRow
        guard shownSymbols.indices.contains(row) else { return }
        onSelect?(shownSymbols[row])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        shownSymbols.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let symbol = shownSymbols[row]
        let identifier = NSUserInterfaceItemIdentifier("SymbolCell")
        // Rows are reused while scrolling; make one only when there is none to reuse.
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SymbolCellView ?? SymbolCellView()
        cell.identifier = identifier
        // While filtering, nesting means little: show every match at the left edge.
        cell.show(symbol, depth: searchField.stringValue.isEmpty ? symbol.depth : 0)
        return cell
    }

    // MARK: - Setup

    private func setUp() {
        searchField.placeholderString = String(localized: "Filter", comment: "Function list: search field")
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Symbol"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 20
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyLabel.alignment = .center
        emptyLabel.lineBreakMode = .byWordWrapping

        let separator = NSBox()
        separator.boxType = .separator

        for view in [separator, searchField, scrollView, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            searchField.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 20),
            emptyLabel.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }
}

/// One row: an icon for the kind of symbol, then its name, indented by its depth.
private final class SymbolCellView: NSTableCellView {

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        imageView = icon
        textField = label
        label.lineBreakMode = .byTruncatingTail
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        for view in [icon, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        leadingConstraint = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)
        NSLayoutConstraint.activate([
            leadingConstraint,
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ symbol: CodeSymbol, depth: Int) {
        leadingConstraint.constant = 2 + CGFloat(min(depth, 6)) * 12
        label.stringValue = symbol.name
        toolTip = String(localized: "\(symbol.name) — line \(symbol.line + 1)", comment: "Function list tooltip: name and line")
        let (symbolName, scope): (String, SyntaxScope) = switch symbol.kind {
        case .function: ("f.cursive", .function)
        case .type: ("cube", .keyword)
        case .heading: ("number", .heading)
        case .section: ("square.grid.2x2", .constant)
        }
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        icon.contentTintColor = SyntaxTheme.color(for: scope)   // the kind's color from the syntax theme
    }
}
