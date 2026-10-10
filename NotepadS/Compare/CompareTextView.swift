import AppKit
import NotepadSCore

/// One side of the Compare window: a read-only text view with one line per row of the
/// side-by-side view, colored by row kind across the full width.
///
/// Built like the editor's text view (TextKit 1, explicit stack), but simpler: no wrapping,
/// no editing. The colors are drawn in `drawBackground(in:)`, under the text: a text background
/// attribute would only cover the characters, not the whole line.
final class CompareTextView: NSTextView {

    /// The kind of each row; drawn as its background.
    var rowKinds: [TextDiff.Kind] = []
    /// Rows that are fillers (no line on this side), drawn hatched.
    var fillerRows: Set<Int> = []
    /// Where each row starts in the text (UTF-16), to find its line fragment.
    private(set) var rowStarts: [Int] = []

    /// Creates the TextKit 1 stack: storage → layout manager → container → this view.
    static func make() -> CompareTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        // No wrapping: the container is practically infinitely wide (FLT_MAX, see EditorPane).
        let unlimited = CGFloat(Float.greatestFiniteMagnitude)
        let container = NSTextContainer(size: NSSize(width: unlimited, height: unlimited))
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)
        let view = CompareTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = true
        view.backgroundColor = .textBackgroundColor
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: unlimited, height: unlimited)
        view.textContainerInset = NSSize(width: 4, height: 4)
        return view
    }

    /// Shows `lines` (one per row) with `font`, and highlights `changedRanges` (per row, ranges
    /// within the row's line) more strongly.
    func show(lines: [String], kinds: [TextDiff.Kind], fillers: Set<Int>, changedRanges: [Int: [NSRange]],
              font: NSFont, isLeft: Bool) {
        rowKinds = kinds
        fillerRows = fillers
        var starts: [Int] = []
        var location = 0
        for line in lines {
            starts.append(location)
            location += (line as NSString).length + 1
        }
        rowStarts = starts
        // Display text only: joined with "\n" whatever the files use; it is never saved.
        let text = NSMutableAttributedString(string: lines.joined(separator: "\n"),
                                             attributes: [.font: font, .foregroundColor: NSColor.textColor])
        let strong = (isLeft ? NSColor.systemRed : NSColor.systemGreen).withAlphaComponent(0.35)
        for (row, ranges) in changedRanges {
            for range in ranges {
                text.addAttribute(.backgroundColor, value: strong,
                                  range: NSRange(location: starts[row] + range.location, length: range.length))
            }
        }
        textStorage?.setAttributedString(text)
        needsDisplay = true
    }

    /// The rectangle of `row` in this view's coordinates (full width).
    func rect(ofRow row: Int) -> NSRect? {
        guard let layoutManager, rowStarts.indices.contains(row), let length = textStorage?.length else { return nil }
        let fragment: NSRect
        if rowStarts[row] < length {
            fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: rowStarts[row]),
                                                      effectiveRange: nil)
        } else {
            fragment = layoutManager.extraLineFragmentRect   // an empty last row
        }
        guard !fragment.isEmpty else { return nil }
        return NSRect(x: bounds.minX, y: fragment.minY + textContainerOrigin.y, width: bounds.width, height: fragment.height)
    }

    /// The rows visible in `rect`.
    func rows(in rect: NSRect) -> Range<Int> {
        guard let layoutManager, let textContainer, !rowStarts.isEmpty else { return 0..<0 }
        let containerRect = rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let first = row(containing: characters.location)
        let last = row(containing: NSMaxRange(characters))
        return first..<(last + 1)
    }

    private func row(containing location: Int) -> Int {
        // The last row starting at or before `location` (rows are sorted).
        var low = 0, high = rowStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if rowStarts[middle] <= location { low = middle } else { high = middle - 1 }
        }
        return low
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for row in rows(in: rect) {
            guard let rowRect = self.rect(ofRow: row), let color = color(forRow: row) else { continue }
            color.setFill()
            rowRect.fill()
            if fillerRows.contains(row) {
                drawHatching(in: rowRect)
            }
        }
    }

    private func color(forRow row: Int) -> NSColor? {
        guard rowKinds.indices.contains(row) else { return nil }
        switch rowKinds[row] {
        case .same: return nil
        case .removed: return fillerRows.contains(row) ? NSColor.quaternaryLabelColor : NSColor.systemRed.withAlphaComponent(0.15)
        case .added: return fillerRows.contains(row) ? NSColor.quaternaryLabelColor : NSColor.systemGreen.withAlphaComponent(0.15)
        case .changed: return NSColor.systemYellow.withAlphaComponent(0.18)
        }
    }

    /// Diagonal lines for a row with no line on this side, like most diff tools.
    private func drawHatching(in rect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let path = NSBezierPath()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: NSPoint(x: x, y: rect.maxY))
            path.line(to: NSPoint(x: x + rect.height, y: rect.minY))
            x += 8
        }
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The line numbers of one side: the original numbers, none for filler rows.
final class CompareGutterView: NSRulerView {

    var lineNumbers: [Int?] = [] {
        didSet {
            let digits = max(String(lineNumbers.compactMap { $0 }.max() ?? 1).count, 3)
            ruleThickness = CGFloat(digits) * 8 + 16
            needsDisplay = true
        }
    }
    private weak var textView: CompareTextView?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    init(textView: CompareTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        clipsToBounds = true   // see LineNumberRulerView
        ruleThickness = 40
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        guard let textView else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        for row in textView.rows(in: textView.visibleRect) {
            guard lineNumbers.indices.contains(row), let number = lineNumbers[row],
                  let rowRect = textView.rect(ofRow: row) else { continue }
            let top = convert(NSPoint(x: 0, y: rowRect.minY), from: textView).y
            let label = String(number) as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.width - 6 - size.width, y: top + (rowRect.height - size.height) / 2),
                       withAttributes: attributes)
        }
    }
}
