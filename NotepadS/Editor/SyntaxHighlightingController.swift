import AppKit
import NotepadSCore

/// Colors the visible text of one editor with the document's language.
///
/// Colors are **temporary attributes** of the layout manager, not attributes of the text
/// storage: they only affect drawing, so they never mark the document as edited, never create
/// undo steps and are never saved.
///
/// Only the visible lines are colored, after each edit and while scrolling. `Highlighter`
/// (Core) keeps the tokenizer state at every line start, so coloring line 5 000 doesn't mean
/// re-reading the file from the top each time.
final class SyntaxHighlightingController {

    /// Above these sizes highlighting turns off: TextKit 1 gets slow with very long lines,
    /// and computing line states for a huge file would make scrolling stutter.
    static let maximumTextLength = 10_000_000   // UTF-16 units, about 10 MB of mostly ASCII text
    static let maximumLineLength = 20_000

    private let layoutManager: NSLayoutManager
    private weak var textView: NSTextView?
    private let text: NSTextStorage
    private let lineIndexProvider: () -> LineIndex

    private(set) var language: Language = .plainText
    /// True when the file is too large or has a too-long line (shown in the status bar).
    private(set) var isTurnedOffForSize = false
    private var highlighter: Highlighter?
    private var isRecolorScheduled = false

    /// Called when `language` or `isTurnedOffForSize` changed.
    var onStateChanged: (() -> Void)?

    init(layoutManager: NSLayoutManager, textView: NSTextView, text: NSTextStorage,
         lineIndexProvider: @escaping () -> LineIndex) {
        self.layoutManager = layoutManager
        self.textView = textView
        self.text = text
        self.lineIndexProvider = lineIndexProvider
    }

    /// Switches language and recolors everything.
    func setLanguage(_ language: Language) {
        self.language = language
        restart()
    }

    /// Starts over after the whole text was replaced (opened, reverted, reopened).
    func restart() {
        let lineIndex = lineIndexProvider()
        isTurnedOffForSize = text.length > Self.maximumTextLength
            || (0..<lineIndex.lineCount).contains { lineIndex.fullRange(ofLine: $0).length > Self.maximumLineLength }
        if let grammar = language.grammar, !isTurnedOffForSize {
            highlighter = Highlighter(grammar: grammar, lineCount: lineIndex.lineCount)
        } else {
            highlighter = nil
        }
        removeAllColors()
        scheduleRecolor()
        onStateChanged?()
    }

    /// Call for every text change, with the lines `LineIndex` reported.
    func textDidChange(_ change: LineChange) {
        let lineIndex = lineIndexProvider()
        let hasLongLine = (change.firstLine...change.newLastLine).contains {
            lineIndex.fullRange(ofLine: $0).length > Self.maximumLineLength
        }
        if highlighter != nil && (hasLongLine || text.length > Self.maximumTextLength) {
            // Too big now: stop until the document is reopened or another language is chosen.
            highlighter = nil
            isTurnedOffForSize = true
            removeAllColors()
            onStateChanged?()
            return
        }
        highlighter?.linesChanged(change)
        scheduleRecolor()
    }

    /// Call when the visible part of the text changed (scrolling, resizing, wrapping).
    func visibleTextDidChange() {
        scheduleRecolor()
    }

    // MARK: - Coloring

    /// Coalesces many requests (each keystroke, each scroll step) into one recoloring, done
    /// right after the current event, when the text system has finished its own work.
    private func scheduleRecolor() {
        guard highlighter != nil, !isRecolorScheduled else { return }
        isRecolorScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecolorScheduled = false
            self.recolorVisibleLines()
        }
    }

    private func recolorVisibleLines() {
        guard let highlighter, let textView, let textContainer = textView.textContainer else { return }
        let lineIndex = lineIndexProvider()
        guard highlighter.lineCount == lineIndex.lineCount else { return }   // an edit is still being processed

        // The characters visible in the text view (the same calculation as the line-number gutter).
        var visibleRect = textView.visibleRect
        visibleRect.origin.x -= textView.textContainerOrigin.x
        visibleRect.origin.y -= textView.textContainerOrigin.y
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let firstLine = lineIndex.line(containing: visibleCharacters.location)
        let lastLine = lineIndex.line(containing: NSMaxRange(visibleCharacters))
        let start = lineIndex.lineStart(of: firstLine)
        let linesRange = NSRange(location: start, length: NSMaxRange(lineIndex.fullRange(ofLine: lastLine)) - start)

        let tokens = highlighter.tokens(forLines: firstLine..<(lastLine + 1), in: text.mutableString, lineIndex: lineIndex)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: linesRange)
        for token in tokens {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: SyntaxTheme.color(for: token.scope),
                                                forCharacterRange: token.range)
        }
    }

    private func removeAllColors() {
        layoutManager.removeTemporaryAttribute(.foregroundColor,
                                               forCharacterRange: NSRange(location: 0, length: text.length))
    }
}
