import AppKit

/// Builds the menu bar in code (no MainMenu.xib).
///
/// Standard actions are referenced by their Objective-C selector names ("saveDocument:")
/// because several have confusing Swift names (e.g. NSDocument's `duplicateDocument:` is
/// `duplicate(_:)` in Swift). Menu items with no target go through the responder chain:
/// text view → … → EditorViewController → window → window controller → document → app.
enum MainMenu {

    static func make() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")
        for submenu in [appMenu(), fileMenu(), editMenu(), viewMenu(), windowMenu(), helpMenu()] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    private static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "NotepadS"
    }

    // MARK: - Menus

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: appName)
        menu.addItem(title: "About \(appName)", action: "orderFrontStandardAboutPanel:")
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        menu.addItem(title: "Services", submenu: services)
        menu.addItem(.separator())
        menu.addItem(title: "Hide \(appName)", action: "hide:", key: "h")
        menu.addItem(title: "Hide Others", action: "hideOtherApplications:", key: "h", modifiers: [.command, .option])
        menu.addItem(title: "Show All", action: "unhideAllApplications:")
        menu.addItem(.separator())
        menu.addItem(title: "Quit \(appName)", action: "terminate:", key: "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(title: "New", action: "newDocument:", key: "n")
        menu.addItem(title: "Open…", action: "openDocument:", key: "o")
        menu.addItem(title: "Open Recent", submenu: openRecentMenu())
        menu.addItem(.separator())
        menu.addItem(title: "Close", action: "performClose:", key: "w")
        menu.addItem(title: "Save…", action: "saveDocument:", key: "s")
        // With autosave in place, macOS uses "Duplicate"; "Save As…" appears while holding ⌥.
        menu.addItem(title: "Duplicate", action: "duplicateDocument:", key: "s", modifiers: [.command, .shift])
        let saveAs = menu.addItem(title: "Save As…", action: "saveDocumentAs:", key: "s", modifiers: [.command, .shift, .option])
        saveAs.isAlternate = true
        menu.addItem(title: "Rename…", action: "renameDocument:")
        menu.addItem(title: "Move To…", action: "moveDocument:")
        menu.addItem(title: "Revert To Saved", action: "revertDocumentToSaved:")
        return menu
    }

    private static func editMenu() -> NSMenu {
        // AppKit adds "AutoFill", "Start Dictation" and "Emoji & Symbols" to a menu titled "Edit".
        let menu = NSMenu(title: "Edit")
        menu.addItem(title: "Undo", action: "undo:", key: "z")
        menu.addItem(title: "Redo", action: "redo:", key: "z", modifiers: [.command, .shift])
        menu.addItem(.separator())
        menu.addItem(title: "Cut", action: "cut:", key: "x")
        menu.addItem(title: "Copy", action: "copy:", key: "c")
        menu.addItem(title: "Paste", action: "paste:", key: "v")
        menu.addItem(title: "Delete", action: "delete:")
        menu.addItem(title: "Select All", action: "selectAll:", key: "a")
        menu.addItem(.separator())
        menu.addItem(title: "Find", submenu: findMenu())
        return menu
    }

    /// Drives NSTextView's built-in find bar (`usesFindBar = true`). The tag selects the action.
    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")
        let action = "performTextFinderAction:"
        menu.addItem(title: "Find…", action: action, key: "f", tag: NSTextFinder.Action.showFindInterface.rawValue)
        menu.addItem(title: "Find and Replace…", action: action, key: "f", modifiers: [.command, .option],
                     tag: NSTextFinder.Action.showReplaceInterface.rawValue)
        menu.addItem(title: "Find Next", action: action, key: "g", tag: NSTextFinder.Action.nextMatch.rawValue)
        menu.addItem(title: "Find Previous", action: action, key: "g", modifiers: [.command, .shift],
                     tag: NSTextFinder.Action.previousMatch.rawValue)
        menu.addItem(title: "Use Selection for Find", action: action, key: "e",
                     tag: NSTextFinder.Action.setSearchString.rawValue)
        menu.addItem(title: "Jump to Selection", action: "centerSelectionInVisibleArea:", key: "j")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        // AppKit adds "Show Tab Bar", "Show All Tabs" and "Enter Full Screen" here automatically.
        let menu = NSMenu(title: "View")
        let increase = #selector(EditorViewController.increaseFontSize(_:))
        menu.addItem(title: "Increase Font Size", selector: increase, key: "+")
        // ⌘= is what people press on many keyboards for ⌘+; keep it working without a visible duplicate.
        let alias = menu.addItem(title: "Increase Font Size", selector: increase, key: "=")
        alias.isHidden = true
        alias.allowsKeyEquivalentWhenHidden = true
        menu.addItem(title: "Decrease Font Size", selector: #selector(EditorViewController.decreaseFontSize(_:)), key: "-")
        menu.addItem(title: "Actual Size", selector: #selector(EditorViewController.resetFontSize(_:)), key: "0")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        // AppKit adds the window list and the tab commands (Show Next Tab, Merge All Windows, …).
        let menu = NSMenu(title: "Window")
        menu.addItem(title: "Minimize", action: "performMiniaturize:", key: "m")
        menu.addItem(title: "Zoom", action: "performZoom:")
        menu.addItem(.separator())
        menu.addItem(title: "Bring All to Front", action: "arrangeInFront:")
        NSApp.windowsMenu = menu
        return menu
    }

    private static func helpMenu() -> NSMenu {
        // An empty Help menu still gets the system's menu search field.
        let menu = NSMenu(title: "Help")
        NSApp.helpMenu = menu
        return menu
    }

    private static func openRecentMenu() -> NSMenu {
        let menu = NSMenu(title: "Open Recent")
        menu.addItem(title: "Clear Menu", action: "clearRecentDocuments:")
        // NSDocumentController fills this menu only if it carries the internal name
        // "NSRecentDocumentsMenu". Interface Builder sets that name for you; there is no public
        // API to do it in code, so we call the long-standing private setter if it exists.
        // This is the only private API in the project. If it ever disappears, Open Recent
        // stays empty and nothing else breaks. (Fallback: move the menu bar into a XIB.)
        let setMenuName = NSSelectorFromString("_setMenuName:")
        if menu.responds(to: setMenuName) {
            menu.perform(setMenuName, with: "NSRecentDocumentsMenu")
        }
        return menu
    }
}

// MARK: - Small helpers to keep the menu definitions readable

private extension NSMenu {

    /// Adds an item for a standard AppKit action given by its Objective-C selector name.
    @discardableResult
    func addItem(title: String, action: String, key: String = "",
                 modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        addItem(title: title, selector: NSSelectorFromString(action), key: key, modifiers: modifiers, tag: tag)
    }

    /// Adds an item for one of our own `@objc` actions.
    @discardableResult
    func addItem(title: String, selector: Selector, key: String = "",
                 modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        addItem(item)
        return item
    }

    @discardableResult
    func addItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
        return item
    }
}
