import AppKit
import NotepadSCore

/// The editor for one document: text view, line-number gutter, minimap and status bar.
///
///     view
///     ├─ scrollView (NSScrollView)
///     │   ├─ documentView: textView (EditorTextView, TextKit 1)
///     │   └─ verticalRulerView: lineNumberView (LineNumberRulerView)
///     ├─ minimapView (MinimapView), right of the scroll view; can be hidden
///     └─ statusBar (StatusBarView)
///
/// Text flow: the document owns the NSTextStorage. Every change to it (typing, undo, paste,
/// revert) posts `didProcessEditingNotification`; we update `lineIndex` incrementally there.
final class EditorViewController: NSViewController {

    let document: TextDocument

    private let layoutManager: InvisiblesLayoutManager
    private let textView: EditorTextView
    private let scrollView = NSScrollView()
    private let statusBar = StatusBarView(frame: .zero)
    private var lineNumberView: LineNumberRulerView!
    private var minimapView: MinimapView!
    /// The minimap's width: `MinimapView.width` when shown, 0 when hidden.
    private var minimapWidthConstraint: NSLayoutConstraint!
    private var highlighting: SyntaxHighlightingController!
    /// True once the user picked a language in the status bar; it then sticks for this window.
    private var isLanguageChosenByUser = false

    /// Where each line starts; shared with the gutter and the status bar.
    private var lineIndex = LineIndex()
    private var fontSize = EditorDefaults.fontSize
    private var wrapsLines = EditorDefaults.wrapsLines
    // `unowned self`: the counters belong to this controller and never outlive it.
    /// Characters in the whole document, for the status bar ("Characters").
    private lazy var documentCharacterCounter = LiveCharacterCounter(
        source: { [unowned self] in
            let text = self.document.textStorage.mutableString
            return (text, text.length)
        },
        didCountInBackground: { [weak self] in self?.updateStatusBar() })
    /// Characters before the caret, for the status bar ("Pos").
    private lazy var caretPositionCounter = LiveCharacterCounter(
        source: { [unowned self] in
            (self.document.textStorage.mutableString, self.textView.selectedRange().location)
        },
        didCountInBackground: { [weak self] in self?.updateStatusBar() })
    /// Overwrite mode (OVR): typing replaces the characters after the caret. Per window, starts off.
    private var isOverwriteMode = false
    /// Font settings the text currently uses, to notice when the Settings window changes them.
    private var appliedFontSettings = ""
    /// True while one of our own commands changes the text; the gatekeeper lets it through.
    private var isPerformingProgrammaticEdit = false

    init(document: TextDocument) {
        self.document = document

        // Build the TextKit 1 stack explicitly: storage → layout manager → container → view.
        // Because the container belongs to an NSLayoutManager, the text view is TextKit 1 from
        // the start, and using `layoutManager` later can never trigger a TextKit 2 fallback.
        let layoutManager = InvisiblesLayoutManager()
        // Lay out only what is visible (plus a margin). This is what keeps multi-MB files fast.
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.showsInvisibles = EditorDefaults.showsInvisibles
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
        applyWordWrap()

        // The gutter must be created after the text view is inside the scroll view.
        lineNumberView = LineNumberRulerView(textView: textView) { [unowned self] in self.lineIndex }
        highlighting = SyntaxHighlightingController(layoutManager: layoutManager, textView: textView,
                                                    text: document.textStorage) { [unowned self] in self.lineIndex }
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        minimapView = MinimapView(text: document.textStorage, scrollView: scrollView,
                                  lineIndexProvider: { [unowned self] in self.lineIndex },
                                  visibleCharactersProvider: { [unowned self] in self.visibleCharacterRange() },
                                  tokensProvider: { [unowned self] lines in self.highlighting.tokens(forLines: lines) })
        minimapWidthConstraint = minimapView.widthAnchor.constraint(equalToConstant: 0)
        applyMinimapVisibility(EditorDefaults.showsMinimap)

        // Delegates last: their callbacks use the gutter and the status bar.
        textView.delegate = self
        textView.multiCursorDelegate = self
        statusBar.delegate = self

        for subview in [scrollView, minimapView, statusBar] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: minimapView.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            minimapView.topAnchor.constraint(equalTo: root.topAnchor),
            minimapView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            minimapView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            minimapWidthConstraint,
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
        document.onSettingsChanged = { [weak self] in self?.documentSettingsDidChange() }
        document.onFileURLChanged = { [weak self] in self?.documentFileDidChange() }
        NotificationCenter.default.addObserver(self, selector: #selector(documentTextDidProcessEditing(_:)),
                                               name: NSTextStorage.didProcessEditingNotification,
                                               object: document.textStorage)

        // Recolor when other text becomes visible: scrolling moves the clip view's bounds,
        // resizing or re-wrapping changes the text view's frame. (The gutter already asked both
        // views to post these notifications.)
        NotificationCenter.default.addObserver(self, selector: #selector(visibleTextDidChange(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(visibleTextDidChange(_:)),
                                               name: NSView.frameDidChangeNotification, object: textView)

        // The Settings window writes to UserDefaults; follow font and tab-width changes live.
        NotificationCenter.default.addObserver(self, selector: #selector(userDefaultsDidChange(_:)),
                                               name: UserDefaults.didChangeNotification, object: nil)

        lineIndex.rebuild(from: document.textStorage.mutableString)
        applyFont()
        lineNumberView.lineCountDidChange(lineIndex.lineCount)
        statusBar.setWrapsLines(wrapsLines)
        updateCharacterCount()
        documentSettingsDidChange()
        highlighting.onStateChanged = { [weak self] in
            self?.updateLanguageInStatusBar()
            self?.minimapView.syntaxDidChange()   // another language, or highlighting turned off
        }
        document.editorPositionProvider = { [weak self] in self?.currentPosition() }
        document.onRestoreEditorPosition = { [weak self] position in self?.restore(position) }
        highlighting.setLanguage(detectedLanguage())
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        if let position = document.takePendingEditorPosition() {
            restore(position)
        }
    }

    // MARK: - Caret and scroll position across relaunches

    /// The current caret, selection and scroll position, for window restoration.
    private func currentPosition() -> TextDocument.EditorPosition {
        TextDocument.EditorPosition(selection: textView.selectedRange(),
                                    firstVisibleCharacter: visibleCharacterRange().location)
    }

    private func restore(_ position: TextDocument.EditorPosition) {
        let length = document.textStorage.length
        // The file may have changed since the position was saved: stay inside the text.
        let location = min(position.selection.location, length)
        let selection = NSRange(location: location, length: min(position.selection.length, length - location))
        let firstCharacter = min(position.firstVisibleCharacter, length)
        guard firstCharacter < length else {
            textView.setSelectedRange(selection)
            return
        }

        // When the window is first drawn, the layout manager resizes the text view to the real
        // text height and then scrolls the *selection* into view (AppKit does this by itself).
        // With the caret elsewhere, that would undo the restored scroll position. So until that
        // first drawing is done, park the caret on the top visible line, then put the real
        // selection back (setting a selection doesn't scroll) and correct the scroll once more.
        textView.setSelectedRange(NSRange(location: firstCharacter, length: 0))
        scrollToTop(character: firstCharacter)
        DispatchQueue.main.async { [weak self] in
            guard let self, NSMaxRange(selection) <= self.document.textStorage.length,
                  firstCharacter < self.document.textStorage.length else { return }
            self.scrollToTop(character: firstCharacter)
            self.textView.setSelectedRange(selection)
        }
    }

    /// Scrolls so that the line containing `character` is at the top of the visible area.
    ///
    /// With non-contiguous layout (on for speed), the layout manager only estimates the height of
    /// text it hasn't laid out yet. Scrolling to a line's position can therefore land a few lines
    /// off, because laying out the newly visible text corrects the estimates. Each round below
    /// measures where the line really is now and scrolls again; it settles after a round or two.
    private func scrollToTop(character: Int) {
        let clipView = scrollView.contentView
        let glyph = layoutManager.glyphIndexForCharacter(at: character)
        for _ in 0..<4 {
            layoutManager.ensureLayout(forGlyphRange: NSRange(location: glyph, length: 1))
            let lineFragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            // Line fragments are in text-container coordinates, offset by `textContainerOrigin`.
            // Scroll the clip view directly, keeping its x origin: it extends under the gutter
            // (its bounds start at a negative x), which `NSView.scroll(_:)` doesn't account for.
            let target = NSPoint(x: clipView.bounds.origin.x, y: lineFragment.minY + textView.textContainerOrigin.y)
            clipView.scroll(to: clipView.constrainBoundsRect(NSRect(origin: target, size: clipView.bounds.size)).origin)
            scrollView.reflectScrolledClipView(clipView)
            if visibleCharacterRange().location >= lineFragmentStart(ofGlyph: glyph) { break }
        }
    }

    /// The first character of the line fragment containing `glyph`.
    private func lineFragmentStart(ofGlyph glyph: Int) -> Int {
        var fragmentGlyphs = NSRange()
        layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentGlyphs)
        return layoutManager.characterIndexForGlyph(at: fragmentGlyphs.location)
    }

    /// The characters currently visible in the text view.
    private func visibleCharacterRange() -> NSRange {
        guard let textContainer = textView.textContainer else { return NSRange(location: 0, length: 0) }
        var visibleRect = textView.visibleRect
        visibleRect.origin.x -= textView.textContainerOrigin.x
        visibleRect.origin.y -= textView.textContainerOrigin.y
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }

    // MARK: - Word wrap (View menu)

    @objc func toggleWordWrap(_ sender: Any?) {
        wrapsLines.toggle()
        EditorDefaults.wrapsLines = wrapsLines   // new windows start with the last choice
        applyWordWrap()
        statusBar.setWrapsLines(wrapsLines)
    }

    /// Wrap on: the text container is as wide as the text view, which follows the visible width.
    /// Wrap off: the container is practically infinitely wide, so lines never break, and the text
    /// view grows sideways with the longest line; the horizontal scroller appears.
    /// (Apple's "Text System User Interface Layer" guide describes both setups.)
    private func applyWordWrap() {
        guard let textContainer = textView.textContainer else { return }
        // FLT_MAX, not CGFloat.greatestFiniteMagnitude: TextKit 1 computes with Float precision
        // in places and misbehaves with larger widths.
        let unlimited = CGFloat(Float.greatestFiniteMagnitude)
        scrollView.hasHorizontalScroller = !wrapsLines
        textView.isHorizontallyResizable = !wrapsLines
        textContainer.widthTracksTextView = wrapsLines
        if wrapsLines {
            // The visible width, without the part of the clip view under the line-number gutter.
            let clipView = scrollView.contentView
            let visibleWidth = clipView.frame.width - clipView.contentInsets.left - clipView.contentInsets.right
            textView.setFrameSize(NSSize(width: visibleWidth, height: textView.frame.height))
            textContainer.containerSize = NSSize(width: textView.frame.width, height: unlimited)
        } else {
            textContainer.containerSize = NSSize(width: unlimited, height: unlimited)
        }
        // Let the text view take its new size from the laid-out text right away.
        textView.sizeToFit()
        lineNumberView?.needsDisplay = true
    }

    // MARK: - Minimap (View menu)

    @objc func toggleMinimap(_ sender: Any?) {
        applyMinimapVisibility(minimapView.isHidden)
        EditorDefaults.showsMinimap = !minimapView.isHidden   // new windows start the same
    }

    /// A hidden view still takes its place in Auto Layout, so the width goes to 0 as well;
    /// the scroll view (pinned to the minimap's left edge) then gets the whole width.
    /// With word wrap on, the text re-wraps to the new width by itself: the text view
    /// follows the clip view's width (autoresizing mask), and the container follows the text view.
    private func applyMinimapVisibility(_ isVisible: Bool) {
        minimapView.isHidden = !isVisible
        minimapWidthConstraint.constant = isVisible ? MinimapView.width : 0
    }

    // MARK: - Go to Line (Edit menu)

    @objc func goToLine(_ sender: Any?) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        askForLine(in: window, message: nil)
    }

    /// Shows the Go to Line sheet. `message` explains why the previous input was rejected.
    private func askForLine(in window: NSWindow, message: String?) {
        let lineCount = lineIndex.lineCount
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = String(localized: "Line number", comment: "Go to Line: text field placeholder")

        let alert = NSAlert()
        alert.messageText = String(localized: "Go to Line", comment: "Go to Line dialog title")
        alert.informativeText = message
            ?? String(localized: "Enter a line number from 1 to \(lineCount).", comment: "Go to Line dialog")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Go", comment: "Go to Line dialog button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Dialog button"))
        // Typing goes straight into the field.
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let line = LineNumberInput.line(from: field.stringValue, lineCount: self.lineIndex.lineCount) else {
                NSSound.beep()
                // A sheet can't present another one while it is still closing; ask again next turn.
                DispatchQueue.main.async {
                    self.askForLine(in: window, message: String(localized: "“\(field.stringValue)” isn’t a line number from 1 to \(self.lineIndex.lineCount).",
                                                                comment: "Go to Line dialog: invalid input"))
                }
                return
            }
            self.moveCaret(toLine: line)
        }
    }

    /// Puts the caret at the start of `line` and scrolls it to the middle of the window.
    private func moveCaret(toLine line: Int) {
        textView.setSelectedRange(NSRange(location: lineIndex.lineStart(of: line), length: 0))
        textView.centerSelectionInVisibleArea(nil)
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Text menu: transformations and hashes

    /// Text › Format JSON, Base64 Encode, snake_case, Sort Lines … The menu item carries the
    /// transformation's raw value. Works on the selection, or on the whole document when
    /// nothing is selected; line-based transformations work on the whole selected lines.
    @objc func applyTextTransform(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let transform = TextTransform(rawValue: rawValue) else { return }
        let range = transform == .joinLines ? joinLinesRange() : targetRange(lineBased: transform.isLineBased)
        let original = document.textStorage.mutableString.substring(with: range)
        let context = transformContext
        do {
            let result = try transform.apply(to: original, context: context)
            guard result != original else { return }   // nothing to change, no undo step
            replaceText(in: range, with: result, actionName: transform.name)
        } catch let error as TransformError {
            showTransformError(error, transformName: transform.name, startingAt: range.location)
        } catch {
            showError(error)
        }
    }

    private var transformContext: TransformContext {
        TransformContext(lineEnding: document.lineEnding, locale: Self.textLocale,
                         indentation: EditorDefaults.insertsSpacesForTab
                             ? String(repeating: " ", count: EditorDefaults.tabWidth) : "\t",
                         tabWidth: EditorDefaults.tabWidth)
    }

    /// The language rules for sorting and case conversion: the language the app's interface is
    /// shown in (English for now), not the Mac's region. With a Czech region, `Locale.current`
    /// would sort "ch" as its own letter after "h", which English users wouldn't expect. Once
    /// the app is translated, each user automatically gets the rules of their language.
    private static let textLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    /// Text › Hash › Copy SHA-256 … Copies the hash of the selection, or of the whole document.
    @objc func copyHash(_ sender: NSMenuItem) {
        guard let hash = hash(for: sender), let digest = digest(hash) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(digest, forType: .string)
    }

    /// Text › Hash › Replace Selection with SHA-256 …
    @objc func replaceSelectionWithHash(_ sender: NSMenuItem) {
        let selection = textView.selectedRange()
        guard selection.length > 0, let hash = hash(for: sender), let digest = digest(hash) else { return }
        replaceText(in: selection, with: digest,
                    actionName: String(localized: "Replace with \(hash.name)", comment: "Undo action name; e.g. SHA-256"))
    }

    private func hash(for menuItem: NSMenuItem) -> TextHash? {
        (menuItem.representedObject as? String).flatMap(TextHash.init(rawValue:))
    }

    /// The hash of the selection's UTF-8 bytes, or of the bytes Save would write for the whole
    /// document (encoding, BOM and line breaks included), so it matches `shasum` on the file.
    private func digest(_ hash: TextHash) -> String? {
        let selection = textView.selectedRange()
        let storage = document.textStorage
        if selection.length > 0 {
            return hash.hexDigest(of: Data(storage.mutableString.substring(with: selection).utf8))
        }
        // Can't fail: every character in the document fits its encoding (invariant 2).
        guard let bytes = try? TextFile.encode(storage.string, encoding: document.encoding) else { return nil }
        return hash.hexDigest(of: bytes)
    }

    // MARK: - Text › Lines: commands on the caret's lines

    @objc func duplicateLines(_ sender: Any?) {
        runLineCommand(.duplicate, actionName: String(localized: "Duplicate Line", comment: "Undo action name"))
    }

    @objc func deleteLines(_ sender: Any?) {
        runLineCommand(.delete, actionName: String(localized: "Delete Line", comment: "Undo action name"))
    }

    @objc func moveLinesUp(_ sender: Any?) {
        runLineCommand(.moveUp, actionName: String(localized: "Move Line Up", comment: "Undo action name"))
    }

    @objc func moveLinesDown(_ sender: Any?) {
        runLineCommand(.moveDown, actionName: String(localized: "Move Line Down", comment: "Undo action name"))
    }

    /// Runs a line command (NotepadSCore computes the edit) as one undo step.
    private func runLineCommand(_ command: LineCommand, actionName: String) {
        guard let edit = command.edit(in: document.textStorage.mutableString, lineIndex: lineIndex,
                                      selection: textView.selectedRange(), lineEnding: document.lineEnding) else {
            NSSound.beep()   // e.g. moving the first line up
            return
        }
        replaceText(in: edit.range, with: edit.replacement, actionName: actionName, selectionAfter: edit.selection)
    }

    /// Join Lines without a selection, or with one inside a single line, joins that line with
    /// the next one, as in other editors; otherwise it joins the selected lines. (Joining the
    /// whole document into one line is never what a caret on one line means.)
    private func joinLinesRange() -> NSRange {
        let range = targetRange(lineBased: true)
        let selection = textView.selectedRange()
        let firstLine = lineIndex.line(containing: selection.location)
        let lastLine = selection.length > 0 ? lineIndex.line(containing: NSMaxRange(selection) - 1) : firstLine
        guard firstLine == lastLine else { return range }
        guard firstLine + 1 < lineIndex.lineCount else { return lineIndex.fullRange(ofLine: firstLine) }
        let start = lineIndex.lineStart(of: firstLine)
        return NSRange(location: start, length: NSMaxRange(lineIndex.fullRange(ofLine: firstLine + 1)) - start)
    }

    /// The last width typed into Split Lines, offered again next time (this run of the app only).
    private static var splitWidth = 80

    /// Text › Lines › Split Lines…: asks for the maximum line length, then splits the selected
    /// lines (all lines if nothing is selected) at spaces.
    @objc func splitLines(_ sender: Any?) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        askForSplitWidth(in: window, message: nil)
    }

    private func askForSplitWidth(in window: NSWindow, message: String?) {
        let maximum = 10_000
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = String(Self.splitWidth)

        let alert = NSAlert()
        alert.messageText = String(localized: "Split Lines", comment: "Split Lines dialog title")
        alert.informativeText = message
            ?? String(localized: "Split lines longer than this many characters at spaces:", comment: "Split Lines dialog")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Split", comment: "Split Lines dialog button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Dialog button"))
        alert.window.initialFirstResponder = field

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            guard let width = LineNumberInput.number(from: field.stringValue, maximum: maximum) else {
                NSSound.beep()
                // A sheet can't present another one while it is still closing; ask again next turn.
                DispatchQueue.main.async {
                    self.askForSplitWidth(in: window, message: String(localized: "“\(field.stringValue)” isn’t a number from 1 to \(maximum).",
                                                                      comment: "Split Lines dialog: invalid input"))
                }
                return
            }
            Self.splitWidth = width
            let range = self.targetRange(lineBased: true)
            let original = self.document.textStorage.mutableString.substring(with: range)
            let result = LineTools.split(original, width: width, context: self.transformContext)
            guard result != original else { return }
            self.replaceText(in: range, with: result,
                             actionName: String(localized: "Split Lines", comment: "Undo action name"))
        }
    }

    /// The selection, the whole document if nothing is selected, and for line-based
    /// transformations the whole lines the selection touches (including the last line's break).
    private func targetRange(lineBased: Bool) -> NSRange {
        let selection = textView.selectedRange()
        let length = document.textStorage.length
        guard selection.length > 0 else { return NSRange(location: 0, length: length) }
        guard lineBased else { return selection }
        let firstLine = lineIndex.line(containing: selection.location)
        // A selection ending right after a line break doesn't include the next line.
        let lastLine = lineIndex.line(containing: NSMaxRange(selection) - 1)
        let start = lineIndex.lineStart(of: firstLine)
        return NSRange(location: start, length: NSMaxRange(lineIndex.fullRange(ofLine: lastLine)) - start)
    }

    /// Replaces `range` with `text` as one undo step named `actionName`, and selects the result
    /// (or sets `selectionAfter`, if given). If the document's encoding can't store the new text,
    /// asks to convert to UTF-8 first.
    func replaceText(in range: NSRange, with text: String, actionName: String, selectionAfter: NSRange? = nil) {
        if let character = document.rejectionReason(forInserting: text) {
            offerConversionToUTF8(character: character) { [weak self] in
                guard let self, NSMaxRange(range) <= self.document.textStorage.length else { return }
                self.performReplacement(in: range, with: text, actionName: actionName, selectionAfter: selectionAfter)
            }
            return
        }
        performReplacement(in: range, with: text, actionName: actionName, selectionAfter: selectionAfter)
    }

    private func performReplacement(in range: NSRange, with text: String, actionName: String, selectionAfter: NSRange?) {
        let hadSelection = textView.selectedRange().length > 0
        let caret = textView.selectedRange().location
        textView.breakUndoCoalescing()
        // shouldChangeText/didChangeText record the change for undo and mark the document
        // edited, like typing. The text is ready, so the gatekeeper lets it through unchanged.
        isPerformingProgrammaticEdit = true
        if textView.shouldChangeText(in: range, replacementString: text) {
            document.textStorage.replaceCharacters(in: range, with: text)
            textView.didChangeText()
        }
        isPerformingProgrammaticEdit = false
        document.undoManager?.setActionName(actionName)

        let newLength = (text as NSString).length
        if let selectionAfter, NSMaxRange(selectionAfter) <= document.textStorage.length {
            textView.setSelectedRange(selectionAfter)
            textView.scrollRangeToVisible(selectionAfter)   // a moved line may leave the window
        } else if hadSelection {
            textView.setSelectedRange(NSRange(location: range.location, length: newLength))
        } else {
            textView.setSelectedRange(NSRange(location: min(caret, document.textStorage.length), length: 0))
        }
    }

    /// Shows why a transformation failed, with the position translated from the transformed
    /// text to the document (line and column as in the status bar).
    private func showTransformError(_ error: TransformError, transformName: String, startingAt offset: Int) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Can’t apply “\(transformName)”.", comment: "Transformation error title")
        var details = error.message
        if let line = error.line, let column = error.column {
            let firstLine = lineIndex.line(containing: offset)
            let documentLine = firstLine + line
            // On the first line, columns count from where the transformed text starts.
            let documentColumn = line == 1 ? lineIndex.column(of: offset, in: document.textStorage.mutableString) - 1 + column
                                           : column
            details = String(localized: "Line \(documentLine), column \(documentColumn): \(error.message)",
                             comment: "Transformation error with its position in the document")
        }
        alert.informativeText = String(localized: "\(details)\n\nThe text wasn’t changed.",
                                       comment: "Transformation error: the reason, then a note that nothing changed")
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    // MARK: - Find and replace with regular expressions (used by FindReplacePanelController)

    @objc func showRegexFindPanel(_ sender: Any?) {
        let selection = textView.selectedRange()
        let selected = selection.length > 0 ? document.textStorage.mutableString.substring(with: selection) : nil
        FindReplacePanelController.shared.show(selectedText: selected)
    }

    /// The document's text, without copying it.
    var searchableText: NSString { document.textStorage.mutableString }
    var currentSelection: NSRange { textView.selectedRange() }
    var documentLineEnding: LineEnding { document.lineEnding }

    /// Selects a match, scrolls to it and briefly highlights it, as the find bar does.
    func showMatch(_ range: NSRange) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    // MARK: - Invisible characters (View menu)

    @objc func toggleInvisibles(_ sender: Any?) {
        layoutManager.showsInvisibles.toggle()
        EditorDefaults.showsInvisibles = layoutManager.showsInvisibles   // new windows start the same
    }

    // MARK: - Settings

    /// What `applyFont()` depends on, as one comparable value.
    private var currentFontSettings: String {
        "\(EditorDefaults.fontName)|\(EditorDefaults.fontSize)|\(EditorDefaults.tabWidth)"
    }

    /// UserDefaults posts this for every change in the app (also unrelated ones), so only
    /// re-apply the font when one of its settings really changed.
    @objc private func userDefaultsDidChange(_ notification: Notification) {
        guard currentFontSettings != appliedFontSettings else { return }
        fontSize = EditorDefaults.fontSize
        applyFont()
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
        let font = EditorDefaults.font(ofSize: fontSize)
        appliedFontSettings = currentFontSettings
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
        minimapView.needsDisplay = true   // the tab width may have changed
    }

    // MARK: - Text changes

    // Not named `textStorageDidProcessEditing(_:)`: since the macOS 26 SDK, NSViewController
    // has a method with that name, and a private method can't override it.
    @objc private func documentTextDidProcessEditing(_ notification: Notification) {
        let storage = document.textStorage
        guard storage.editedMask.contains(.editedCharacters) else { return }   // ignore font/color changes

        let previousLineCount = lineIndex.lineCount
        // `mutableString` avoids copying the whole text, which `storage.string` would do.
        let change = lineIndex.applyEditReportingLines(editedRange: storage.editedRange,
                                                       changeInLength: storage.changeInLength,
                                                       in: storage.mutableString)
        highlighting.textDidChange(change)
        lineNumberView.needsDisplay = true
        minimapView.textDidChange(change)
        updateCharacterCount()

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
        minimapView.needsDisplay = true
        updateCharacterCount()
        documentSettingsDidChange()   // reading the file may have changed the line-break style
        if isLanguageChosenByUser {
            highlighting.restart()
        } else {
            highlighting.setLanguage(detectedLanguage())
        }
    }

    // MARK: - Syntax highlighting

    /// The language from the file name, or from a `#!` line for files without a known extension.
    private func detectedLanguage() -> Language {
        let firstLineRange = lineIndex.contentRange(ofLine: 0)
        // Only the start of the first line matters; never copy a huge first line.
        let firstLine = document.textStorage.mutableString.substring(
            with: NSRange(location: 0, length: min(firstLineRange.length, 200)))
        return Language.detect(fileName: document.fileURL?.lastPathComponent, firstLine: firstLine)
    }

    /// Saved under a new name (e.g. an untitled document saved as "script.py"): pick the
    /// language for the new name, unless the user chose one in the status bar.
    private func documentFileDidChange() {
        updateStatusBar()   // "Reopen with Encoding" needs a file
        let language = detectedLanguage()
        guard !isLanguageChosenByUser, language != highlighting.language else { return }
        highlighting.setLanguage(language)
    }

    @objc private func visibleTextDidChange(_ notification: Notification) {
        highlighting.visibleTextDidChange()
        minimapView.needsDisplay = true   // the slider follows the visible text
        document.invalidateRestorableState()   // the scroll position is part of the saved state
    }

    private func updateLanguageInStatusBar() {
        statusBar.setLanguage(highlighting.language,
                              isHighlightingOff: highlighting.isTurnedOffForSize && highlighting.language.grammar != nil)
    }

    /// The document's encoding or line-break style changed.
    private func documentSettingsDidChange() {
        textView.lineBreakToInsert = document.lineEnding
        updateStatusBar()
    }

    // MARK: - Overwrite mode (Edit menu, status bar, Insert key)

    /// Switches between insert (INS) and overwrite (OVR) mode for this window.
    @objc func toggleOverwriteMode(_ sender: Any?) {
        isOverwriteMode.toggle()
        textView.isOverwriteMode = isOverwriteMode
        statusBar.setOverwriteMode(isOverwriteMode)
    }

    // MARK: - Line endings

    /// "Convert Line Endings": rewrites every line break as `lineEnding` and makes it the style
    /// for new breaks. Text and style change in one undo group, so one ⌘Z restores the
    /// original (possibly mixed) line breaks exactly.
    private func convertLineEndings(to lineEnding: LineEnding) {
        let storage = document.textStorage
        let original = storage.string
        let converted = LineEnding.convertAll(original, to: lineEnding)
        guard converted != original || lineEnding != document.lineEnding,
              let undoManager = document.undoManager else { return }

        // Don't merge this step with the typing before it.
        textView.breakUndoCoalescing()
        undoManager.beginUndoGrouping()
        document.setLineEnding(lineEnding)
        if converted != original {
            let caret = textView.selectedRange().location
            let fullRange = NSRange(location: 0, length: storage.length)
            // shouldChangeText/didChangeText make NSTextView record the change for undo and
            // mark the document edited, exactly like typing.
            isPerformingProgrammaticEdit = true
            if textView.shouldChangeText(in: fullRange, replacementString: converted) {
                storage.replaceCharacters(in: fullRange, with: converted)
                textView.didChangeText()
            }
            isPerformingProgrammaticEdit = false
            textView.setSelectedRange(NSRange(location: min(caret, storage.length), length: 0))
        }
        undoManager.setActionName(String(localized: "Convert Line Endings", comment: "Undo action name"))
        undoManager.endUndoGrouping()
    }

    // MARK: - Status bar

    private func updateStatusBar() {
        let text = document.textStorage.mutableString
        let selection = textView.selectedRange()
        let caret = min(selection.location, text.length)
        statusBar.update(
            line: lineIndex.line(containing: caret) + 1,
            column: lineIndex.column(of: caret, in: text),
            position: caretPositionCounter.count.map { $0 + 1 },   // 1-based, like Ln and Col
            selectedCharacters: characterCount(in: selection, of: text),
            lineCount: lineIndex.lineCount,
            characterCount: documentCharacterCounter.count,
            encoding: document.encoding,
            lineEndingCounts: lineIndex.counts,
            newLineEnding: document.lineEnding,
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

    /// Recounts the document's characters and those before the caret after a change (see
    /// LiveCharacterCounter: right away for small documents, on a background copy for large ones).
    private func updateCharacterCount() {
        documentCharacterCounter.recount()
        caretPositionCounter.recount()
        updateStatusBar()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    /// Invariant 2: new text contains `character`, which the document's encoding can't store.
    /// Nothing has been inserted. Asks whether to convert the document to UTF-8; if the user
    /// agrees, converts and then runs `insert`, both as one undo step.
    private func offerConversionToUTF8(character: UnencodableCharacter, thenPerform insert: @escaping () -> Void) {
        guard let window = view.window, window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let characterName = String(character.character)
        let encodingName = document.encoding.displayName
        // Present after the current editing event has finished. The sheet is window-modal,
        // so the user can't edit the text meanwhile and `range` stays valid.
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "“\(characterName)” can’t be saved in \(encodingName).",
                                       comment: "Dialog title; character in quotes, then encoding name")
            alert.informativeText = String(localized: "Convert the document to UTF-8 to insert it. One Undo reverts both.",
                                           comment: "Unsupported-character dialog")
            // First button = default (Return), second = Esc.
            alert.addButton(withTitle: String(localized: "Convert to UTF-8 and Insert", comment: "Unsupported-character dialog button"))
            alert.addButton(withTitle: String(localized: "Cancel", comment: "Dialog button"))
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                self?.convertToUTF8(thenPerform: insert)
            }
        }
    }

    /// Converts the document to UTF-8 and runs `insert`, as one undo step.
    private func convertToUTF8(thenPerform insert: () -> Void) {
        guard let undoManager = document.undoManager else { return }
        textView.breakUndoCoalescing()
        undoManager.beginUndoGrouping()
        do {
            try document.convert(to: .utf8)   // UTF-8 can store any text, so this doesn't throw
            insert()
        } catch {
            showError(error)
        }
        undoManager.setActionName(String(localized: "Convert to UTF-8", comment: "Undo action name"))
        undoManager.endUndoGrouping()
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {

    /// Gatekeeper for every user edit (typing, paste, drop, find & replace) — enforces the
    /// document invariants before anything reaches the text storage.
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        guard let replacement = replacementString, !replacement.isEmpty else { return true }

        // Our own commands prepare their text themselves. Undo and redo restore earlier text
        // exactly; converting it here would make ⌘Z after "Convert Line Endings" lose the
        // original line breaks.
        if isPerformingProgrammaticEdit {
            return true
        }
        if let undoManager = textView.undoManager, undoManager.isUndoing || undoManager.isRedoing {
            return true
        }

        // Invariant 2: never accept characters the document's encoding can't save. Insert
        // nothing now; the dialog offers to convert the document to UTF-8 and then insert.
        if let character = document.rejectionReason(forInserting: replacement) {
            // The sheet is window-modal, so the text can't change before the user decides and
            // `affectedCharRange` stays valid. Inserting goes through this gatekeeper again: the
            // text then passes the encoding check, and its line breaks get the document's style.
            offerConversionToUTF8(character: character) { [weak self, weak textView] in
                guard let self, let textView,
                      NSMaxRange(affectedCharRange) <= self.document.textStorage.length else { return }
                textView.insertText(replacement, replacementRange: affectedCharRange)
            }
            return false
        }

        // Invariant 1: line breaks the user inserts (paste, drop) use the document's style;
        // existing breaks are never touched. If the text needs converting, cancel this change and
        // insert the converted copy instead (it comes back here, passes, and is recorded for
        // undo like normal typing). Check bytes, not Characters: in Swift "\r\n" is one Character.
        if replacement.utf8.contains(where: { $0 == 0x0A || $0 == 0x0D }) {
            let converted = LineEnding.convertAll(replacement, to: document.lineEnding)
            if converted != replacement {
                textView.insertText(converted, replacementRange: affectedCharRange)
                return false
            }
        }
        return true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        caretPositionCounter.recount()
        updateStatusBar()
        document.invalidateRestorableState()   // AppKit saves the new caret position soon
        lineNumberView.needsDisplay = true   // the highlighted current-line number may change
    }

    func textDidChange(_ notification: Notification) {
        updateStatusBar()
    }
}

// MARK: - EditorTextViewMultiCursorDelegate

extension EditorViewController: EditorTextViewMultiCursorDelegate {

    /// The edit gatekeeper for typing at several cursors (the single-cursor one is
    /// `textView(_:shouldChangeTextIn:replacementString:)`). Line breaks already have the
    /// document's style; here only the encoding is checked (invariant 2).
    func textView(_ textView: EditorTextView, perform edit: MultiCursorEdit, actionName: String) {
        let apply = { [weak self, weak textView] in
            guard let self, let textView else { return }
            // NSTextView passes a multi-range change to the single-range gatekeeper as one range
            // with the text in between; that text is already in the document, so let it through.
            self.isPerformingProgrammaticEdit = true
            textView.applyMultiCursorEdit(edit, actionName: actionName)
            self.isPerformingProgrammaticEdit = false
        }
        if let character = document.rejectionReason(forInserting: edit.replacements.map(\.string).joined()) {
            offerConversionToUTF8(character: character, thenPerform: apply)
            return
        }
        apply()
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
        alert.messageText = String(localized: "Reopen with \(encoding.displayName)?", comment: "Dialog title")
        alert.informativeText = String(localized: "Unsaved changes will be discarded and the file will be read again from disk.",
                                       comment: "Reopen-with-encoding dialog")
        alert.addButton(withTitle: String(localized: "Reopen", comment: "Dialog button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Dialog button"))
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

    func statusBar(_ statusBar: StatusBarView, didSelect language: Language) {
        isLanguageChosenByUser = true
        highlighting.setLanguage(language)
    }

    func statusBar(_ statusBar: StatusBarView, convertLineEndingsTo lineEnding: LineEnding) {
        convertLineEndings(to: lineEnding)
    }

    func statusBarDidToggleWordWrap(_ statusBar: StatusBarView) {
        toggleWordWrap(statusBar)
    }

    func statusBarDidToggleOverwriteMode(_ statusBar: StatusBarView) {
        toggleOverwriteMode(statusBar)
        view.window?.makeFirstResponder(textView)   // keep typing in the text after the click
    }

    private func reopen(with encoding: TextEncoding) {
        do {
            try document.reopen(with: encoding)
        } catch {
            showError(error)
        }
    }
}

// MARK: - NSMenuItemValidation

extension EditorViewController: NSMenuItemValidation {

    /// AppKit asks before showing a menu; we use it to put a checkmark on toggles.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWordWrap(_:)) {
            menuItem.state = wrapsLines ? .on : .off
        } else if menuItem.action == #selector(toggleInvisibles(_:)) {
            menuItem.state = layoutManager.showsInvisibles ? .on : .off
        } else if menuItem.action == #selector(toggleMinimap(_:)) {
            menuItem.state = minimapView.isHidden ? .off : .on
        } else if menuItem.action == #selector(toggleOverwriteMode(_:)) {
            menuItem.state = isOverwriteMode ? .on : .off
        } else if menuItem.action == #selector(copyHash(_:)), let hash = hash(for: menuItem) {
            // Say what is hashed: risk 9 in DESIGN.md.
            menuItem.title = textView.selectedRange().length > 0
                ? String(localized: "Copy \(hash.name) of Selection", comment: "Text › Hash menu item")
                : String(localized: "Copy \(hash.name) of Document", comment: "Text › Hash menu item")
        } else if menuItem.action == #selector(replaceSelectionWithHash(_:)) {
            return textView.selectedRange().length > 0
        }
        return true
    }
}
