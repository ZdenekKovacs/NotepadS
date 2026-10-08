import AppKit

/// The app's shared document controller (installed in `AppDelegate`).
///
/// NSDocumentController already handles Open, Open Recent, autosave scheduling and window
/// restoration. We only customize the Open panel: hidden files, packages, a language filter.
final class DocumentController: NSDocumentController {

    override func beginOpenPanel(_ openPanel: NSOpenPanel,
                                 forTypes inTypes: [String]?,
                                 completionHandler: @escaping (Int) -> Void) {
        // Developers need dotfiles: .env, .gitignore, .zshrc …
        openPanel.showsHiddenFiles = true
        // Allow browsing into packages (.app, .xcodeproj, …) to open the text files inside.
        openPanel.treatsFilePackagesAsDirectories = true
        // "Show: All Files / Python / …"; it installs itself as accessory view and delegate.
        _ = OpenFilterAccessoryView(openPanel: openPanel)
        super.beginOpenPanel(openPanel, forTypes: inTypes, completionHandler: completionHandler)
    }
}
