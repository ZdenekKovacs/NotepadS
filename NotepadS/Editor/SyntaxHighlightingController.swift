import AppKit
import NotepadSCore

/// Colors the visible text of an editor's panes (one, or two when split) with the document's language.
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

    /// A pane to color. Temporary attributes belong to a layout manager, so each pane (with its
    /// own layout manager) is colored separately; the tokenizer state is shared.
    private struct View {
        let layoutManager: NSLayoutManager
        weak var textView: NSTextView?
    }

    private var views: [View] = []
    private let text: NSTextStorage
    private let lineIndexProvider: () -> LineIndex

    private(set) var language = SyntaxLanguage.plainText
    /// True when the file is too large or has a too-long line (shown in the status bar).
    private(set) var isTurnedOffForSize = false
    private var highlighter: Highlighter?
    private var isRecolorScheduled = false

    /// Called when `language` or `isTurnedOffForSize` changed.
    var onStateChanged: (() -> Void)?

    init(text: NSTextStorage, lineIndexProvider: @escaping () -> LineIndex) {
        self.text = text
        self.lineIndexProvider = lineIndexProvider
    }

    /// Starts coloring a pane.
    func addView(layoutManager: NSLayoutManager, textView: NSTextView) {
        views.append(View(layoutManager: layoutManager, textView: textView))
        scheduleRecolor()
    }

    /// Stops coloring a pane (its split was closed).
    func removeView(_ textView: NSTextView) {
        views.removeAll { $0.textView === textView || $0.textView == nil }
    }

    /// Switches language and recolors everything.
    func setLanguage(_ language: SyntaxLanguage) {
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

    /// Tokens of `lines` for the minimap, with ranges from the start of the text;
    /// nil when the text isn't highlighted (plain text, or turned off for size).
    func tokens(forLines lines: Range<Int>) -> [SyntaxToken]? {
        guard let highlighter else { return nil }
        let lineIndex = lineIndexProvider()
        guard highlighter.lineCount == lineIndex.lineCount else { return [] }   // an edit is still being processed
        return highlighter.tokens(forLines: lines, in: text.mutableString, lineIndex: lineIndex)
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
        guard let highlighter else { return }
        let lineIndex = lineIndexProvider()
        guard highlighter.lineCount == lineIndex.lineCount else { return }   // an edit is still being processed
        for view in views {
            recolorVisibleLines(of: view, highlighter: highlighter, lineIndex: lineIndex)
        }
    }

    private func recolorVisibleLines(of view: View, highlighter: Highlighter, lineIndex: LineIndex) {
        guard let textView = view.textView, let textContainer = textView.textContainer else { return }
        let layoutManager = view.layoutManager

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
        for view in views {
            view.layoutManager.removeTemporaryAttribute(.foregroundColor,
                                                        forCharacterRange: NSRange(location: 0, length: text.length))
        }
    }
}
