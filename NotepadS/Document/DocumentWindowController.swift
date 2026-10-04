import AppKit

/// One window (or tab) showing one document.
///
/// Window restoration is automatic: a window controller that belongs to an NSDocument gets
/// the document controller as its restoration class.
final class DocumentWindowController: NSWindowController {

    private static let defaultContentSize = NSSize(width: 900, height: 650)

    init(document: TextDocument) {
        let window = DocumentWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // The window controller owns the window; with the default (true) a window created in
        // code would also release itself on close, which can crash under ARC.
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 400, height: 200)
        // Open new documents as tabs of the current window, like Notepad++.
        // (Default `.automatic` follows System Settings, which usually means separate windows.)
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "NotepadSDocument"

        super.init(window: window)

        window.contentViewController = EditorViewController(document: document)
        // Setting contentViewController resizes the window to the view; restore our default.
        window.setContentSize(Self.defaultContentSize)
        window.center()
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // Only now is the window part of a tab group, so the tab bar can be shown.
        (window as? DocumentWindow)?.showTabBarUnlessHiddenByUser()
    }

    /// Implementing this makes the "+" button appear in the tab bar.
    override func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }
}
