import AppKit
import NotepadSCore

/// Edit › ASCII Character Panel: a table of the codes 0–255 (Windows-1252, see
/// `CharacterTable`) with hex, Unicode and HTML codes, like Notepad++'s ASCII Codes Insertion
/// Panel. Double-click a row (or select it and press Insert) to type that character into the
/// document in the main window, at every cursor.
///
/// One floating panel for the whole app, like the Find and Replace panel: it works on the
/// frontmost document window (the panel itself never becomes the main window).
final class CharacterPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {

    static let shared = CharacterPanelController()

    private let entries = CharacterTable.entries
    private let tableView = NSTableView()
    private let insertButton = NSButton(title: String(localized: "Insert", comment: "ASCII panel button"), target: nil, action: nil)

    private enum Column: String, CaseIterable {
        case code, hex, character, unicode, htmlName, htmlNumber

        var title: String {
            switch self {
            case .code: return String(localized: "Value", comment: "ASCII panel column: decimal code")
            case .hex: return String(localized: "Hex", comment: "ASCII panel column: hexadecimal code")
            case .character: return String(localized: "Character", comment: "ASCII panel column")
            case .unicode: return String(localized: "Unicode", comment: "ASCII panel column: code point, e.g. U+20AC")
            case .htmlName: return String(localized: "HTML Name", comment: "ASCII panel column, e.g. &euro;")
            case .htmlNumber: return String(localized: "HTML Number", comment: "ASCII panel column, e.g. &#8364;")
            }
        }

        var width: CGFloat {
            switch self {
            case .code, .hex: return 40
            case .character: return 72
            case .unicode: return 64
            case .htmlName, .htmlNumber: return 84
            }
        }
    }

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: true)
        panel.title = String(localized: "ASCII Characters", comment: "ASCII panel title")
        // Stays above document windows but hides while another app is active.
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isRestorable = false
        super.init(window: panel)
        buildContent(in: panel)
        panel.setFrameAutosaveName("ASCIICharacterPanel")   // remembers position and size
        if !panel.setFrameUsingName("ASCIICharacterPanel") {
            panel.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Inserting

    @objc private func insertSelectedCharacter(_ sender: Any?) {
        // A double-click on the header has row -1.
        let row = sender is NSTableView ? tableView.clickedRow : tableView.selectedRow
        guard entries.indices.contains(row) else { return }
        guard let editor = NSApp.mainWindow?.contentViewController as? EditorViewController else {
            NSSound.beep()   // no document window
            return
        }
        editor.typeText(entries[row].character)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard let identifier = tableColumn?.identifier.rawValue, let column = Column(rawValue: identifier) else { return nil }
        let entry = entries[row]
        switch column {
        case .code: return String(entry.code)
        case .hex: return entry.hex
        // Control and invisible characters show their name, everything else itself.
        case .character: return entry.controlName ?? entry.character
        case .unicode: return entry.unicode
        case .htmlName: return entry.htmlName ?? ""
        case .htmlNumber: return entry.htmlNumber
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        insertButton.isEnabled = tableView.selectedRow >= 0
    }

    // MARK: - Setup

    private func buildContent(in panel: NSPanel) {
        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.isEditable = false
            tableView.addTableColumn(tableColumn)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.doubleAction = #selector(insertSelectedCharacter(_:))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true

        let hint = NSTextField(labelWithString: String(localized: "Double-click a character to insert it. Codes 128–255 are Windows-1252.",
                                                       comment: "ASCII panel hint"))
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        insertButton.target = self
        insertButton.action = #selector(insertSelectedCharacter(_:))
        insertButton.isEnabled = false
        insertButton.keyEquivalent = "\r"   // Return inserts the selected row

        let content = NSView()
        for view in [scrollView, hint, insertButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            insertButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            insertButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            insertButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            hint.centerYAnchor.constraint(equalTo: insertButton.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: insertButton.leadingAnchor, constant: -8),
        ])
        panel.contentView = content
        panel.contentMinSize = NSSize(width: 360, height: 240)
    }
}
