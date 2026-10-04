import AppKit
import NotepadSCore

/// The editor for one document: text view, line-number gutter and status bar.
///
///     view
///     ├─ scrollView (NSScrollView)
///     │   ├─ documentView: textView (EditorTextView, TextKit 1)
///     │   └─ verticalRulerView: lineNumberView (LineNumberRulerView)
///     └─ statusBar (StatusBarView)
///
/// Text flow: the document owns the NSTextStorage. Every change to it (typing, undo, paste,
/// revert) posts `didProcessEditingNotification`; we update `lineIndex` incrementally there.
final class EditorViewController: NSViewController {

    let document: TextDocument

    private let layoutManager: NSLayoutManager
    private let textView: EditorTextView
    private let scrollView = NSScrollView()
    private let statusBar = StatusBarView(frame: .zero)
    private var lineNumberView: LineNumberRulerView!

    /// Where each line starts; shared with the gutter and the status bar.
    private var lineIndex = LineIndex()
    private var fontSize = EditorDefaults.fontSize

    init(document: TextDocument) {
        self.document = document

        // Build the TextKit 1 stack explicitly: storage → layout manager → container → view.
        // Because the container belongs to an NSLayoutManager, the text view is TextKit 1 from
        // the start, and using `layoutManager` later can never trigger a TextKit 2 fallback.
        let layoutManager = NSLayoutManager()
        // Lay out only what is visible (plus a margin). This is what keeps multi-MB files fast.
        layoutManager.allowsNonContiguousLayout = true
        document.textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true   // word wrap at the view width
        layoutManager.addTextContainer(textContainer)

        self.layoutManager = layoutManager
        self.textView = EditorTextView(frame: .zero, textContainer: textContainer)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View setup

    override func loadView() {
        let size = NSSize(width: 900, height: 650)
        let root = NSView(frame: NSRect(origin: .zero, size: size))

        // Apple's recipe for a text view in a scroll view: give both a real initial size, let
        // the text view grow vertically and track the visible width through autoresizing.
        scrollView.frame = NSRect(x: 0, y: StatusBarView.height,
                                  width: size.width, height: size.height - StatusBarView.height)
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        // The gutter must be created after the text view is inside the scroll view.
        lineNumberView = LineNumberRulerView(textView: textView) { [unowned self] in self.lineIndex }
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        // Delegates last: their callbacks use the gutter and the status bar.
        textView.delegate = self
        statusBar.delegate = self

        for subview in [scrollView, statusBar] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        assert(textView.textLayoutManager == nil, "The editor must use TextKit 1 (see CLAUDE.md).")

        document.onTextReplaced = { [weak self] in self?.documentTextWasReplaced() }
        document.onSettingsChanged = { [weak self] in self?.updateStatusBar() }
        NotificationCenter.default.addObserver(self, selector: #selector(textStorageDidProcessEditing(_:)),
                                               name: NSTextStorage.didProcessEditingNotification,
                                               object: document.textStorage)

        lineIndex.rebuild(from: document.textStorage.mutableString)
        applyFont()
        lineNumberView.lineCountDidChange(lineIndex.lineCount)
        updateStatusBar()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Font size (View menu; reached through the responder chain)

    @objc func increaseFontSize(_ sender: Any?) {
        setFontSize(fontSize + 1)
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        setFontSize(fontSize - 1)
    }

    @objc func resetFontSize(_ sender: Any?) {
        setFontSize(EditorDefaults.defaultFontSize)
    }

    private func setFontSize(_ size: CGFloat) {
        fontSize = min(max(size, EditorDefaults.minimumFontSize), EditorDefaults.maximumFontSize)
        EditorDefaults.fontSize = fontSize   // new windows start with the last chosen size
        applyFont()
    }

    /// Applies font, color and tab width to the whole text and to newly typed text.
    /// Attribute changes are not edits: no undo step, the document stays unmodified.
    private func applyFont() {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        // Tab stops every `tabWidth` spaces (NSTextView's default is every 28 points).
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = spaceWidth * CGFloat(EditorDefaults.tabWidth)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,   // dynamic color: follows Light/Dark mode
            .paragraphStyle: paragraphStyle,
        ]
        textView.font = font
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = attributes

        let storage = document.textStorage
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()

        lineNumberView.textFontDidChange(font)
    }

    // MARK: - Text changes

    @objc private func textStorageDidProcessEditing(_ notification: Notification) {
        let storage = document.textStorage
        guard storage.editedMask.contains(.editedCharacters) else { return }   // ignore font/color changes

        let previousLineCount = lineIndex.lineCount
        // `mutableString` avoids copying the whole text, which `storage.string` would do.
        lineIndex.applyEdit(editedRange: storage.editedRange,
                            changeInLength: storage.changeInLength,
                            in: storage.mutableString)
        lineNumberView.needsDisplay = true

        if lineIndex.lineCount != previousLineCount {
            // Resizing the gutter re-tiles the scroll view. Don't do that while the text system
            // is still processing this edit; do it right after.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lineNumberView.lineCountDidChange(self.lineIndex.lineCount)
            }
        }
    }

    /// The document re-read its file (revert, external change, reopen with encoding).
    private func documentTextWasReplaced() {
        applyFont()   // text read from disk has no attributes yet
        let caret = min(textView.selectedRange().location, document.textStorage.length)
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        lineNumberView.needsDisplay = true
        updateStatusBar()
    }

    // MARK: - Status bar

    private func updateStatusBar() {
        let text = document.textStorage.mutableString
        let selection = textView.selectedRange()
        let caret = min(selection.location, text.length)
        statusBar.update(
            line: lineIndex.line(containing: caret) + 1,
            column: lineIndex.column(of: caret, in: text),
            selectedCharacters: characterCount(in: selection, of: text),
            encoding: document.encoding,
            lineEnding: document.lineEnding,
            hadMixedLineEndings: document.hadMixedLineEndings,
            canReopen: document.fileURL != nil
        )
    }

    /// Selection size in user-perceived characters. Counting them is O(n), so very large
    /// selections show UTF-16 units instead (close enough, and instant).
    private func characterCount(in range: NSRange, of text: NSString) -> Int {
        guard range.length > 0, NSMaxRange(range) <= text.length else { return 0 }
        guard range.length <= 200_000 else { return range.length }
        return text.substring(with: range).count
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func showInsertionRejected(_ message: String) {
        NSSound.beep()
        guard let window = view.window, window.attachedSheet == nil else { return }
        // Present after the current editing event has finished.
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Character not supported by the current encoding"
            alert.informativeText = message
            alert.beginSheetModal(for: window)
        }
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {

    /// Gatekeeper for every user edit (typing, paste, drop, find & replace) — enforces the
    /// document invariants before anything reaches the text storage.
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard let replacement = replacementString, !replacement.isEmpty else { return true }

        // Invariant 2: never accept characters the document's encoding can't save.
        if let reason = document.rejectionReason(forInserting: replacement) {
            showInsertionRejected(reason)
            return false
        }

        // Invariant 1: the storage contains only LF. Pasted or dropped text may contain CRLF/CR;
        // insert a normalized copy instead (registered for undo like normal typing).
        // Check bytes, not Characters: in Swift "\r\n" is a single Character.
        if replacement.utf8.contains(0x0D) {
            textView.insertText(LineEnding.normalizeToLF(replacement), replacementRange: affectedCharRange)
            return false
        }
        return true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateStatusBar()
        lineNumberView.needsDisplay = true   // the highlighted current-line number may change
    }

    func textDidChange(_ notification: Notification) {
        updateStatusBar()
    }
}

// MARK: - StatusBarViewDelegate

extension EditorViewController: StatusBarViewDelegate {

    func statusBar(_ statusBar: StatusBarView, reopenWith encoding: TextEncoding) {
        guard document.fileURL != nil else { return }
        guard document.isDocumentEdited, let window = view.window else {
            reopen(with: encoding)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Reopen with \(encoding.displayName)?"
        alert.informativeText = "Unsaved changes will be discarded and the file will be read again from disk."
        alert.addButton(withTitle: "Reopen")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.reopen(with: encoding)
            }
        }
    }

    func statusBar(_ statusBar: StatusBarView, convertTo encoding: TextEncoding) {
        do {
            try document.convert(to: encoding)
        } catch {
            showError(error)
        }
    }

    func statusBar(_ statusBar: StatusBarView, didSelect lineEnding: LineEnding) {
        document.setLineEnding(lineEnding)
    }

    private func reopen(with encoding: TextEncoding) {
        do {
            try document.reopen(with: encoding)
        } catch {
            showError(error)
        }
    }
}
