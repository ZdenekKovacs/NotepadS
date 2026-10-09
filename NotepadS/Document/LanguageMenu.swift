import AppKit
import NotepadSCore

/// The language list of the Save and Open panels: Plain Text, the user's own languages, then one
/// submenu per letter (A, B, C …, like the status bar's language menu). Each item shows the
/// language's name and, in gray, its file extensions; its `representedObject` is the
/// language's `SyntaxLanguage.identifier`.
enum LanguageMenu {

    static func addItems(to menu: NSMenu, target: AnyObject, action: Selector) {
        // Two columns: the language name, then its extensions in gray, starting at a tab stop
        // just right of the longest name, so the names stand out and the extensions line up.
        let font = NSFont.menuFont(ofSize: 0)
        let userLanguages = UserLanguageStore.shared.languages
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let names = Language.allCases.map(\.displayName) + userLanguages.map(\.name)
        let widestName = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let columns = NSMutableParagraphStyle()
        columns.tabStops = [NSTextTab(textAlignment: .left, location: (widestName + 24).rounded())]

        func makeItem(for language: SyntaxLanguage) -> NSMenuItem {
            let extensions = language.fileExtensions.map { ".\($0)" }.joined(separator: " ")
            let item = NSMenuItem(title: String(localized: "\(language.displayName)   \(extensions)",
                                                comment: "Save panel: language name, then its file extensions"),
                                  action: action, keyEquivalent: "")
            // What the menu shows; `title` above stays for VoiceOver and type-to-select.
            let attributedTitle = NSMutableAttributedString(string: language.displayName,
                                                            attributes: [.font: font, .paragraphStyle: columns])
            attributedTitle.append(NSAttributedString(string: "\t\(extensions)",
                                                      attributes: [.font: font, .paragraphStyle: columns,
                                                                   .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = attributedTitle
            item.target = target
            item.representedObject = language.identifier
            return item
        }

        menu.addItem(makeItem(for: .plainText))
        menu.addItem(.separator())
        if !userLanguages.isEmpty {
            menu.addItem(NSMenuItem.sectionHeader(title: String(localized: "My Languages", comment: "Language menu section: user-defined languages")))
            for language in userLanguages {
                menu.addItem(makeItem(for: .user(language)))
            }
            menu.addItem(.separator())
        }
        for group in Language.groupedByInitial {
            let submenu = NSMenu()
            for language in group.languages {
                submenu.addItem(makeItem(for: .builtIn(language)))
            }
            let groupItem = NSMenuItem(title: group.initial, action: nil, keyEquivalent: "")
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }
    }
}
