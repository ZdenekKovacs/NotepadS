import AppKit
import NotepadSCore

/// Adjusts the menu bar loaded from `MainMenu.xib`.
///
/// The XIB is Xcode's standard "Main Menu" template. It comes from a XIB, not code, because
/// that is the only public way to get a working Open Recent menu: the template marks that
/// submenu as the system's recent-documents menu, and AppKit fills it (also in the sandbox).
/// Here we only remove what a plain-text editor doesn't need and add our own items.
///
/// Items are found by their action, not their title, so this keeps working once the menu is
/// translated. Items without a target go through the responder chain:
/// text view → … → EditorViewController → window → window controller → document → app.
enum MainMenu {

    /// Call in `applicationWillFinishLaunching`, after AppKit has loaded the XIB.
    static func adjust() {
        guard let mainMenu = NSApp.mainMenu else {
            assertionFailure("MainMenu.xib was not loaded (NSMainNibFile in Info.plist)")
            return
        }
        replaceTemplateAppName(in: mainMenu)

        // Rich-text features that make no sense in a plain-text editor.
        removeTopLevelMenu(containing: "orderFrontFontPanel:", from: mainMenu)          // Format menu
        removeItem(withSubmenuContaining: "showGuessPanel:", from: mainMenu)            // Spelling and Grammar
        removeItem(withSubmenuContaining: "orderFrontSubstitutionsPanel:", from: mainMenu)  // Substitutions
        removeItem(withSubmenuContaining: "uppercaseWord:", from: mainMenu)             // Transformations
        removeItem(withSubmenuContaining: "startSpeaking:", from: mainMenu)             // Speech
        // No toolbar or sidebar.
        for action in ["toggleToolbarShown:", "runToolbarCustomizationPalette:", "toggleSidebar:"] {
            removeItems(withAction: action, from: mainMenu)
        }
        // The template's Print… sends `print:`, which would print the window's text view as it
        // looks on screen. `printDocument:` asks TextDocument, which lays the text out for paper.
        for item in allItems(in: mainMenu) where item.action == NSSelectorFromString("print:") {
            item.action = NSSelectorFromString("printDocument:")
        }
        // The template's Preferences item has no action, so it can only be found by title.
        removeItems(withTitle: "Preferences…", from: mainMenu)
        removeDuplicateSeparators(in: mainMenu)

        // Settings… after About, where macOS apps have it. (The template's Preferences item was removed above.)
        if let appMenu = mainMenu.items.first?.submenu,
           let aboutIndex = appMenu.items.firstIndex(where: { $0.action == NSSelectorFromString("orderFrontStandardAboutPanel:") }) {
            appMenu.insertItem(.separator(), at: aboutIndex + 1)
            appMenu.insertItem(NSMenuItem(title: String(localized: "Settings…", comment: "App menu item"),
                                          action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ","),
                               at: aboutIndex + 2)
        }
        if let viewMenu = submenu(containing: "toggleFullScreen:", in: mainMenu) {
            addFontSizeItems(to: viewMenu)
        }
        if let findMenu = submenu(containing: "performFindPanelAction:", in: mainMenu) {
            let item = NSMenuItem(title: String(localized: "Find and Replace with Regular Expressions…", comment: "Edit › Find menu item"),
                                  action: #selector(EditorViewController.showRegexFindPanel(_:)), keyEquivalent: "f")
            item.keyEquivalentModifierMask = [.shift, .option, .command]
            findMenu.insertItem(item, at: 2)   // after Find… and Find and Replace…
            let filesItem = NSMenuItem(title: String(localized: "Find in Files…", comment: "Edit › Find menu item: search a folder"),
                                       action: #selector(AppDelegate.showFindInFiles(_:)), keyEquivalent: "f")
            filesItem.keyEquivalentModifierMask = [.shift, .command]
            findMenu.insertItem(filesItem, at: 3)
        }
        if let editMenu = submenu(containing: "selectAll:", in: mainMenu),
           let editItem = mainMenu.items.first(where: { $0.submenu === editMenu }) {
            let textItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            textItem.submenu = makeTextMenu()
            mainMenu.insertItem(textItem, at: mainMenu.index(of: editItem) + 1)
        }
        if let fileMenu = submenu(containing: "performClose:", in: mainMenu),
           let closeIndex = fileMenu.items.firstIndex(where: { $0.action == NSSelectorFromString("performClose:") }) {
            // No shortcut: AppKit already uses ⌥⌘W for "Close Other Tabs".
            fileMenu.insertItem(NSMenuItem(title: String(localized: "Close All", comment: "File menu item: close every document, then open a new empty one"),
                                           action: #selector(AppDelegate.closeAllDocuments(_:)), keyEquivalent: ""),
                                at: closeIndex + 1)
        }
        if let editMenu = submenu(containing: "selectAll:", in: mainMenu) {
            editMenu.addItem(.separator())
            editMenu.addItem(NSMenuItem(title: String(localized: "Go to Line…", comment: "Edit menu item"),
                                        action: #selector(EditorViewController.goToLine(_:)), keyEquivalent: "l"))
            // No shortcut: the Insert key (Help key on a Mac) toggles it, see EditorTextView.
            editMenu.addItem(NSMenuItem(title: String(localized: "Overwrite Mode", comment: "Edit menu item: typing replaces the characters after the caret"),
                                        action: #selector(EditorViewController.toggleOverwriteMode(_:)), keyEquivalent: ""))
            // ⌃⌥↑ / ⌃⌥↓ like Ctrl+Alt+↑/↓ in VS Code on Windows (⌥⌘↑/↓ already moves lines).
            editMenu.addItem(.separator())
            editMenu.addItem(withModifiers([.control, .option], NSMenuItem(title: String(localized: "Add Cursor Above", comment: "Edit menu item: another caret on the line above"),
                                                                           action: #selector(EditorTextView.addCursorAbove(_:)),
                                                                           keyEquivalent: arrowKey(NSUpArrowFunctionKey))))
            editMenu.addItem(withModifiers([.control, .option], NSMenuItem(title: String(localized: "Add Cursor Below", comment: "Edit menu item: another caret on the line below"),
                                                                           action: #selector(EditorTextView.addCursorBelow(_:)),
                                                                           keyEquivalent: arrowKey(NSDownArrowFunctionKey))))
            editMenu.addItem(.separator())
            editMenu.addItem(NSMenuItem(title: String(localized: "ASCII Character Panel", comment: "Edit menu item: table of characters 0–255 to insert"),
                                        action: #selector(AppDelegate.showCharacterPanel(_:)), keyEquivalent: ""))
        }
    }

    // MARK: - Our items

    /// The Text menu: transformations from NotepadSCore, applied by EditorViewController to the
    /// selection or the whole document.
    private static func makeTextMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Text", comment: "Menu bar: text transformations"))
        let groups: [[TextTransform]] = [
            [.formatJSON, .minifyJSON],
            [.base64Encode, .base64Decode, .urlEncode, .urlDecode],
            [.uppercase, .lowercase, .titleCase, .titleCaseKeepingOtherLetters, .sentenceCase,
             .sentenceCaseKeepingOtherLetters, .invertCase, .randomCase],
            [.camelCase, .snakeCase, .kebabCase],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for transform in group {
                menu.addItem(transformItem(transform))
            }
            if index == 1 {
                // Hashes after the encodings.
                menu.addItem(.separator())
                let hashItem = NSMenuItem(title: String(localized: "Hash", comment: "Text menu: submenu with SHA-256, SHA-512, SHA-1, MD5"),
                                          action: nil, keyEquivalent: "")
                hashItem.submenu = makeHashMenu()
                menu.addItem(hashItem)
            }
        }
        menu.addItem(.separator())
        let linesItem = NSMenuItem(title: String(localized: "Lines", comment: "Text menu: submenu with line operations"),
                                   action: nil, keyEquivalent: "")
        linesItem.submenu = makeLinesMenu()
        menu.addItem(linesItem)
        let whitespaceItem = NSMenuItem(title: String(localized: "Whitespace", comment: "Text menu: submenu with whitespace operations"),
                                        action: nil, keyEquivalent: "")
        whitespaceItem.submenu = makeWhitespaceMenu()
        menu.addItem(whitespaceItem)
        return menu
    }

    private static func transformItem(_ transform: TextTransform) -> NSMenuItem {
        let item = NSMenuItem(title: transform.name,
                              action: #selector(EditorViewController.applyTextTransform(_:)), keyEquivalent: "")
        item.representedObject = transform.rawValue
        return item
    }

    /// Text › Lines, like Notepad++'s Edit › Line Operations. The first group works on the
    /// caret's line (or the selected lines), the rest on the selected lines or the whole document.
    private static func makeLinesMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Lines", comment: "Text menu: submenu with line operations"))
        let upArrow = arrowKey(NSUpArrowFunctionKey)
        let downArrow = arrowKey(NSDownArrowFunctionKey)
        menu.addItem(NSMenuItem(title: String(localized: "Duplicate Line", comment: "Text › Lines menu item"),
                                action: #selector(EditorViewController.duplicateLines(_:)), keyEquivalent: "d"))
        menu.addItem(withModifiers([.shift, .command], NSMenuItem(title: String(localized: "Delete Line", comment: "Text › Lines menu item"),
                                                                  action: #selector(EditorViewController.deleteLines(_:)),
                                                                  keyEquivalent: "k")))
        menu.addItem(withModifiers([.option, .command], NSMenuItem(title: String(localized: "Move Line Up", comment: "Text › Lines menu item"),
                                                                   action: #selector(EditorViewController.moveLinesUp(_:)),
                                                                   keyEquivalent: upArrow)))
        menu.addItem(withModifiers([.option, .command], NSMenuItem(title: String(localized: "Move Line Down", comment: "Text › Lines menu item"),
                                                                   action: #selector(EditorViewController.moveLinesDown(_:)),
                                                                   keyEquivalent: downArrow)))
        menu.addItem(.separator())
        let joinItem = transformItem(.joinLines)
        joinItem.keyEquivalent = "j"
        menu.addItem(withModifiers([.control, .command], joinItem))
        menu.addItem(NSMenuItem(title: String(localized: "Split Lines…", comment: "Text › Lines menu item: asks for the maximum line length"),
                                action: #selector(EditorViewController.splitLines(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        for transform in [TextTransform.sortLinesAscending, .sortLinesDescending, .reverseLines, .shuffleLines] {
            menu.addItem(transformItem(transform))
        }
        menu.addItem(.separator())
        for transform in [TextTransform.removeDuplicateLines, .removeConsecutiveDuplicateLines, .removeEmptyLines] {
            menu.addItem(transformItem(transform))
        }
        return menu
    }

    /// Text › Whitespace, like Notepad++'s Edit › Blank Operations. Works on the selected lines,
    /// or the whole document; tab stops come from Settings.
    private static func makeWhitespaceMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Whitespace", comment: "Text menu: submenu with whitespace operations"))
        let groups: [[TextTransform]] = [
            [.trimLeadingWhitespace, .trimTrailingWhitespace, .trimWhitespace],
            [.tabsToSpaces, .leadingSpacesToTabs],
            [.lineBreaksToSpaces],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for transform in group {
                menu.addItem(transformItem(transform))
            }
        }
        return menu
    }

    private static func makeHashMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Hash", comment: "Text menu: submenu with SHA-256, SHA-512, SHA-1, MD5"))
        // Titles say "of Selection" or "of Document"; EditorViewController sets them when the menu opens.
        for hash in TextHash.allCases {
            let item = NSMenuItem(title: String(localized: "Copy \(hash.name) of Document", comment: "Text › Hash menu item"),
                                  action: #selector(EditorViewController.copyHash(_:)), keyEquivalent: "")
            item.representedObject = hash.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for hash in TextHash.allCases {
            let item = NSMenuItem(title: String(localized: "Replace Selection with \(hash.name)", comment: "Text › Hash menu item"),
                                  action: #selector(EditorViewController.replaceSelectionWithHash(_:)), keyEquivalent: "")
            item.representedObject = hash.rawValue
            menu.addItem(item)
        }
        return menu
    }

    /// ⌘+ / ⌘− / ⌘0 at the top of the View menu, handled by EditorViewController.
    private static func addFontSizeItems(to menu: NSMenu) {
        let increase = #selector(EditorViewController.increaseFontSize(_:))
        let items = [
            NSMenuItem(title: String(localized: "Increase Font Size", comment: "View menu item"),
                       action: increase, keyEquivalent: "+"),
            // ⌘= is what people press for ⌘+ on keyboards where "+" needs Shift or sits on a digit
            // key. The hidden alias makes it work without a visible duplicate item.
            hiddenAlias(NSMenuItem(title: String(localized: "Increase Font Size", comment: "View menu item"),
                                   action: increase, keyEquivalent: "=")),
            NSMenuItem(title: String(localized: "Decrease Font Size", comment: "View menu item"),
                       action: #selector(EditorViewController.decreaseFontSize(_:)), keyEquivalent: "-"),
            NSMenuItem(title: String(localized: "Actual Size", comment: "View menu item: default font size"),
                       action: #selector(EditorViewController.resetFontSize(_:)), keyEquivalent: "0"),
            NSMenuItem.separator(),
            // ⌃⌘W, because AppKit already uses ⌥⌘W for "Close Other Tabs".
            withModifiers([.control, .command], NSMenuItem(title: String(localized: "Wrap Lines", comment: "View menu item"),
                                                           action: #selector(EditorViewController.toggleWordWrap(_:)),
                                                           keyEquivalent: "w")),
            withModifiers([.option, .command], NSMenuItem(title: String(localized: "Show Invisibles", comment: "View menu item: marks for spaces, tabs and line breaks"),
                                                          action: #selector(EditorViewController.toggleInvisibles(_:)),
                                                          keyEquivalent: "i")),
            withModifiers([.control, .command], NSMenuItem(title: String(localized: "Show Minimap", comment: "View menu item: miniature of the document beside the text"),
                                                           action: #selector(EditorViewController.toggleMinimap(_:)),
                                                           keyEquivalent: "m")),
            withModifiers([.control, .command], NSMenuItem(title: String(localized: "Show Function List", comment: "View menu item: list of the document's functions, classes and headings"),
                                                           action: #selector(EditorViewController.toggleFunctionList(_:)),
                                                           keyEquivalent: "l")),
            NSMenuItem.separator(),
            // Like Xcode: ⌥⌘← / ⌥⌘→ fold and unfold, with ⇧ for all blocks.
            withModifiers([.option, .command], NSMenuItem(title: String(localized: "Fold", comment: "View menu item: collapse the code block at the caret"),
                                                          action: #selector(EditorViewController.foldBlock(_:)),
                                                          keyEquivalent: arrowKey(NSLeftArrowFunctionKey))),
            withModifiers([.option, .command], NSMenuItem(title: String(localized: "Unfold", comment: "View menu item: expand the code block at the caret"),
                                                          action: #selector(EditorViewController.unfoldBlock(_:)),
                                                          keyEquivalent: arrowKey(NSRightArrowFunctionKey))),
            withModifiers([.shift, .option, .command], NSMenuItem(title: String(localized: "Fold All", comment: "View menu item"),
                                                                  action: #selector(EditorViewController.foldAllBlocks(_:)),
                                                                  keyEquivalent: arrowKey(NSLeftArrowFunctionKey))),
            withModifiers([.shift, .option, .command], NSMenuItem(title: String(localized: "Unfold All", comment: "View menu item"),
                                                                  action: #selector(EditorViewController.unfoldAllBlocks(_:)),
                                                                  keyEquivalent: arrowKey(NSRightArrowFunctionKey))),
            NSMenuItem.separator(),
            // ⌃⌘E: letters work on every keyboard layout (on a Czech one, the backslash needs ⌥).
            withModifiers([.control, .command], NSMenuItem(title: String(localized: "Split Editor Side by Side", comment: "View menu item: two views of the same document"),
                                                           action: #selector(EditorViewController.splitEditorSideBySide(_:)),
                                                           keyEquivalent: "e")),
            withModifiers([.shift, .control, .command], NSMenuItem(title: String(localized: "Split Editor Top and Bottom", comment: "View menu item: two views of the same document"),
                                                                   action: #selector(EditorViewController.splitEditorTopAndBottom(_:)),
                                                                   keyEquivalent: "E")),
            NSMenuItem.separator(),
        ]
        for (index, item) in items.enumerated() {
            menu.insertItem(item, at: index)
        }
    }

    private static func withModifiers(_ modifiers: NSEvent.ModifierFlags, _ item: NSMenuItem) -> NSMenuItem {
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    /// Arrow keys as key equivalents are their function-key characters (NSUpArrowFunctionKey …).
    private static func arrowKey(_ functionKey: Int) -> String {
        // Function-key characters are in the Private Use Area, always valid scalars.
        String(Character(UnicodeScalar(UInt16(functionKey))!))
    }

    private static func hiddenAlias(_ item: NSMenuItem) -> NSMenuItem {
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    // MARK: - Helpers

    /// The template says "NewApplication" (About, Hide, Quit, Help); use the real app name.
    private static func replaceTemplateAppName(in menu: NSMenu) {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NotepadS"
        for item in menu.items {
            item.title = item.title.replacingOccurrences(of: "NewApplication", with: appName)
            if let submenu = item.submenu {
                submenu.title = submenu.title.replacingOccurrences(of: "NewApplication", with: appName)
                replaceTemplateAppName(in: submenu)
            }
        }
    }

    /// Every item of `menu` and its submenus.
    private static func allItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems(in:)) ?? []) }
    }

    /// The submenu (at any depth) that directly contains an item with `action`.
    private static func submenu(containing action: String, in menu: NSMenu) -> NSMenu? {
        let selector = NSSelectorFromString(action)
        if menu.items.contains(where: { $0.action == selector }) {
            return menu
        }
        for item in menu.items {
            if let submenu = item.submenu, let found = Self.submenu(containing: action, in: submenu) {
                return found
            }
        }
        return nil
    }

    /// Removes the menu-bar menu (e.g. Format) that contains `action` at any depth.
    private static func removeTopLevelMenu(containing action: String, from mainMenu: NSMenu) {
        for item in mainMenu.items {
            if let submenu = item.submenu, Self.submenu(containing: action, in: submenu) != nil {
                mainMenu.removeItem(item)
            }
        }
    }

    /// Removes the item whose submenu directly contains an item with `action`.
    private static func removeItem(withSubmenuContaining action: String, from menu: NSMenu) {
        guard let submenu = submenu(containing: action, in: menu),
              let parent = submenu.supermenu,
              let item = parent.items.first(where: { $0.submenu === submenu }) else { return }
        parent.removeItem(item)
    }

    private static func removeItems(withAction action: String, from menu: NSMenu) {
        let selector = NSSelectorFromString(action)
        for item in menu.items {
            if item.action == selector {
                menu.removeItem(item)
            } else if let submenu = item.submenu {
                removeItems(withAction: action, from: submenu)
            }
        }
    }

    private static func removeItems(withTitle title: String, from menu: NSMenu) {
        for item in menu.items {
            if item.title == title {
                menu.removeItem(item)
            } else if let submenu = item.submenu {
                removeItems(withTitle: title, from: submenu)
            }
        }
    }

    /// After removing items, two separators may follow each other or end a menu.
    private static func removeDuplicateSeparators(in menu: NSMenu) {
        var previousWasSeparator = true   // also removes a separator at the top
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator {
                menu.removeItem(item)
                continue
            }
            previousWasSeparator = item.isSeparatorItem
            if let submenu = item.submenu {
                removeDuplicateSeparators(in: submenu)
            }
        }
        if let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
    }
}
