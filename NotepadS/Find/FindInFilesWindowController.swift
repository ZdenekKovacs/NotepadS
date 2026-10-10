import AppKit
import NotepadSCore

/// Edit › Find › Find in Files… (⇧⌘F): searches every file in a folder, like Notepad++'s
/// Find in Files. Results are listed per file; clicking a result opens the file at that line.
///
/// The app is sandboxed, so it may only read a folder the user chose in the Open panel
/// ("Choose…"); that permission lasts until the app quits. The search runs on a background
/// thread and shows results as they come; "Stop" or a new search ends it.
final class FindInFilesWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate {

    static let shared = FindInFilesWindowController()

    /// Results stop here, so a search for "e" in a big folder stays usable.
    private static let maximumMatches = 10_000

    // MARK: Result model (classes: the outline view tracks its items by identity)

    private final class FileResult {
        let url: URL
        let displayPath: String
        var matches: [MatchResult] = []
        init(url: URL, displayPath: String) {
            self.url = url
            self.displayPath = displayPath
        }
    }

    private final class MatchResult {
        unowned let file: FileResult
        let match: LineMatch
        init(file: FileResult, match: LineMatch) {
            self.file = file
            self.match = match
        }
    }

    private var results: [FileResult] = []
    private var folderURL: URL?
    /// Increases with every search; a running search stops when it no longer matches.
    private var searchGeneration = 0
    private var isSearching = false

    // MARK: Controls

    private let findField = NSTextField()
    private let folderControl = NSPathControl()
    private let filterField = NSTextField()
    private let regexCheckbox = FindInFilesWindowController.checkbox(String(localized: "Regular expression", comment: "Find in Files option"))
    private let ignoreCaseCheckbox = FindInFilesWindowController.checkbox(String(localized: "Ignore case", comment: "Find in Files option"))
    private let subfoldersCheckbox = FindInFilesWindowController.checkbox(String(localized: "Include subfolders", comment: "Find in Files option"))
    private let hiddenCheckbox = FindInFilesWindowController.checkbox(String(localized: "Skip hidden files and folders", comment: "Find in Files option"))
    private let findButton = NSButton(title: String(localized: "Find All", comment: "Find in Files button"), target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let outlineView = NSOutlineView()

    private enum Key {
        static let filter = "FindInFilesFilter"
        static let regex = "FindInFilesRegex"
        static let ignoreCase = "FindInFilesIgnoreCase"
        static let subfolders = "FindInFilesSubfolders"
        static let skipHidden = "FindInFilesSkipHidden"
    }

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.title = String(localized: "Find in Files", comment: "Find in Files window title")
        window.contentMinSize = NSSize(width: 520, height: 320)
        window.isRestorable = false   // a tool window, not reopened at launch
        super.init(window: window)
        buildContent(in: window)
        loadOptions()
        window.setFrameAutosaveName("FindInFilesWindow")   // remembers position and size
        if !window.setFrameUsingName("FindInFilesWindow") {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window; a short one-line selection from the editor becomes the search text.
    /// `suggestedFolder` (the front document's folder) is where "Choose…" starts.
    func show(selectedText: String?, suggestedFolder: URL?) {
        if let selectedText, !selectedText.isEmpty, selectedText.count <= 200,
           !selectedText.utf8.contains(where: { $0 == 0x0A || $0 == 0x0D }) {
            findField.stringValue = selectedText
        }
        self.suggestedFolder = suggestedFolder
        showWindow(nil)
        window?.makeFirstResponder(findField)
    }

    private var suggestedFolder: URL?

    // MARK: - Folder

    @objc private func chooseFolder(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Find in Files: folder panel button")
        panel.message = String(localized: "Choose the folder to search.", comment: "Find in Files: folder panel message")
        panel.directoryURL = folderURL ?? suggestedFolder
        // The Open panel is the only way a sandboxed app gets access to a folder.
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.folderURL = url
            self.folderControl.url = url
            self.statusLabel.stringValue = ""
        }
    }

    // MARK: - Searching

    @objc private func findAll(_ sender: Any?) {
        if isSearching {
            stopSearch()
            return
        }
        saveOptions()
        guard let folderURL else {
            chooseFolder(nil)
            return
        }
        let search: TextSearch
        do {
            search = try TextSearch(pattern: findField.stringValue,
                                    options: SearchOptions(isRegularExpression: regexCheckbox.state == .on,
                                                           ignoresCase: ignoreCaseCheckbox.state == .on))
        } catch {
            report(error.localizedDescription)
            NSSound.beep()
            return
        }
        let options = FolderSearch.Options(filter: FileFilter(filterField.stringValue),
                                           includesSubfolders: subfoldersCheckbox.state == .on,
                                           skipsHiddenItems: hiddenCheckbox.state == .on)
        results = []
        outlineView.reloadData()
        searchGeneration += 1
        setSearching(true)
        report(String(localized: "Searching…", comment: "Find in Files status"))
        let generation = searchGeneration
        let folderPath = folderURL.standardizedFileURL.path

        // `TextSearch` isn't thread-safe to share, so the background thread uses its own copy.
        let pattern = findField.stringValue, searchOptions = search.options
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let search = try? TextSearch(pattern: pattern, options: searchOptions) else { return }
            let files = FolderSearch.files(in: folderURL, options: options)
            var batch: [(URL, String, [LineMatch])] = []
            var matchCount = 0
            var lastDelivery = Date()
            for (index, file) in files.enumerated() {
                // Stop as soon as a newer search started or the user pressed Stop.
                var isCurrent = false
                DispatchQueue.main.sync { isCurrent = self?.searchGeneration == generation }
                guard isCurrent else { return }

                if let data = try? Data(contentsOf: file, options: .mappedIfSafe),
                   let matches = FolderSearch.matches(in: data, search: search), !matches.isEmpty {
                    let kept = Array(matches.prefix(Self.maximumMatches - matchCount))
                    matchCount += kept.count
                    let path = file.standardizedFileURL.path
                    let display = path.hasPrefix(folderPath + "/") ? String(path.dropFirst(folderPath.count + 1)) : path
                    batch.append((file, display, kept))
                }
                let isLast = index == files.count - 1 || matchCount >= Self.maximumMatches
                // Deliver a few times a second, so the list fills while searching without
                // reloading for every file.
                if isLast || Date().timeIntervalSince(lastDelivery) > 0.2 {
                    let delivered = batch
                    batch = []
                    lastDelivery = Date()
                    let searched = index + 1
                    DispatchQueue.main.async {
                        self?.deliver(delivered, generation: generation, searchedFiles: searched,
                                      totalFiles: files.count, isFinished: isLast,
                                      isTruncated: matchCount >= Self.maximumMatches)
                    }
                }
                if matchCount >= Self.maximumMatches { return }
            }
            if files.isEmpty {
                DispatchQueue.main.async {
                    self?.deliver([], generation: generation, searchedFiles: 0, totalFiles: 0,
                                  isFinished: true, isTruncated: false)
                }
            }
        }
    }

    private func deliver(_ batch: [(URL, String, [LineMatch])], generation: Int, searchedFiles: Int,
                         totalFiles: Int, isFinished: Bool, isTruncated: Bool) {
        guard generation == searchGeneration else { return }
        let newFiles = batch.map { url, display, matches in
            let file = FileResult(url: url, displayPath: display)
            file.matches = matches.map { MatchResult(file: file, match: $0) }
            return file
        }
        if !newFiles.isEmpty {
            results += newFiles
            outlineView.reloadData()
            for file in newFiles {
                outlineView.expandItem(file)   // matches visible at once, as in Notepad++
            }
        }
        let matchCount = results.reduce(0) { $0 + $1.matches.count }
        if isFinished {
            setSearching(false)
            if matchCount == 0 {
                report(String(localized: "No matches in \(totalFiles) files.", comment: "Find in Files status"))
            } else if isTruncated {
                report(String(localized: "Stopped after \(matchCount) matches in \(results.count) files.",
                              comment: "Find in Files status: too many matches"))
            } else {
                report(String(localized: "\(matchCount) matches in \(results.count) files (\(totalFiles) searched).",
                              comment: "Find in Files status"))
            }
        } else {
            report(String(localized: "Searching… \(searchedFiles) of \(totalFiles) files, \(matchCount) matches",
                          comment: "Find in Files status while searching"))
        }
    }

    private func stopSearch() {
        searchGeneration += 1   // the background loop sees it and ends
        setSearching(false)
        let matchCount = results.reduce(0) { $0 + $1.matches.count }
        report(String(localized: "Stopped: \(matchCount) matches in \(results.count) files.", comment: "Find in Files status"))
    }

    private func setSearching(_ searching: Bool) {
        isSearching = searching
        findButton.title = searching
            ? String(localized: "Stop", comment: "Find in Files button while searching")
            : String(localized: "Find All", comment: "Find in Files button")
        if searching { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }

    private func report(_ message: String) {
        statusLabel.stringValue = message
    }

    // MARK: - Opening a result

    @objc private func resultClicked(_ sender: NSOutlineView) {
        let item = outlineView.item(atRow: outlineView.clickedRow)
        if let result = item as? MatchResult {
            open(result.file.url, line: result.match.line, rangeInLine: result.match.rangeInLine)
        } else if let file = item as? FileResult {
            // A click on a file shows or hides its matches; a double-click opens it.
            if NSApp.currentEvent?.clickCount == 2, let first = file.matches.first {
                open(file.url, line: first.match.line, rangeInLine: first.match.rangeInLine)
            } else if outlineView.isItemExpanded(file) {
                outlineView.collapseItem(file)
            } else {
                outlineView.expandItem(file)
            }
        }
    }

    /// Opens the file (or brings its window forward) and selects the match. The line and column
    /// are used rather than an offset in the file, so it also fits a document edited since.
    private func open(_ url: URL, line: Int, rangeInLine: NSRange) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                NSApp.presentError(error)
                return
            }
            // After the window has appeared and restored its own position.
            DispatchQueue.main.async {
                guard let editor = document?.windowControllers.first?.contentViewController as? EditorViewController else { return }
                editor.reveal(line: line, rangeInLine: rangeInLine)
            }
        }
    }

    // MARK: - Outline view

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let file = item as? FileResult { return file.matches.count }
        return item == nil ? results.count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let file = item as? FileResult { return file.matches[index] }
        return results[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is FileResult
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier)
        if let file = item as? FileResult {
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: file.url.path)
            cell.imageView?.isHidden = false
            let title = NSMutableAttributedString(string: file.displayPath,
                                                  attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)])
            title.append(NSAttributedString(string: "  \(file.matches.count)",
                                            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                         .foregroundColor: NSColor.secondaryLabelColor]))
            cell.textField?.attributedStringValue = title
            cell.toolTip = file.url.path
        } else if let result = item as? MatchResult {
            cell.imageView?.isHidden = true
            cell.textField?.attributedStringValue = Self.title(for: result.match)
            cell.toolTip = nil
        }
        return cell
    }

    /// "12  the line with the match", the line number in gray and the match highlighted.
    private static func title(for match: LineMatch) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .regular)
        let title = NSMutableAttributedString(string: "\(match.line + 1)  ",
                                              attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        // Tabs and leading spaces would push the match out of view in a one-line row.
        let text = match.lineText.replacingOccurrences(of: "\t", with: " ")
        let line = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if NSMaxRange(match.rangeInLineText) <= line.length {
            line.addAttributes([.backgroundColor: NSColor.findHighlightColor, .foregroundColor: NSColor.black],
                               range: match.rangeInLineText)
        }
        title.append(line)
        return title
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        for view in [image, text] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - Options

    private func loadOptions() {
        let defaults = UserDefaults.standard
        filterField.stringValue = defaults.string(forKey: Key.filter) ?? ""
        regexCheckbox.state = defaults.bool(forKey: Key.regex) ? .on : .off
        ignoreCaseCheckbox.state = (defaults.object(forKey: Key.ignoreCase) as? Bool ?? true) ? .on : .off
        subfoldersCheckbox.state = (defaults.object(forKey: Key.subfolders) as? Bool ?? true) ? .on : .off
        hiddenCheckbox.state = (defaults.object(forKey: Key.skipHidden) as? Bool ?? true) ? .on : .off
    }

    private func saveOptions() {
        let defaults = UserDefaults.standard
        defaults.set(filterField.stringValue, forKey: Key.filter)
        defaults.set(regexCheckbox.state == .on, forKey: Key.regex)
        defaults.set(ignoreCaseCheckbox.state == .on, forKey: Key.ignoreCase)
        defaults.set(subfoldersCheckbox.state == .on, forKey: Key.subfolders)
        defaults.set(hiddenCheckbox.state == .on, forKey: Key.skipHidden)
    }

    // MARK: - Layout

    private static func checkbox(_ title: String) -> NSButton {
        NSButton(checkboxWithTitle: title, target: nil, action: nil)
    }

    private func buildContent(in window: NSWindow) {
        findField.placeholderString = String(localized: "Text to find", comment: "Find in Files field")
        // Return starts the search: the Find All button has Return as its key equivalent.
        filterField.placeholderString = String(localized: "All files — or e.g. *.swift *.py !*.min.js !build",
                                               comment: "Find in Files: file filter placeholder")
        filterField.toolTip = String(localized: "Separate patterns with spaces. * matches anything, ? one character. Start a pattern with ! to skip matching files and folders.",
                                     comment: "Find in Files: file filter tooltip")
        folderControl.pathStyle = .standard
        folderControl.isEditable = false
        folderControl.placeholderString = String(localized: "No folder chosen", comment: "Find in Files: folder placeholder")
        let chooseButton = NSButton(title: String(localized: "Choose…", comment: "Find in Files: choose folder button"),
                                    target: self, action: #selector(chooseFolder(_:)))
        findButton.target = self
        findButton.action = #selector(findAll(_:))
        findButton.keyEquivalent = "\r"
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)   // pushes Find All to the right

        let folderRow = NSStackView(views: [folderControl, chooseButton])
        folderRow.spacing = 8
        folderControl.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let options = NSStackView(views: [regexCheckbox, ignoreCaseCheckbox, subfoldersCheckbox, hiddenCheckbox])
        options.spacing = 14
        let grid = NSGridView(views: [
            [label(String(localized: "Find:", comment: "Find in Files label")), findField],
            [label(String(localized: "Folder:", comment: "Find in Files label")), folderRow],
            [label(String(localized: "Files:", comment: "Find in Files label")), filterField],
            [NSGridCell.emptyContentView, options],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8

        let buttonRow = NSStackView(views: [progress, statusLabel, findButton])
        buttonRow.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Result"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 20
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(resultClicked(_:))
        outlineView.style = .plain
        outlineView.usesAlternatingRowBackgroundColors = true
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let content = NSView()
        for view in [grid, buttonRow, scrollView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttonRow.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            buttonRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttonRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
        window.contentView = content
        window.initialFirstResponder = findField
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }
}
