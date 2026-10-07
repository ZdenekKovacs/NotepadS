import AppKit
import NotepadSCore

/// A miniature of the document beside the text, as in VS Code: each line is drawn as small
/// blocks (one per character, spaces left empty) in the syntax-highlighting colors, and a
/// shaded "slider" marks the visible part. Click to jump there; drag the slider to scroll;
/// the scroll wheel scrolls the text.
///
/// Like the gutter, it draws only the lines that fit in its height and reads them straight from
/// the text storage through `LineIndex`, so it costs the same for a 10-line and a 1-million-line
/// file. It works on logical lines (as in the file), not wrapped lines: that needs no layout,
/// which matters because the layout manager lays out only the visible text (non-contiguous layout).
///
/// When the document has more lines than fit, the minimap scrolls too, proportionally to the
/// text: at the top of the text it shows the first lines, at the bottom the last ones.
final class MinimapView: NSView {

    static let width: CGFloat = 110

    /// Height of one line in points. On a Retina screen 2 pt = 4 pixels: 3 for the block, 1 gap.
    private let lineHeight: CGFloat = 2
    private let blockHeight: CGFloat = 1.5
    private let characterWidth: CGFloat = 1
    private let horizontalPadding: CGFloat = 6
    private let minimumSliderHeight: CGFloat = 12

    private let text: NSTextStorage
    private weak var scrollView: NSScrollView?
    private let lineIndexProvider: () -> LineIndex
    /// The characters visible in the text view (computed by the editor from the layout manager).
    private let visibleCharactersProvider: () -> NSRange
    /// Syntax tokens of some lines (ranges from the start of the text); nil without highlighting.
    private let tokensProvider: (Range<Int>) -> [SyntaxToken]?

    /// Syntax tokens per line, with ranges relative to the line start, so they stay valid when
    /// an edit above moves the line. Tokenizing all ~400 lines the minimap shows takes 15–30 ms,
    /// too slow for every keystroke or scroll step, so each line is tokenized once and kept.
    /// After an edit, lines below it keep their colors; they can be outdated (e.g. after typing
    /// `/*`), so the whole cache is refreshed once typing pauses.
    private var lineTokens: [Int: [SyntaxToken]] = [:]
    /// Increases with every edit; a scheduled refresh for an older edit does nothing.
    private var editGeneration = 0

    /// While dragging: the distance from the slider's top to the mouse, kept constant.
    private var dragOffsetInSlider: CGFloat?

    init(text: NSTextStorage, scrollView: NSScrollView,
         lineIndexProvider: @escaping () -> LineIndex,
         visibleCharactersProvider: @escaping () -> NSRange,
         tokensProvider: @escaping (Range<Int>) -> [SyntaxToken]?) {
        self.text = text
        self.scrollView = scrollView
        self.lineIndexProvider = lineIndexProvider
        self.visibleCharactersProvider = visibleCharactersProvider
        self.tokensProvider = tokensProvider
        super.init(frame: .zero)
        // See LineNumberRulerView: since the macOS 14 SDK, views don't clip their drawing by default.
        clipsToBounds = true
        setAccessibilityElement(false)   // a picture of the text; the text view itself is accessible
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Like the text view: y grows downwards, line 0 is at the top.
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    /// A click in a window that isn't active jumps right away, instead of only activating it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true   // more or fewer lines fit now
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true   // Light/Dark mode: the colors below resolve differently
    }

    // MARK: - Updates from the editor

    /// Call for every text change, with the lines `LineIndex` reported.
    func textDidChange(_ change: LineChange) {
        var moved: [Int: [SyntaxToken]] = [:]
        for (line, tokens) in lineTokens {
            if line < change.firstLine {
                moved[line] = tokens
            } else if line > change.oldLastLine {
                moved[line + change.lineCountDelta] = tokens
            }
            // The edited lines themselves are tokenized again when drawn.
        }
        lineTokens = moved
        needsDisplay = true

        editGeneration += 1
        let generation = editGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, generation == self.editGeneration else { return }   // still typing
            self.syntaxDidChange()
        }
    }

    /// Call when the colors of many lines may have changed: another language, or the whole
    /// text was replaced.
    func syntaxDidChange() {
        lineTokens.removeAll()
        needsDisplay = true
    }

    // MARK: - Geometry

    /// Where things are, computed fresh for each drawing or mouse event.
    private struct Geometry {
        /// How far the minimap's content is scrolled, in points.
        var contentOffset: CGFloat
        /// The visible part of the text, in view coordinates.
        var slider: NSRect
        /// How far the slider's top can move, in points (for dragging).
        var sliderTravel: CGFloat
    }

    private func geometry(lineIndex: LineIndex) -> Geometry {
        let contentHeight = CGFloat(lineIndex.lineCount) * lineHeight
        let overflow = max(0, contentHeight - bounds.height)
        let contentOffset = (overflow * scrollFraction).rounded()

        let visible = visibleCharactersProvider()
        let firstLine = lineIndex.line(containing: visible.location)
        let lastLine = lineIndex.line(containing: max(visible.location, NSMaxRange(visible) - 1))
        let sliderHeight = max(CGFloat(lastLine - firstLine + 1) * lineHeight, minimumSliderHeight)
        let slider = NSRect(x: 0, y: CGFloat(firstLine) * lineHeight - contentOffset,
                            width: bounds.width, height: sliderHeight)
        let sliderTravel = max(1, min(contentHeight, bounds.height) - sliderHeight)
        return Geometry(contentOffset: contentOffset, slider: slider, sliderTravel: sliderTravel)
    }

    /// How far the text is scrolled: 0 at the top, 1 at the bottom.
    private var scrollFraction: CGFloat {
        guard let clipView = scrollView?.contentView else { return 0 }
        let maximum = clipView.documentRect.height - clipView.bounds.height
        guard maximum > 0 else { return 0 }
        return min(max(clipView.bounds.origin.y / maximum, 0), 1)
    }

    /// Scrolls the text to `fraction` (0 = top, 1 = bottom).
    private func scrollText(toFraction fraction: CGFloat) {
        guard let scrollView else { return }
        let clipView = scrollView.contentView
        let maximum = max(0, clipView.documentRect.height - clipView.bounds.height)
        // Keep the clip view's x origin: it extends under the gutter (see EditorViewController.scrollToTop).
        let target = NSPoint(x: clipView.bounds.origin.x, y: (maximum * min(max(fraction, 0), 1)).rounded())
        clipView.scroll(to: clipView.constrainBoundsRect(NSRect(origin: target, size: clipView.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        let lineIndex = lineIndexProvider()
        let geometry = geometry(lineIndex: lineIndex)

        NSColor.labelColor.withAlphaComponent(dragOffsetInSlider == nil ? 0.08 : 0.16).setFill()
        geometry.slider.fill()

        let blocks = characterBlocks(in: dirtyRect, lineIndex: lineIndex, contentOffset: geometry.contentOffset)
        if let context = NSGraphicsContext.current?.cgContext {
            // `setFill()` sets the context's fill color; one fill per color is much faster than
            // filling thousands of small rectangles one by one.
            for (scope, rects) in blocks {
                let color = scope.map { SyntaxTheme.color(for: $0).withAlphaComponent(0.85) }
                    ?? NSColor.textColor.withAlphaComponent(0.5)
                color.setFill()
                context.addRects(rects)
                context.fillPath()
            }
        }

        // A thin line between the text and the minimap.
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
    }

    /// One rectangle per run of non-blank characters of the same color on the lines inside
    /// `rect`, grouped by syntax scope (nil = plain text).
    private func characterBlocks(in rect: NSRect, lineIndex: LineIndex, contentOffset: CGFloat) -> [SyntaxScope?: [CGRect]] {
        let firstLine = max(0, Int(((rect.minY + contentOffset) / lineHeight).rounded(.down)))
        let lastLine = min(lineIndex.lineCount - 1, Int(((rect.maxY + contentOffset) / lineHeight).rounded(.up)))
        guard firstLine <= lastLine else { return [:] }
        loadTokens(forLines: firstLine..<(lastLine + 1), lineIndex: lineIndex)

        let maxColumns = max(0, Int((bounds.width - 2 * horizontalPadding) / characterWidth))
        let tabWidth = EditorDefaults.tabWidth
        // Read at most `maxColumns` characters per line: a 5 MB single-line file costs the same as a short line.
        var buffer = [unichar](repeating: 0, count: maxColumns)
        var rects: [SyntaxScope?: [CGRect]] = [:]
        let textLength = text.length

        for line in firstLine...lastLine {
            let content = lineIndex.contentRange(ofLine: line)
            let length = min(content.length, maxColumns)
            guard length > 0, content.location + length <= textLength else { continue }
            text.mutableString.getCharacters(&buffer, range: NSRange(location: content.location, length: length))

            let y = CGFloat(line) * lineHeight - contentOffset
            let tokens = lineTokens[line] ?? []
            var tokenIndex = 0
            var column = 0
            var runStart: Int?
            var runScope: SyntaxScope?
            func endRun() {
                guard let start = runStart else { return }
                rects[runScope, default: []].append(
                    CGRect(x: horizontalPadding + CGFloat(start) * characterWidth, y: y,
                           width: CGFloat(min(column, maxColumns) - start) * characterWidth,
                           height: blockHeight))
                runStart = nil
            }
            for (offset, unit) in buffer[0..<length].enumerated() {
                if column >= maxColumns { break }
                // The token covering this character, if any (tokens are sorted and don't overlap).
                while tokenIndex < tokens.count, NSMaxRange(tokens[tokenIndex].range) <= offset {
                    tokenIndex += 1
                }
                let scope = tokenIndex < tokens.count && tokens[tokenIndex].range.location <= offset
                    ? tokens[tokenIndex].scope : nil
                switch unit {
                case 0x09:   // tab: advance to the next tab stop
                    endRun()
                    column = (column / tabWidth + 1) * tabWidth
                case 0x20, 0xA0:   // space, no-break space
                    endRun()
                    column += 1
                case 0xDC00...0xDFFF:
                    break   // second half of a surrogate pair (e.g. an emoji): no extra column
                default:
                    if runStart != nil && scope != runScope { endRun() }
                    if runStart == nil {
                        runStart = column
                        runScope = scope
                    }
                    column += 1
                }
            }
            endRun()
        }
        return rects
    }

    /// Tokenizes the lines in `lines` that aren't in `lineTokens` yet.
    private func loadTokens(forLines lines: Range<Int>, lineIndex: LineIndex) {
        if lineTokens.count > 5_000 {
            lineTokens.removeAll()   // keep memory bounded after scrolling through a huge file
        }
        var line = lines.lowerBound
        while line < lines.upperBound {
            guard lineTokens[line] == nil else {
                line += 1
                continue
            }
            // Ask for each run of missing lines at once.
            var end = line + 1
            while end < lines.upperBound && lineTokens[end] == nil { end += 1 }
            guard let tokens = tokensProvider(line..<end) else { return }   // no highlighting
            for missing in line..<end {
                lineTokens[missing] = []
            }
            for token in tokens {
                let tokenLine = lineIndex.line(containing: token.range.location)
                let lineStart = lineIndex.lineStart(of: tokenLine)
                lineTokens[tokenLine, default: []].append(
                    SyntaxToken(range: NSRange(location: token.range.location - lineStart, length: token.range.length),
                                scope: token.scope))
            }
            line = end
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let geometry = geometry(lineIndex: lineIndexProvider())
        if geometry.slider.contains(point) {
            // Grab the slider where it was clicked.
            dragOffsetInSlider = point.y - geometry.slider.minY
        } else {
            // Jump: center the slider on the click, then keep dragging from there.
            dragOffsetInSlider = geometry.slider.height / 2
            drag(to: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        drag(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        dragOffsetInSlider = nil
        needsDisplay = true
    }

    /// Moves the slider's top to `point.y` minus the grab offset, by scrolling the text.
    private func drag(to point: NSPoint) {
        guard let dragOffsetInSlider else { return }
        let geometry = geometry(lineIndex: lineIndexProvider())
        scrollText(toFraction: (point.y - dragOffsetInSlider) / geometry.sliderTravel)
    }

    /// The scroll wheel and trackpad over the minimap scroll the text.
    override func scrollWheel(with event: NSEvent) {
        scrollView?.scrollWheel(with: event)
    }
}
