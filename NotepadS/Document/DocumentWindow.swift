import AppKit

/// The window of a document. Its only addition: it remembers whether the user hid the tab bar.
///
/// macOS hides the tab bar (and with it the "+" button) while a window has a single tab.
/// NotepadS shows it like Notepad++ does, unless the user chose View › Hide Tab Bar.
final class DocumentWindow: NSWindow {

    private static let tabBarHiddenKey = "TabBarHiddenByUser"

    /// Shows the tab bar if it is hidden and the user hasn't hidden it on purpose.
    func showTabBarUnlessHiddenByUser() {
        guard !UserDefaults.standard.bool(forKey: Self.tabBarHiddenKey),
              let tabGroup, !tabGroup.isTabBarVisible else { return }
        super.toggleTabBar(nil)
    }

    /// View › Show/Hide Tab Bar (the menu item AppKit adds) calls this. Remember the choice so
    /// new windows respect it.
    override func toggleTabBar(_ sender: Any?) {
        super.toggleTabBar(sender)
        let isVisible = tabGroup?.isTabBarVisible ?? true
        UserDefaults.standard.set(!isVisible, forKey: Self.tabBarHiddenKey)
    }
}
