import AppKit

/// One window (or tab) showing one document.
///
/// Window restoration is automatic: a window controller that belongs to an NSDocument gets
/// the document controller as its restoration class.
final class DocumentWindowController: NSWindowController {

    private static let defaultContentSize = NSSize(width: 900, height: 650)
    /// The name under which the frame of the last document window the user moved, resized or
    /// closed is kept in UserDefaults (by `NSWindow.saveFrame(usingName:)`).
    private static let frameAutosaveName = "NotepadSDocumentWindow"

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
        // A new window opens where the user last put a document window (e.g. snapped to the left
        // half of the screen), also after Close All; the first time ever, centered.
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        shouldCascadeWindows = true
        // Remember the frame whenever this window moves, resizes or closes. Not with
        // `setFrameAutosaveName`: only one open window can own a name, so after closing that
        // window (or tab) the others wouldn't be remembered any more.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(rememberFrame(_:)), name: name, object: window)
        }
    }

    @objc private func rememberFrame(_ notification: Notification) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }   // a full-screen frame isn't a place
        window.saveFrame(usingName: Self.frameAutosaveName)
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
