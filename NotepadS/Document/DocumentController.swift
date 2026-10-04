import AppKit

/// The app's shared document controller (installed in `AppDelegate`).
///
/// NSDocumentController already handles Open, Open Recent, autosave scheduling and window
/// restoration. We only customize the Open panel.
final class DocumentController: NSDocumentController {

    override func beginOpenPanel(_ openPanel: NSOpenPanel,
                                 forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        // Developers need dotfiles: .env, .gitignore, .zshrc …
        openPanel.showsHiddenFiles = true
        // Allow browsing into packages (.app, .xcodeproj, …) to open the text files inside.
        openPanel.treatsFilePackagesAsDirectories = true
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
}
