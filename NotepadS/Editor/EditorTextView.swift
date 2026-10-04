import AppKit

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
