import AppKit
import NotepadSCore

/// File › Compare With: two texts side by side with their differences colored, like the
/// Compare plugin of Notepad++. Removed lines are red on the left, added lines green on the
/// right, changed lines yellow with the changed characters marked; equal lines stay level, and
/// both sides scroll together. The window only shows the texts; it never changes them.
final class CompareWindowController: NSWindowController, NSWindowDelegate {

    /// What one side shows: an open document (its current, possibly unsaved text) or a file.
    enum Source {
        case document(TextDocument)
        case file(URL)

        var title: String {
            switch self {
            case .document(let document): return document.displayName
            case .file(let url): return url.lastPathComponent
            }
        }

        /// The lines, without their breaks.
        func lines() throws -> [String] {
            switch self {
            case .document(let document):
                return TextLines(document.textStorage.string).lines.map(\.content)
            case .file(let url):
                return TextLines(try TextFile.decode(Data(contentsOf: url)).text).lines.map(\.content)
            }
        }
    }

    /// Open compare windows; each keeps itself alive until it is closed.
    private static var openWindows: [CompareWindowController] = []

    private let left: Source
    private let right: Source
    private var diff = TextDiff(left: [], right: [])
    /// The difference shown last with Next/Previous.
    private var currentDifference = -1

    private let leftView = CompareTextView.make()
    private let rightView = CompareTextView.make()
    private let leftScrollView = NSScrollView()
    private let rightScrollView = NSScrollView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let whitespaceCheckbox = NSButton(checkboxWithTitle: String(localized: "Ignore whitespace", comment: "Compare option"),
                                              target: nil, action: nil)
    private let caseCheckbox = NSButton(checkboxWithTitle: String(localized: "Ignore case", comment: "Compare option"),
                                        target: nil, action: nil)
    /// True while one side follows the other's scrolling, so they don't echo each other.
    private var isSyncingScroll = false

    /// Opens a compare window for `left` and `right`.
    static func show(left: Source, right: Source) {
        let controller = CompareWindowController(left: left, right: right)
        openWindows.append(controller)
        controller.showWindow(nil)
        controller.compare()
    }

    private init(left: Source, right: Source) {
        self.left = left
        self.right = right
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: true)
        window.title = String(localized: "\(left.title) ↔ \(right.title)", comment: "Compare window title: the two names")
        window.contentMinSize = NSSize(width: 600, height: 300)
        window.isRestorable = false
        window.tabbingMode = .disallowed   // not a tab among the documents
        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func windowWillClose(_ notification: Notification) {
        Self.openWindows.removeAll { $0 === self }
    }

    // MARK: - Comparing

    @objc private func compare() {
        let leftLines: [String], rightLines: [String]
        do {
            leftLines = try left.lines()
            rightLines = try right.lines()
        } catch {
            summaryLabel.stringValue = error.localizedDescription
            return
        }
        let options = TextDiff.Options(ignoresWhitespace: whitespaceCheckbox.state == .on,
                                       ignoresCase: caseCheckbox.state == .on)
        diff = TextDiff(left: leftLines, right: rightLines, options: options)
        let view = diff.sideBySide(left: leftLines, right: rightLines)

        // Characters that differ within changed lines.
        var leftChanges: [Int: [NSRange]] = [:], rightChanges: [Int: [NSRange]] = [:]
        for (row, kind) in view.kinds.enumerated() where kind == .changed {
            let ranges = TextDiff.changedRanges(left: view.left.lines[row], right: view.right.lines[row])
            leftChanges[row] = ranges.left
            rightChanges[row] = ranges.right
        }
        let font = EditorDefaults.font(ofSize: EditorDefaults.fontSize)
        let leftFillers = Set(view.left.lineNumbers.indices.filter { view.left.lineNumbers[$0] == nil })
        let rightFillers = Set(view.right.lineNumbers.indices.filter { view.right.lineNumbers[$0] == nil })
        leftView.show(lines: view.left.lines, kinds: view.kinds, fillers: leftFillers, changedRanges: leftChanges,
                      font: font, isLeft: true)
        rightView.show(lines: view.right.lines, kinds: view.kinds, fillers: rightFillers, changedRanges: rightChanges,
                       font: font, isLeft: false)
        (leftScrollView.verticalRulerView as? CompareGutterView)?.lineNumbers = view.left.lineNumbers
        (rightScrollView.verticalRulerView as? CompareGutterView)?.lineNumbers = view.right.lineNumbers
        currentDifference = -1
        showSummary()
    }

    private func showSummary() {
        let counts = diff.counts
        if diff.isIdentical {
            summaryLabel.stringValue = String(localized: "The texts are identical.", comment: "Compare summary")
            return
        }
        let blocks = diff.differenceStarts.count
        summaryLabel.stringValue = String(localized: "\(blocks) differences: \(counts.changed) lines changed, \(counts.removed) removed, \(counts.added) added",
                                          comment: "Compare summary; removed = only on the left, added = only on the right")
    }

    // MARK: - Next and previous difference

    @objc private func nextDifference(_ sender: Any?) {
        move(by: 1)
    }

    @objc private func previousDifference(_ sender: Any?) {
        move(by: -1)
    }

    private func move(by step: Int) {
        let starts = diff.differenceStarts
        guard !starts.isEmpty else {
            NSSound.beep()
            return
        }
        currentDifference = (currentDifference + step + starts.count) % starts.count   // wraps around
        let row = starts[currentDifference]
        if let rect = leftView.rect(ofRow: row) {
            // Show the difference a few rows below the top, so what comes before is visible too.
            let target = NSPoint(x: leftScrollView.contentView.bounds.origin.x, y: max(0, rect.minY - rect.height * 3))
            leftScrollView.contentView.scroll(to: target)
            leftScrollView.reflectScrolledClipView(leftScrollView.contentView)
        }
        summaryLabel.stringValue = String(localized: "Difference \(currentDifference + 1) of \(starts.count)",
                                          comment: "Compare: position in the list of differences")
    }

    // MARK: - Scrolling together

    @objc private func clipViewDidScroll(_ notification: Notification) {
        guard !isSyncingScroll, let source = notification.object as? NSClipView else { return }
        let target = source === leftScrollView.contentView ? rightScrollView : leftScrollView
        isSyncingScroll = true
        target.contentView.scroll(to: source.bounds.origin)
        target.reflectScrolledClipView(target.contentView)
        isSyncingScroll = false
    }

    // MARK: - Layout

    private func buildContent(in window: NSWindow) {
        let previous = NSButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: nil)!,
                                target: self, action: #selector(previousDifference(_:)))
        previous.toolTip = String(localized: "Previous difference (⌥⌘↑)", comment: "Compare button tooltip")
        previous.keyEquivalent = String(Character(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!))
        previous.keyEquivalentModifierMask = [.option, .command]
        let next = NSButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)!,
                            target: self, action: #selector(nextDifference(_:)))
        next.toolTip = String(localized: "Next difference (⌥⌘↓)", comment: "Compare button tooltip")
        next.keyEquivalent = String(Character(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!))
        next.keyEquivalentModifierMask = [.option, .command]
        // (The `!` above: SF Symbols that ship with macOS, and function-key characters, always exist.)
        for checkbox in [whitespaceCheckbox, caseCheckbox] {
            checkbox.target = self
            checkbox.action = #selector(compare)
        }
        let refresh = NSButton(title: String(localized: "Refresh", comment: "Compare button: compare again"),
                               target: self, action: #selector(compare))
        refresh.toolTip = String(localized: "Compare again, for example after editing one of the documents.",
                                 comment: "Compare button tooltip")
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [previous, next, summaryLabel, whitespaceCheckbox, caseCheckbox, refresh])
        bar.spacing = 10

        let leftTitle = titleLabel(left.title), rightTitle = titleLabel(right.title)
        let leftColumn = NSStackView(views: [leftTitle, leftScrollView])
        let rightColumn = NSStackView(views: [rightTitle, rightScrollView])
        for column in [leftColumn, rightColumn] {
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 4
        }
        for (scrollView, textView) in [(leftScrollView, leftView), (rightScrollView, rightView)] {
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = true
            scrollView.borderType = .bezelBorder
            // Apple's setup for text that doesn't wrap: the view follows the visible size and
            // grows with the text (see "Text System User Interface Layer").
            textView.minSize = .zero
            textView.autoresizingMask = [.width, .height]
            // The gutter must be created after the text view is inside the scroll view.
            scrollView.verticalRulerView = CompareGutterView(textView: textView)
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipViewDidScroll(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            scrollView.widthAnchor.constraint(equalTo: (scrollView === leftScrollView ? leftColumn : rightColumn).widthAnchor).isActive = true
        }

        let columns = NSStackView(views: [leftColumn, rightColumn])
        columns.distribution = .fillEqually
        columns.spacing = 8

        let content = NSView()
        for view in [bar, columns] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            columns.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10),
            columns.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            columns.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            columns.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        window.contentView = content
    }

    private func titleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
