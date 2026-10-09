import AppKit
import NotepadSCore

/// The text view, configured as a plain-text code editor.
///
/// Create it only with `init(frame:textContainer:)` and a container that belongs to an
/// `NSLayoutManager` (see EditorViewController). That makes it TextKit 1 from the start.
/// Never create it with `init(frame:)` or `NSTextView.scrollableTextView()`: on macOS 12+
/// those build a TextKit 2 view, which silently falls back to TextKit 1 the first time
/// anything touches `layoutManager`.
///
/// Later phases add behaviour here (auto-indent, invisible characters, Go to Line).
/// Multiple cursors are in EditorTextView+MultipleCursors.swift.
final class EditorTextView: NSTextView {

    // MARK: - Multiple cursors (state; behaviour in EditorTextView+MultipleCursors.swift)

    /// Every cursor, sorted, while there is more than one (VS Code-style multiple cursors);
    /// empty otherwise. NSTextView itself can't do this: it keeps only one caret, and typing
    /// into several selections changes only the first. So NSTextView shows the primary cursor
    /// as its own selection, and this view draws, moves and edits the others.
    var cursors: [Cursor] = []
    /// The cursor NSTextView shows (and scrolls to): the one added last.
    var primaryCursorIndex = 0
    /// Column for Add Cursor Above/Below: where the first cursor was, so a column of cursors
    /// stays straight across shorter lines.
    var columnForAddedCursors = 0
    /// True while this view changes the selection itself; any other selection change (a click,
    /// Select All, Undo) goes back to a single cursor.
    var isUpdatingCursors = false
    /// Applies edits at several cursors after the edit gatekeeper's checks.
    weak var multiCursorDelegate: EditorTextViewMultiCursorDelegate?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureForPlainText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Focus

    /// Called when this view gets the keyboard focus (a split editor's pane was clicked).
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onBecomeFirstResponder?() }
        return accepted
    }

    // MARK: - Multiple cursors: NSTextView methods that need to know about them

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !isUpdatingCursors, !cursors.isEmpty {
            cursors = []   // a click, Select All, Undo …: one cursor again
            setNeedsDisplay(visibleRect)
        }
    }

    override func copy(_ sender: Any?) {
        guard hasMultipleCursors else {
            super.copy(sender)
            return
        }
        if !copySelectionsAtEveryCursor() { NSSound.beep() }
    }

    override func cut(_ sender: Any?) {
        guard adoptMultipleSelections() else {
            super.cut(sender)
            return
        }
        cutAtEveryCursor()
    }

    override func paste(_ sender: Any?) {
        guard adoptMultipleSelections() else {
            super.paste(sender)
            return
        }
        pasteAtEveryCursor()
    }

    /// Input methods (accents with a dead key, Japanese …) compose text at one place only.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        removeExtraCursors()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    // `drawBackground(in:)` runs before the text is drawn, `draw(_:)` around it: selections of
    // the other cursors go under the text, their carets on top.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if hasMultipleCursors { drawSelectionsOfOtherCursors() }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if hasMultipleCursors { drawCaretsOfOtherCursors() }
    }

    // MARK: - Line breaks

    /// The line break the editor inserts: the document's style (set by EditorViewController).
    var lineBreakToInsert: LineEnding = .lf

    // NSTextView maps Enter, ⌥Enter, ⌃Enter and similar keys to these four actions. By default
    // they insert "\n", or the Unicode line/paragraph separators U+2028/U+2029, which don't
    // belong in a plain-text file. All of them insert the document's line break instead.
    // `insertText` goes through the normal edit path, so undo and the delegate work as for typing.

    override func insertNewline(_ sender: Any?) {
        insertLineBreakOfDocumentStyle()
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        insertLineBreakOfDocumentStyle()
    }

    override func insertLineBreak(_ sender: Any?) {
        insertLineBreakOfDocumentStyle()
    }

    override func insertParagraphSeparator(_ sender: Any?) {
        insertLineBreakOfDocumentStyle()
    }

    /// Inserts the document's line break, followed by the current line's indentation when
    /// auto-indent is on (Settings).
    private func insertLineBreakOfDocumentStyle() {
        let selection = selectedRange()
        let indentation = EditorDefaults.autoIndents ? leadingWhitespace(ofLineBefore: selection.location) : ""
        insertText(lineBreakToInsert.string + indentation, replacementRange: selection)
    }

    /// Spaces and tabs at the start of the line containing `location`, up to `location`.
    func leadingWhitespace(ofLineBefore location: Int) -> String {
        let text = textStorage?.mutableString ?? NSMutableString()
        var lineStart = location
        while lineStart > 0 {
            let unit = text.character(at: lineStart - 1)
            if unit == 0x0A || unit == 0x0D { break }
            lineStart -= 1
        }
        var end = lineStart
        while end < location, [0x20, 0x09].contains(text.character(at: end)) {
            end += 1
        }
        return text.substring(with: NSRange(location: lineStart, length: end - lineStart))
    }

    // MARK: - Tab key

    /// With "Insert spaces when pressing Tab" (Settings), Tab inserts spaces up to the next tab
    /// stop. A tab character in the line counts as reaching its tab stop.
    override func insertTab(_ sender: Any?) {
        guard EditorDefaults.insertsSpacesForTab else {
            super.insertTab(sender)
            return
        }
        let selection = selectedRange()
        insertText(tabText(at: selection.location), replacementRange: selection)
    }

    /// What Tab inserts at `location`: a tab character, or with "Insert spaces when pressing
    /// Tab" the spaces up to the next tab stop.
    func tabText(at location: Int) -> String {
        guard EditorDefaults.insertsSpacesForTab else { return "\t" }
        let text = textStorage?.mutableString ?? NSMutableString()
        let tabWidth = EditorDefaults.tabWidth
        var lineStart = location
        while lineStart > 0, ![0x0A, 0x0D].contains(text.character(at: lineStart - 1)) {
            lineStart -= 1
        }
        var column = 0
        for index in lineStart..<location {
            column = text.character(at: index) == 0x09 ? (column / tabWidth + 1) * tabWidth : column + 1
        }
        return String(repeating: " ", count: tabWidth - column % tabWidth)
    }

    // MARK: - Overwrite mode

    /// Overwrite (OVR) instead of insert (INS) mode, set by EditorViewController. NSTextView has
    /// no overwrite mode of its own, so `insertText` below widens the replaced range. The caret
    /// turns orange as a reminder.
    var isOverwriteMode = false {
        didSet { insertionPointColor = isOverwriteMode ? .systemOrange : .textColor }
    }

    // Typing reaches `insertText(_:replacementRange:)` with `NSNotFound` as the range, meaning
    // "replace the selection". Only that case overwrites: our own calls (Return, Tab as spaces,
    // the edit gatekeeper) pass an explicit range, and Paste doesn't come through here at all,
    // so they still insert. Return and Tab never overwrite, as in Notepad++.
    // Accents typed with a dead key (⌥E, then E) are marked text first; they insert.
    // The replacement goes through `shouldChangeText` like any typing, so the gatekeeper,
    // undo ("Typing", coalesced as usual) and the "edited" state work unchanged.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if replacementRange.location == NSNotFound, !hasMarkedText(), adoptMultipleSelections() {
            typeAtEveryCursor(typed)
            return
        }
        let selection = selectedRange()
        guard isOverwriteMode, replacementRange.location == NSNotFound, !hasMarkedText(),
              selection.length == 0, !typed.isEmpty,
              !typed.utf8.contains(where: { $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }),
              let text = textStorage?.mutableString else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let replaced = Overwrite.rangeReplaced(byTyping: typed.count, at: selection.location, in: text)
        super.insertText(string, replacementRange: replaced)
    }

    /// The Insert key switches between insert and overwrite mode. Mac keyboards have no Insert
    /// key; on a PC keyboard connected to a Mac it arrives as the Help key (NSHelpFunctionKey).
    override func keyDown(with event: NSEvent) {
        let otherModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad])
        if otherModifiers.isEmpty,
           let key = event.charactersIgnoringModifiers?.unicodeScalars.first.map({ Int($0.value) }),
           key == NSHelpFunctionKey || key == NSInsertFunctionKey {
            // EditorViewController owns the mode; it is further up the responder chain.
            if tryToPerform(#selector(EditorViewController.toggleOverwriteMode(_:)), with: self) {
                return
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Setup

    private func configureForPlainText() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFontPanel = false
        usesInspectorBar = false
        // Our line-number gutter is the scroll view's ruler. With `usesRuler` on, NSTextView
        // would put paragraph/tab markers into it.
        usesRuler = false

        // Built-in find bar (⌘F) with live highlighting of matches.
        usesFindBar = true
        isIncrementalSearchingEnabled = true

        // Never change what the user typed.
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextCompletionEnabled = false
        smartInsertDeleteEnabled = false
        inlinePredictionType = .no                       // macOS 14: grey inline word predictions
        if #available(macOS 15.0, *) {
            writingToolsBehavior = .none                 // macOS 15: Apple Intelligence Writing Tools
        }

        drawsBackground = true
        backgroundColor = .textBackgroundColor           // semantic colors follow Light/Dark mode
        insertionPointColor = .textColor
        textContainerInset = NSSize(width: 0, height: 4)
    }
}
