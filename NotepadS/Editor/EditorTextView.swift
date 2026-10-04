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
final class EditorTextView: NSTextView {

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configureForPlainText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
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

    private func insertLineBreakOfDocumentStyle() {
        insertText(lineBreakToInsert.string, replacementRange: selectedRange())
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
