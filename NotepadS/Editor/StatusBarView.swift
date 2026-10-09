import AppKit
import NotepadSCore

protocol StatusBarViewDelegate: AnyObject {
    func statusBar(_ statusBar: StatusBarView, reopenWith encoding: TextEncoding)
    func statusBar(_ statusBar: StatusBarView, convertTo encoding: TextEncoding)
    func statusBar(_ statusBar: StatusBarView, convertLineEndingsTo lineEnding: LineEnding)
    func statusBar(_ statusBar: StatusBarView, didSelect language: SyntaxLanguage)
    func statusBarDidToggleWordWrap(_ statusBar: StatusBarView)
    func statusBarDidToggleOverwriteMode(_ statusBar: StatusBarView)
}

/// Bottom bar: caret position, selection size, document size, word wrap, language, encoding,
/// line endings and insert/overwrite mode. Language, encoding and line endings are pull-down menus; the view only
/// reports choices to its delegate.
final class StatusBarView: NSView {

    static let height: CGFloat = 24

    weak var delegate: StatusBarViewDelegate?

    private let positionLabel = StatusBarView.makeLabel()
    private let selectionLabel = StatusBarView.makeLabel()
    private let documentSizeLabel = StatusBarView.makeLabel()
    private let wrapCheckbox = NSButton(checkboxWithTitle: String(localized: "Wrap", comment: "Status bar checkbox: wrap long lines"),
                                        target: nil, action: nil)
    private let languageButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let encodingButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let lineEndingButton = NSPopUpButton(frame: .zero, pullsDown: true)
    /// "INS" or "OVR"; a click switches the mode.
    private let overwriteModeButton = NSButton(title: "", target: nil, action: nil)

    private var reopenItems: [NSMenuItem] = []
    private var convertItems: [NSMenuItem] = []
    private var lineEndingItems: [NSMenuItem] = []
    private var languageItems: [NSMenuItem] = []
    /// The letter submenus (A, B, C …) of the language menu.
    private var languageGroupItems: [NSMenuItem] = []
    /// What `setLanguage` showed last, to show it again after the menu is rebuilt.
    private var shownLanguage = SyntaxLanguage.plainText
    private var isShownHighlightingOff = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildMenus()
        setUpLayout()
        setLanguage(.plainText, isHighlightingOff: false)
        setOverwriteMode(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// - Parameters:
    ///   - position: the caret's character position in the document, 1-based; `nil` while it
    ///     hasn't been counted yet.
    ///   - lineCount: lines in the document.
    ///   - characterCount: characters in the document; `nil` while it hasn't been counted yet.
    ///   - lineEndingCounts: line breaks of each style in the text, kept live by `LineIndex`.
    ///   - newLineEnding: the document's style for inserted line breaks.
    func update(line: Int, column: Int, position: Int?, selectedCharacters: Int,
                lineCount: Int, characterCount: Int?,
                encoding: TextEncoding, lineEndingCounts: LineEndingCounts,
                newLineEnding: LineEnding, canReopen: Bool) {
        positionLabel.stringValue = position.map { position in
            String(localized: "Ln \(line), Col \(column), Pos \(position.formatted())",
                   comment: "Status bar: caret line, column and character position in the document")
        } ?? String(localized: "Ln \(line), Col \(column)", comment: "Status bar: caret line and column")
        selectionLabel.stringValue = selectedCharacters > 0
            ? String(localized: "\(selectedCharacters) selected", comment: "Status bar: number of selected characters")
            : ""
        // `formatted()` adds the user's digit grouping (1,234 or 1 234).
        let lines = lineCount.formatted()
        documentSizeLabel.stringValue = characterCount.map { count in
            String(localized: "Lines: \(lines)  Characters: \(count.formatted())",
                   comment: "Status bar: number of lines and characters in the document")
        } ?? String(localized: "Lines: \(lines)", comment: "Status bar: number of lines (characters not counted yet)")

        setTitle(encoding.shortName, of: encodingButton)
        for item in reopenItems {
            item.isEnabled = canReopen   // untitled documents have no file to re-read
        }
        for item in convertItems {
            item.state = (item.representedObject as? TextEncoding) == encoding ? .on : .off
        }

        // Show the most frequent style in the text; a text without breaks shows the style
        // that Enter will insert.
        let shownLineEnding = lineEndingCounts.dominant ?? newLineEnding
        let isMixed = lineEndingCounts.isMixed
        setTitle(isMixed ? "\(shownLineEnding.shortName) (mixed)" : shownLineEnding.shortName, of: lineEndingButton)
        lineEndingButton.toolTip = isMixed
            ? String(localized: "This text mixes line-break styles. New line breaks use \(newLineEnding.shortName). Choose “Convert to …” to unify them.",
                     comment: "Status bar tooltip; the style is LF, CRLF or CR")
            : String(localized: "Line endings: \(shownLineEnding.displayName)", comment: "Status bar tooltip")
        for item in lineEndingItems {
            item.state = !isMixed && (item.representedObject as? LineEnding) == shownLineEnding ? .on : .off
        }
    }

    // MARK: - Menu actions

    @objc private func reopenItemChosen(_ sender: NSMenuItem) {
        guard let encoding = sender.representedObject as? TextEncoding else { return }
        delegate?.statusBar(self, reopenWith: encoding)
    }

    @objc private func convertItemChosen(_ sender: NSMenuItem) {
        guard let encoding = sender.representedObject as? TextEncoding else { return }
        delegate?.statusBar(self, convertTo: encoding)
    }

    @objc private func lineEndingItemChosen(_ sender: NSMenuItem) {
        guard let lineEnding = sender.representedObject as? LineEnding else { return }
        delegate?.statusBar(self, convertLineEndingsTo: lineEnding)
    }

    @objc private func wrapCheckboxClicked(_ sender: NSButton) {
        delegate?.statusBarDidToggleWordWrap(self)
    }

    @objc private func overwriteModeButtonClicked(_ sender: NSButton) {
        delegate?.statusBarDidToggleOverwriteMode(self)
    }

    /// Shows "INS" (typing inserts) or "OVR" (typing overwrites).
    func setOverwriteMode(_ isOverwriteMode: Bool) {
        overwriteModeButton.title = isOverwriteMode
            ? String(localized: "OVR", comment: "Status bar: overwrite mode, typing replaces the characters after the caret")
            : String(localized: "INS", comment: "Status bar: insert mode, typing inserts characters")
        overwriteModeButton.toolTip = isOverwriteMode
            ? String(localized: "Overwrite mode: typing replaces the characters after the caret. Click, press Insert or choose Edit › Overwrite Mode to insert instead.",
                     comment: "Status bar tooltip")
            : String(localized: "Insert mode: typing inserts characters. Click, press Insert or choose Edit › Overwrite Mode to overwrite instead.",
                     comment: "Status bar tooltip")
    }

    /// Shows whether long lines wrap.
    func setWrapsLines(_ wrapsLines: Bool) {
        wrapCheckbox.state = wrapsLines ? .on : .off
    }

    @objc private func languageItemChosen(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? SyntaxLanguage else { return }
        delegate?.statusBar(self, didSelect: language)
    }

    /// Shows the document's language; `isHighlightingOff` adds a note when the file is too large.
    func setLanguage(_ language: SyntaxLanguage, isHighlightingOff: Bool) {
        shownLanguage = language
        isShownHighlightingOff = isHighlightingOff
        let title = isHighlightingOff
            ? String(localized: "\(language.displayName) (highlighting off)",
                     comment: "Status bar: language name, highlighting disabled for a very large file")
            : language.displayName
        setTitle(title, of: languageButton)
        languageButton.toolTip = isHighlightingOff
            ? String(localized: "Syntax highlighting is off: the file is very large or has very long lines.",
                     comment: "Status bar tooltip")
            : String(localized: "Syntax highlighting language", comment: "Status bar tooltip")
        for item in languageItems {
            item.state = (item.representedObject as? SyntaxLanguage) == language ? .on : .off
        }
        // A checkmark on the letter, too, so the current language is easy to find.
        for groupItem in languageGroupItems {
            groupItem.state = groupItem.submenu?.items.contains { $0.state == .on } == true ? .on : .off
        }
    }

    // MARK: - Setup

    /// Rebuilds the language menu with the user's own languages (Settings › Languages).
    func setUserLanguages(_ userLanguages: [UserLanguage]) {
        buildLanguageMenu(userLanguages: userLanguages)
        setLanguage(shownLanguage, isHighlightingOff: isShownHighlightingOff)
    }

    /// Plain Text, the user's own languages, then one submenu per letter (A, B, C …), like
    /// Notepad++'s Language menu. Each item carries its `SyntaxLanguage`.
    private func buildLanguageMenu(userLanguages: [UserLanguage]) {
        languageItems = []
        languageGroupItems = []
        let languageMenu = NSMenu()
        languageMenu.autoenablesItems = false
        languageMenu.addItem(NSMenuItem())   // item 0 of a pull-down is its title, not a choice
        languageItems.append(addItem(SyntaxLanguage.plainText.displayName, value: SyntaxLanguage.plainText,
                                     action: #selector(languageItemChosen(_:)), to: languageMenu))
        languageMenu.addItem(.separator())
        if !userLanguages.isEmpty {
            languageMenu.addItem(NSMenuItem.sectionHeader(title: String(localized: "My Languages", comment: "Language menu section: user-defined languages")))
            for language in userLanguages.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                languageItems.append(addItem(language.name, value: SyntaxLanguage.user(language),
                                             action: #selector(languageItemChosen(_:)), to: languageMenu))
            }
            languageMenu.addItem(.separator())
        }
        for group in Language.groupedByInitial {
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for language in group.languages {
                languageItems.append(addItem(language.displayName, value: SyntaxLanguage.builtIn(language),
                                             action: #selector(languageItemChosen(_:)), to: submenu))
            }
            let groupItem = NSMenuItem(title: group.initial, action: nil, keyEquivalent: "")
            groupItem.submenu = submenu
            languageMenu.addItem(groupItem)
            languageGroupItems.append(groupItem)
        }
        configure(languageButton, menu: languageMenu, toolTip: "")
    }

    private func buildMenus() {
        buildLanguageMenu(userLanguages: [])

        let encodingMenu = NSMenu()
        encodingMenu.autoenablesItems = false
        encodingMenu.addItem(NSMenuItem())   // item 0 of a pull-down is its title, not a choice
        encodingMenu.addItem(NSMenuItem.sectionHeader(title: String(localized: "Reopen with Encoding", comment: "Encoding menu section")))
        for encoding in TextEncoding.allCases {
            reopenItems.append(addItem(encoding.displayName, value: encoding,
                                       action: #selector(reopenItemChosen(_:)), to: encodingMenu))
        }
        encodingMenu.addItem(.separator())
        encodingMenu.addItem(NSMenuItem.sectionHeader(title: String(localized: "Convert to Encoding", comment: "Encoding menu section")))
        for encoding in TextEncoding.allCases {
            convertItems.append(addItem(encoding.displayName, value: encoding,
                                        action: #selector(convertItemChosen(_:)), to: encodingMenu))
        }
        configure(encodingButton, menu: encodingMenu, toolTip: String(localized: "Text encoding", comment: "Status bar tooltip"))

        let lineEndingMenu = NSMenu()
        lineEndingMenu.autoenablesItems = false
        lineEndingMenu.addItem(NSMenuItem())
        for lineEnding in LineEnding.allCases {
            lineEndingItems.append(addItem(String(localized: "Convert to \(lineEnding.displayName)", comment: "Line-endings menu item"), value: lineEnding,
                                           action: #selector(lineEndingItemChosen(_:)), to: lineEndingMenu))
        }
        configure(lineEndingButton, menu: lineEndingMenu, toolTip: String(localized: "Line endings", comment: "Status bar tooltip"))

        wrapCheckbox.target = self
        wrapCheckbox.action = #selector(wrapCheckboxClicked(_:))
        wrapCheckbox.controlSize = .small
        wrapCheckbox.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        wrapCheckbox.toolTip = String(localized: "Wrap long lines at the window edge (View › Wrap Lines, ⌃⌘W)",
                                      comment: "Status bar tooltip")
        overwriteModeButton.target = self
        overwriteModeButton.action = #selector(overwriteModeButtonClicked(_:))
        overwriteModeButton.isBordered = false
        overwriteModeButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        positionLabel.toolTip = String(localized: "Pos is the caret’s position in the document, in characters as you see them: an emoji or a CRLF line break counts as one.",
                                       comment: "Status bar tooltip")
        documentSizeLabel.toolTip = String(localized: "Characters are counted as you see them: an emoji or a CRLF line break counts as one.",
                                           comment: "Status bar tooltip")
    }

    private func addItem(_ title: String, value: Any, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = value
        menu.addItem(item)
        return item
    }

    private func configure(_ button: NSPopUpButton, menu: NSMenu, toolTip: String) {
        button.menu = menu
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        button.toolTip = toolTip
    }

    /// A pull-down button always shows the title of its first item.
    private func setTitle(_ title: String, of button: NSPopUpButton) {
        guard button.item(at: 0)?.title != title else { return }
        button.item(at: 0)?.title = title
        button.synchronizeTitleAndSelectedItem()
    }

    private func setUpLayout() {
        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        stack.setViews([positionLabel, selectionLabel], in: .leading)
        stack.setViews([documentSizeLabel, wrapCheckbox, languageButton, encodingButton, lineEndingButton,
                       overwriteModeButton], in: .trailing)

        for subview in [separator, stack] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            stack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private static func makeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byClipping
        return label
    }
}
