import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The first NSDocumentController ever created becomes `NSDocumentController.shared`.
        // Creating ours here, before AppKit asks for the shared one, installs the subclass.
        _ = DocumentController()

        Self.setFixedDefaults()

        // AppKit has already loaded the menu bar from MainMenu.xib (NSMainNibFile in Info.plist).
        MainMenu.adjust()
    }

    /// Defaults the app always sets, also again after Settings › Restore Defaults.
    static func setFixedDefaults() {
        // "Never lose text": reopen all windows — including autosaved untitled documents —
        // on the next launch, even when "Close windows when quitting an application" is on
        // in System Settings › Desktop & Dock. A value in the app's own defaults domain
        // overrides the global setting for this app only.
        UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
    }

    /// NotepadS › Settings… (⌘,)
    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(sender)
    }

    /// "Define a Language…" in the status bar's language menu: Settings at the Languages tab.
    @objc func showLanguageSettings(_ sender: Any?) {
        SettingsWindowController.shared.show(.languages)
    }

    /// File › Close All. (The app delegate is always in the responder chain of menu actions.)
    @objc func closeAllDocuments(_ sender: Any?) {
        (NSDocumentController.shared as? DocumentController)?.closeAllAndOpenNew()
    }

    /// Edit › Find › Find in Files… (⇧⌘F). A selection in the front document becomes the search
    /// text, and its folder is where "Choose…" starts.
    @objc func showFindInFiles(_ sender: Any?) {
        let editor = NSApp.mainWindow?.contentViewController as? EditorViewController
        FindInFilesWindowController.shared.show(selectedText: editor?.selectedTextForSearch,
                                                suggestedFolder: editor?.document.fileURL?.deletingLastPathComponent())
    }

    /// Edit › Macro › Start/Stop Recording (⌃⌘R). Recording works in every document.
    @objc func toggleMacroRecording(_ sender: Any?) {
        let recorder = MacroRecorder.shared
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            recorder.startRecording()
        }
    }

    /// The menu item says what it will do.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMacroRecording(_:)) {
            menuItem.title = MacroRecorder.shared.isRecording
                ? String(localized: "Stop Recording", comment: "Edit › Macro menu item")
                : String(localized: "Start Recording", comment: "Edit › Macro menu item")
        }
        return true
    }

    /// Edit › ASCII Character Panel
    @objc func showCharacterPanel(_ sender: Any?) {
        CharacterPanelController.shared.showWindow(sender)
    }

    /// Opt in to secure coding for window restoration (AppKit logs a warning otherwise).
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Open an empty document when the app starts with nothing to restore, like TextEdit.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }
}
