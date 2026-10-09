import AppKit
import NotepadSCore

/// One view of a document's text: layout manager, text container, text view, scroll view and
/// line-number gutter. An editor has one pane, or two when split (View › Split Editor).
///
/// Both panes show the same `NSTextStorage`. TextKit 1 supports this directly: a text storage
/// can have several layout managers, each laying out the same text for its own text view, so
/// typing in one pane appears in the other at once, while each pane scrolls on its own.
final class EditorPane {

    let layoutManager = InvisiblesLayoutManager()
    let textView: EditorTextView
    let scrollView = NSScrollView()
    private(set) var lineNumberView: LineNumberRulerView!

    /// Builds the TextKit 1 stack explicitly: storage → layout manager → container → view.
    /// Because the container belongs to an NSLayoutManager, the text view is TextKit 1 from the
    /// start, and using `layoutManager` later can never trigger a TextKit 2 fallback.
    init(textStorage: NSTextStorage, showsInvisibles: Bool) {
        // Lay out only what is visible (plus a margin). This is what keeps multi-MB files fast.
        layoutManager.allowsNonContiguousLayout = true
        layoutManager.showsInvisibles = showsInvisibles
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true   // word wrap at the view width
        layoutManager.addTextContainer(textContainer)
        textView = EditorTextView(frame: .zero, textContainer: textContainer)
    }

    /// Puts the text view into the scroll view and adds the gutter. `size` is a first size; the
    /// enclosing layout changes it later.
    func installViews(size: NSSize, wrapsLines: Bool, lineIndexProvider: @escaping () -> LineIndex) {
        // Apple's recipe for a text view in a scroll view: give both a real initial size, let
        // the text view grow vertically and track the visible width through autoresizing.
        scrollView.frame = NSRect(origin: .zero, size: size)
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
        applyWordWrap(wrapsLines)

        // The gutter must be created after the text view is inside the scroll view.
        lineNumberView = LineNumberRulerView(textView: textView, lineIndexProvider: lineIndexProvider)
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
    }

    /// Removes this pane's layout manager from the text storage, so it no longer lays out the
    /// text (after closing a split).
    func detach(from textStorage: NSTextStorage) {
        textStorage.removeLayoutManager(layoutManager)
    }

    // MARK: - Word wrap

    /// Wrap on: the text container is as wide as the text view, which follows the visible width.
    /// Wrap off: the container is practically infinitely wide, so lines never break, and the text
    /// view grows sideways with the longest line; the horizontal scroller appears.
    /// (Apple's "Text System User Interface Layer" guide describes both setups.)
    func applyWordWrap(_ wrapsLines: Bool) {
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

    // MARK: - Visible text and scrolling

    /// The characters currently visible in the text view.
    func visibleCharacterRange() -> NSRange {
        guard let textContainer = textView.textContainer else { return NSRange(location: 0, length: 0) }
        var visibleRect = textView.visibleRect
        visibleRect.origin.x -= textView.textContainerOrigin.x
        visibleRect.origin.y -= textView.textContainerOrigin.y
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }

    /// Scrolls so that the line containing `character` is at the top of the visible area.
    ///
    /// With non-contiguous layout (on for speed), the layout manager only estimates the height of
    /// text it hasn't laid out yet. Scrolling to a line's position can therefore land a few lines
    /// off, because laying out the newly visible text corrects the estimates. Each round below
    /// measures where the line really is now and scrolls again; it settles after a round or two.
    func scrollToTop(character: Int) {
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
}
