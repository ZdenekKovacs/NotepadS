import AppKit
import SwiftUI

/// The Settings window (⌘,): the Editor and Languages tabs as icons in the toolbar, like
/// System Settings panes in most Mac apps. Each tab's content is SwiftUI, hosted in AppKit.
///
/// Created the first time it is opened, so SwiftUI isn't loaded at launch (fast cold start).
final class SettingsWindowController: NSWindowController {

    enum Tab: String {
        case editor, languages
    }

    static let shared = SettingsWindowController()

    /// The tab shown last, shown again next time.
    static let tabKey = "SettingsTab"
    private let tabViewController = RememberingTabViewController()

    private init() {
        // `.toolbar` puts the tabs into the window's toolbar; when switching, the window resizes
        // to the new tab's `preferredContentSize`, which each hosting controller keeps up to date.
        tabViewController.tabStyle = .toolbar
        tabViewController.addTabViewItem(Self.item(EditorSettingsView(), tab: .editor,
                                                   label: String(localized: "Editor", comment: "Settings tab"),
                                                   symbol: "textformat"))
        tabViewController.addTabViewItem(Self.item(LanguagesSettingsView(), tab: .languages,
                                                   label: String(localized: "Languages", comment: "Settings tab: user-defined languages"),
                                                   symbol: "chevron.left.forwardslash.chevron.right"))
        let window = NSWindow(contentViewController: tabViewController)
        window.styleMask = [.titled, .closable]
        window.isRestorable = false
        super.init(window: window)
        select(Tab(rawValue: UserDefaults.standard.string(forKey: Self.tabKey) ?? "") ?? .editor)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window at `tab` (e.g. Languages from the status bar's language menu).
    func show(_ tab: Tab) {
        select(tab)
        showWindow(nil)
    }

    private func select(_ tab: Tab) {
        if let index = tabViewController.tabViewItems.firstIndex(where: { $0.identifier as? String == tab.rawValue }) {
            tabViewController.selectedTabViewItemIndex = index
        }
    }

    private static func item(_ view: some View, tab: Tab, label: String, symbol: String) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        // Without this the window keeps one size; with it, each tab's SwiftUI size becomes the
        // controller's preferred size, which the toolbar-style tab view resizes the window to.
        host.sizingOptions = [.preferredContentSize]
        host.title = label   // the window title follows the selected tab
        let item = NSTabViewItem(viewController: host)
        item.identifier = tab.rawValue
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// Remembers the selected tab. NSTabViewController is its tab view's delegate, so a subclass
/// hears about every switch here.
private final class RememberingTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let identifier = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(identifier, forKey: SettingsWindowController.tabKey)
        }
    }
}
