import AppKit
import NotepadSCore

/// Edit › Find › Find and Replace with Regular Expressions… (⇧⌥⌘F).
///
/// One floating panel for the whole app. It always works on the document in the main window
/// (the frontmost document window; the panel itself never becomes the main window), so it
/// follows when the user switches tabs or windows.
///
/// The built-in find bar (⌘F) stays for quick plain searches; this panel adds regular
/// expressions with `$1` groups in the replacement and Replace All as one undo step.
final class FindReplacePanelController: NSWindowController {

    static let shared = FindReplacePanelController()

    private let findField = NSTextField()
    private let replaceField = NSTextField()
    private let regexCheckbox = NSButton(checkboxWithTitle: String(localized: "Regular expression", comment: "Find panel option"),
                                         target: nil, action: nil)
    private let ignoreCaseCheckbox = NSButton(checkboxWithTitle: String(localized: "Ignore case", comment: "Find panel option"),
                                              target: nil, action: nil)
    private let wrapCheckbox = NSButton(checkboxWithTitle: String(localized: "Wrap around", comment: "Find panel option"),
                                        target: nil, action: nil)
    private let selectionOnlyCheckbox = NSButton(checkboxWithTitle: String(localized: "Replace All in selection only",
                                                                          comment: "Find panel option"),
                                                 target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: true)
        panel.title = String(localized: "Find and Replace", comment: "Find panel title")
        // Stays above document windows but hides while another app is active, like Find panels do.
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        // A tool window: not reopened at launch, and never the "main" window the editor
        // commands act on.
        panel.isRestorable = false
        super.init(window: panel)
        buildContent(in: panel)
        panel.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the panel, with the selected text (if short and on one line) as the search text.
    func show(selectedText: String?) {
        if let selectedText, !selectedText.isEmpty, selectedText.count <= 200,
           !selectedText.utf8.contains(where: { $0 == 0x0A || $0 == 0x0D }) {
            findField.stringValue = selectedText
        }
        showWindow(nil)
        window?.makeFirstResponder(findField)
        statusLabel.stringValue = ""
    }

    // MARK: - Actions

    @objc private func findNext(_ sender: Any?) {
        find(forward: true)
    }

    @objc private func findPrevious(_ sender: Any?) {
        find(forward: false)
    }

    /// Replaces the current match (if the selection is one) and moves to the next match.
    @objc private func replace(_ sender: Any?) {
        guard let editor, let search = makeSearch() else { return }
        let text = editor.searchableText
        let selection = editor.currentSelection
        if selection.length > 0, search.matches(in: text, range: selection).first == selection {
            let replacement = search.replacement(for: selection, in: text, template: replaceField.stringValue,
                                                 lineEnding: editor.documentLineEnding)
            editor.replaceText(in: selection, with: replacement,
                               actionName: String(localized: "Replace", comment: "Undo action name"))
        }
        find(forward: true)
    }

    /// Replaces every match in the document (or the selection) as one undo step.
    @objc private func replaceAll(_ sender: Any?) {
        guard let editor, let search = makeSearch() else { return }
        let text = editor.searchableText
        let selection = editor.currentSelection
        let range = selectionOnlyCheckbox.state == .on && selection.length > 0
            ? selection : NSRange(location: 0, length: text.length)
        let result = search.replaceAll(in: text, range: range, template: replaceField.stringValue,
                                       lineEnding: editor.documentLineEnding)
        guard result.count > 0 else {
            report(String(localized: "Not found", comment: "Find panel status"), beep: true)
            return
        }
        editor.replaceText(in: range, with: result.text,
                           actionName: String(localized: "Replace All", comment: "Undo action name"))
        report(String(localized: "Replaced \(result.count) matches", comment: "Find panel status"), beep: false)
    }

    // MARK: - Searching

    /// The editor of the document the user is working in.
    private var editor: EditorViewController? {
        NSApp.mainWindow?.contentViewController as? EditorViewController
    }

    private func makeSearch() -> TextSearch? {
        let options = SearchOptions(isRegularExpression: regexCheckbox.state == .on,
                                    ignoresCase: ignoreCaseCheckbox.state == .on)
        do {
            return try TextSearch(pattern: findField.stringValue, options: options)
        } catch {
            report(error.localizedDescription, beep: true)
            return nil
        }
    }

    private func find(forward: Bool) {
        guard let editor, let search = makeSearch() else { return }
        let text = editor.searchableText
        let selection = editor.currentSelection
        let wraps = wrapCheckbox.state == .on
        let match = forward
            ? search.nextMatch(in: text, from: selection.length > 0 ? NSMaxRange(selection) : selection.location, wraps: wraps)
            : search.previousMatch(in: text, before: selection.location, wraps: wraps)
        guard let match else {
            report(String(localized: "Not found", comment: "Find panel status"), beep: true)
            return
        }
        editor.showMatch(match)
        report("", beep: false)
    }

    private func report(_ message: String, beep: Bool) {
        statusLabel.stringValue = message
        if beep { NSSound.beep() }
    }

    // MARK: - Layout

    private func buildContent(in panel: NSPanel) {
        for field in [findField, replaceField] {
            field.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        }
        findField.placeholderString = String(localized: "Text or regular expression", comment: "Find panel placeholder")
        replaceField.placeholderString = String(localized: "Replacement ($1 for groups, \\n for a line break)",
                                                comment: "Find panel placeholder")
        wrapCheckbox.state = .on
        statusLabel.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "Find:", comment: "Find panel label")), findField],
            [NSTextField(labelWithString: String(localized: "Replace:", comment: "Find panel label")), replaceField],
            [NSGridCell.emptyContentView, optionsRow()],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 10

        let buttons = NSStackView(views: [
            statusLabel,
            button(String(localized: "Replace All", comment: "Find panel button"), #selector(replaceAll(_:))),
            button(String(localized: "Replace", comment: "Find panel button"), #selector(replace(_:))),
            button(String(localized: "Previous", comment: "Find panel button"), #selector(findPrevious(_:))),
            defaultButton(String(localized: "Next", comment: "Find panel button"), #selector(findNext(_:))),
        ])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let content = NSStackView(views: [grid, buttons])
        content.orientation = .vertical
        content.alignment = .trailing
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        content.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = content
        buttons.widthAnchor.constraint(equalTo: grid.widthAnchor).isActive = true
    }

    private func optionsRow() -> NSView {
        let row = NSStackView(views: [regexCheckbox, ignoreCaseCheckbox, wrapCheckbox])
        row.orientation = .horizontal
        row.spacing = 12
        let column = NSStackView(views: [row, selectionOnlyCheckbox])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        return column
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    /// Return triggers Next, like in other Find panels.
    private func defaultButton(_ title: String, _ action: Selector) -> NSButton {
        let button = self.button(title, action)
        button.keyEquivalent = "\r"
        return button
    }
}
