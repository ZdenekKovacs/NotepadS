import AppKit

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
        // Printing arrives in v0.4. No toolbar or sidebar, and no Settings window yet (v0.4).
        for action in ["runPageLayout:", "print:", "printDocument:",
                       "toggleToolbarShown:", "runToolbarCustomizationPalette:", "toggleSidebar:"] {
            removeItems(withAction: action, from: mainMenu)
        }
        // The template's Preferences item has no action, so it can only be found by title.
        removeItems(withTitle: "Preferences…", from: mainMenu)
        removeDuplicateSeparators(in: mainMenu)

        if let viewMenu = submenu(containing: "toggleFullScreen:", in: mainMenu) {
            addFontSizeItems(to: viewMenu)
        }
    }

    // MARK: - Our items

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
