import AppKit
import NotepadSCore

protocol StatusBarViewDelegate: AnyObject {
    func statusBar(_ statusBar: StatusBarView, reopenWith encoding: TextEncoding)
    func statusBar(_ statusBar: StatusBarView, convertTo encoding: TextEncoding)
    func statusBar(_ statusBar: StatusBarView, didSelect lineEnding: LineEnding)
}

/// Bottom bar: caret position, selection size, language, encoding and line endings.
/// Encoding and line endings are pull-down menus; the view only reports choices to its delegate.
final class StatusBarView: NSView {

    static let height: CGFloat = 24

    weak var delegate: StatusBarViewDelegate?

    private let positionLabel = StatusBarView.makeLabel()
    private let selectionLabel = StatusBarView.makeLabel()
    private let languageLabel = StatusBarView.makeLabel()
    private let encodingButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let lineEndingButton = NSPopUpButton(frame: .zero, pullsDown: true)

    private var reopenItems: [NSMenuItem] = []
    private var convertItems: [NSMenuItem] = []
    private var lineEndingItems: [NSMenuItem] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildMenus()
        setUpLayout()
        languageLabel.stringValue = "Plain Text"   // syntax languages arrive in v0.2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(line: Int, column: Int, selectedCharacters: Int,
                encoding: TextEncoding, lineEnding: LineEnding,
                hadMixedLineEndings: Bool, canReopen: Bool) {
        positionLabel.stringValue = "Ln \(line), Col \(column)"
        selectionLabel.stringValue = selectedCharacters > 0 ? "\(selectedCharacters) selected" : ""

        setTitle(encoding.shortName, of: encodingButton)
        for item in reopenItems {
            item.isEnabled = canReopen   // untitled documents have no file to re-read
        }
        for item in convertItems {
            item.state = (item.representedObject as? TextEncoding) == encoding ? .on : .off
        }

        setTitle(hadMixedLineEndings ? "\(lineEnding.shortName) (mixed)" : lineEnding.shortName, of: lineEndingButton)
        lineEndingButton.toolTip = hadMixedLineEndings
            ? "The file mixed line endings when it was opened. Saving writes \(lineEnding.shortName) everywhere."
            : "Line endings"
        for item in lineEndingItems {
            item.state = (item.representedObject as? LineEnding) == lineEnding ? .on : .off
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
        delegate?.statusBar(self, didSelect: lineEnding)
    }

    // MARK: - Setup

    private func buildMenus() {
        let encodingMenu = NSMenu()
        encodingMenu.autoenablesItems = false
        encodingMenu.addItem(NSMenuItem())   // item 0 of a pull-down is its title, not a choice
        encodingMenu.addItem(NSMenuItem.sectionHeader(title: "Reopen with Encoding"))
        for encoding in TextEncoding.allCases {
            reopenItems.append(addItem(encoding.displayName, value: encoding,
                                       action: #selector(reopenItemChosen(_:)), to: encodingMenu))
        }
        encodingMenu.addItem(.separator())
        encodingMenu.addItem(NSMenuItem.sectionHeader(title: "Convert to Encoding"))
        for encoding in TextEncoding.allCases {
            convertItems.append(addItem(encoding.displayName, value: encoding,
                                        action: #selector(convertItemChosen(_:)), to: encodingMenu))
        }
        configure(encodingButton, menu: encodingMenu, toolTip: "Text encoding")

        let lineEndingMenu = NSMenu()
        lineEndingMenu.autoenablesItems = false
        lineEndingMenu.addItem(NSMenuItem())
        for lineEnding in LineEnding.allCases {
            lineEndingItems.append(addItem(lineEnding.displayName, value: lineEnding,
                                           action: #selector(lineEndingItemChosen(_:)), to: lineEndingMenu))
        }
        configure(lineEndingButton, menu: lineEndingMenu, toolTip: "Line endings")
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
        stack.setViews([languageLabel, encodingButton, lineEndingButton], in: .trailing)

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
