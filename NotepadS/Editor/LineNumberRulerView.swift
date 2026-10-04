import AppKit
import NotepadSCore

/// Line numbers in the scroll view's vertical ruler (TextKit 1).
///
/// - Draws only the visible lines.
/// - Line starts come from `LineIndex`, so drawing never scans the text.
/// - Positions come from the layout manager, so a wrapped line gets one number.
/// - The current line's number is drawn in the primary label color.
final class LineNumberRulerView: NSRulerView {

    private weak var textView: NSTextView?
    private let lineIndexProvider: () -> LineIndex
    private var numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var lineCount = 1
    private var digitCount = 0
    private let horizontalPadding: CGFloat = 8

    /// - Parameters:
    ///   - textView: must already be the scroll view's document view.
    ///   - lineIndexProvider: returns the editor's current line index (owned by the view controller).
    init(textView: NSTextView, lineIndexProvider: @escaping () -> LineIndex) {
        self.textView = textView
        self.lineIndexProvider = lineIndexProvider
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        reservedThicknessForMarkers = 0
        reservedThicknessForAccessoryView = 0
        updateThickness()

        // Redraw when the visible text changes: scrolling, or re-wrapping after a resize.
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(visibleTextDidChange(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: clipView)
        }
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(visibleTextDidChange(_:)),
                                               name: NSView.frameDidChangeNotification, object: textView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Same coordinate orientation as the (flipped) text view: y grows downwards.
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: - Updates from the editor

    /// Widens or narrows the gutter when the number of digits changes.
    func lineCountDidChange(_ newLineCount: Int) {
        lineCount = newLineCount
        updateThickness()
    }

    func textFontDidChange(_ textFont: NSFont) {
        numberFont = NSFont.monospacedDigitSystemFont(ofSize: max(textFont.pointSize - 2, 9), weight: .regular)
        digitCount = 0   // force recalculation with the new font
        updateThickness()
        needsDisplay = true
    }

    @objc private func visibleTextDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    private func updateThickness() {
        let digits = max(String(lineCount).count, 3)
        guard digits != digitCount else { return }
        digitCount = digits
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        ruleThickness = ceil(CGFloat(digits) * digitWidth + 2 * horizontalPadding)
        scrollView?.tile()   // re-layout the scroll view for the new gutter width
    }

    // MARK: - Drawing

    /// Replaces NSRulerView's default appearance with a plain gutter.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let lineIndex = lineIndexProvider()
        let textLength = textView.textStorage?.length ?? 0

        // Characters visible in the text view. Layout-manager rects are in text-container
        // coordinates, which are offset from the text view by `textContainerOrigin`.
        let origin = textView.textContainerOrigin
        var visibleRect = textView.visibleRect
        visibleRect.origin.x -= origin.x
        visibleRect.origin.y -= origin.y
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let caretLine = lineIndex.line(containing: min(textView.selectedRange().location, textLength))
        var line = lineIndex.line(containing: visibleCharacters.location)

        while line < lineIndex.lineCount {
            let start = lineIndex.lineStart(of: line)
            if start > NSMaxRange(visibleCharacters) { break }

            let lineFragment: NSRect
            if start < textLength {
                let glyph = layoutManager.glyphIndexForCharacter(at: start)
                lineFragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                // The empty last line after a final "\n", or an empty document.
                lineFragment = layoutManager.extraLineFragmentRect
            }
            if !lineFragment.isEmpty {
                drawNumber(line + 1, lineFragment: lineFragment, in: textView, isCurrentLine: line == caretLine)
            }
            line += 1
        }
    }

    private func drawNumber(_ number: Int, lineFragment: NSRect, in textView: NSTextView, isCurrentLine: Bool) {
        let topInTextView = lineFragment.minY + textView.textContainerOrigin.y
        let top = convert(NSPoint(x: 0, y: topInTextView), from: textView).y
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: isCurrentLine ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let label = String(number) as NSString
        let size = label.size(withAttributes: attributes)
        // Right-aligned, vertically centred on the line's first fragment.
        let point = NSPoint(x: bounds.width - horizontalPadding - size.width,
                            y: top + (lineFragment.height - size.height) / 2)
        label.draw(at: point, withAttributes: attributes)
    }
}
