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

    // MARK: - File › Close All

    /// Closes every document and then opens one new empty document. Like Close, it asks about
    /// untitled documents with text (Save, Delete or Cancel); documents with a file are saved
    /// automatically (autosave in place). If the user cancels, the rest stay open and no new
    /// document is created.
    func closeAllAndOpenNew() {
        closeAllDocuments(withDelegate: self,
                          didCloseAllSelector: #selector(documentController(_:didCloseAll:contextInfo:)),
                          contextInfo: nil)
    }

    /// The callback `closeAllDocuments` expects (an Objective-C selector, hence the signature).
    @objc private func documentController(_ controller: NSDocumentController, didCloseAll: Bool,
                                          contextInfo: UnsafeMutableRawPointer?) {
        guard didCloseAll else { return }
        newDocument(nil)
    }
}
