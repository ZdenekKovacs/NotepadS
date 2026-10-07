import AppKit
import NotepadSCore

/// Shown at the bottom of the Save panel: a pull-down listing the languages NotepadS
/// highlights, with their file extensions. Choosing one puts its usual extension on the file
/// name; typing any other extension still works (the panel accepts every extension).
///
/// A pull-down rather than a pop-up: a pop-up would show a selected language, which would be
/// wrong as soon as the user types another extension. (The Save panel doesn't tell the app
/// about typing, so the menu can't follow the name field.)
final class SaveExtensionAccessoryView: NSView {

    private weak var savePanel: NSSavePanel?
    private let pullDown = NSPopUpButton(frame: .zero, pullsDown: true)

    init(savePanel: NSSavePanel) {
        self.savePanel = savePanel
        super.init(frame: .zero)
        buildMenu()
        setUpLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildMenu() {
        let menu = NSMenu()
        // Item 0 of a pull-down is its title, not a choice.
        menu.addItem(withTitle: String(localized: "Set Extension", comment: "Save panel: pull-down title; lists languages with syntax highlighting"),
                     action: nil, keyEquivalent: "")
        // Plain text first, then the languages alphabetically, as people look for them by name.
        let languages = [Language.plainText] + Language.allCases
            .filter { $0 != .plainText }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        for language in languages {
            let extensions = language.fileExtensions.map { ".\($0)" }.joined(separator: " ")
            let item = NSMenuItem(title: String(localized: "\(language.displayName)   \(extensions)",
                                                comment: "Save panel: language name, then its file extensions"),
                                  action: #selector(languageChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            menu.addItem(item)
        }
        pullDown.menu = menu
        pullDown.toolTip = String(localized: "Files with these extensions get syntax highlighting. You can also type any other extension.",
                                  comment: "Save panel tooltip")
    }

    private func setUpLayout() {
        let label = NSTextField(labelWithString: String(localized: "Syntax highlighting:", comment: "Save panel: label before the extension pull-down"))
        let hint = NSTextField(labelWithString: String(localized: "Or type your own extension.", comment: "Save panel hint"))
        hint.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [label, pullDown, hint])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        ])
        // The Save panel sizes its accessory view from the view's frame.
        setFrameSize(fittingSize)
    }

    @objc private func languageChosen(_ sender: NSMenuItem) {
        guard let savePanel,
              let rawValue = sender.representedObject as? String,
              let language = Language(rawValue: rawValue),
              let newExtension = language.fileExtensions.first else { return }
        savePanel.nameFieldStringValue = Language.fileName(savePanel.nameFieldStringValue, withExtension: newExtension)
    }
}
