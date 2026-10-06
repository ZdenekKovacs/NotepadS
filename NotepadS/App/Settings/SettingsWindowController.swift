import AppKit
import SwiftUI

/// The Settings window (⌘,), with SwiftUI content hosted in an AppKit window.
///
/// Created the first time it is opened, so SwiftUI isn't loaded at launch (fast cold start).
final class SettingsWindowController: NSWindowController {

    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = String(localized: "Settings", comment: "Settings window title")
        window.styleMask = [.titled, .closable]
        window.isRestorable = false
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
