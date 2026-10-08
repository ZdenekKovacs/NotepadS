import AppKit
import NotepadSCore

/// Shown in the Open panel: "Show: All Files / Plain Text / A › … / P › Python …". Choosing a
/// language filters the file list to that language's extensions and file names ("Makefile").
///
/// macOS doesn't hide files that don't match a filter; it shows them grayed out and they can't
/// be chosen (like `allowedContentTypes`, which can't match file names such as "Makefile").
/// The filter is the panel delegate's `panel(_:shouldEnable:)`. The last choice is remembered.
final class OpenFilterAccessoryView: NSView, NSOpenSavePanelDelegate {

    private static let filterKey = "OpenPanelLanguageFilter"

    private weak var openPanel: NSOpenPanel?
    private let pullDown = NSPopUpButton(frame: .zero, pullsDown: true)
    private let allFilesItem = NSMenuItem()
    /// nil shows all files.
    private var language: Language? = UserDefaults.standard.string(forKey: OpenFilterAccessoryView.filterKey)
        .flatMap(Language.init(rawValue:))

    /// Sets itself as the panel's accessory view and delegate. The panel keeps its accessory
    /// view (strong reference); its `delegate` is weak, so this view must be that accessory view.
    init(openPanel: NSOpenPanel) {
        self.openPanel = openPanel
        super.init(frame: .zero)
        buildMenu()
        setUpLayout()
        showChoice()
        openPanel.accessoryView = self
        // Since macOS 10.11 the accessory view hides behind an "Options" button unless disclosed.
        openPanel.isAccessoryViewDisclosed = true
        openPanel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - NSOpenSavePanelDelegate

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        guard let language else { return true }
        // Folders (and packages, which the panel lets you browse) must stay enabled to navigate.
        // If the sandbox doesn't let us look, enable the item rather than block it.
        if url.hasDirectoryPath { return true }
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { return true }
        if values.isDirectory == true { return true }
        return language.includes(fileName: url.lastPathComponent)
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem())   // item 0 of a pull-down is its title, not a choice
        allFilesItem.title = String(localized: "All Files", comment: "Open panel filter: no filter")
        allFilesItem.target = self
        allFilesItem.action = #selector(allFilesChosen(_:))
        menu.addItem(allFilesItem)
        menu.addItem(.separator())
        LanguageMenu.addItems(to: menu, target: self, action: #selector(languageChosen(_:)))
        pullDown.menu = menu
        pullDown.toolTip = String(localized: "Files of other languages are shown grayed out.", comment: "Open panel filter tooltip")
    }

    @objc private func allFilesChosen(_ sender: NSMenuItem) {
        choose(nil)
    }

    @objc private func languageChosen(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        choose(Language(rawValue: rawValue))
    }

    private func choose(_ newLanguage: Language?) {
        language = newLanguage
        UserDefaults.standard.set(newLanguage?.rawValue ?? "", forKey: Self.filterKey)
        showChoice()
        // Asks the delegate again for every visible file (documented for this purpose).
        openPanel?.validateVisibleColumns()
    }

    /// The pull-down's title and the checkmarks follow the current choice.
    private func showChoice() {
        pullDown.item(at: 0)?.title = language?.displayName ?? allFilesItem.title
        pullDown.synchronizeTitleAndSelectedItem()
        allFilesItem.state = language == nil ? .on : .off
        for item in pullDown.menu?.items ?? [] {
            if let submenu = item.submenu {
                for languageItem in submenu.items {
                    languageItem.state = languageItem.representedObject as? String == language?.rawValue ? .on : .off
                }
                item.state = submenu.items.contains { $0.state == .on } ? .on : .off
            } else if item.representedObject is String {
                item.state = item.representedObject as? String == language?.rawValue ? .on : .off
            }
        }
    }

    private func setUpLayout() {
        let label = NSTextField(labelWithString: String(localized: "Show:", comment: "Open panel: label before the language filter"))
        let stack = NSStackView(views: [label, pullDown])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        ])
        // The panel sizes its accessory view from the view's frame. Wide enough for long names.
        pullDown.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        setFrameSize(fittingSize)
    }
}
