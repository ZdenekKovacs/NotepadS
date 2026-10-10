import AppKit
import NotepadSCore

/// Code folding for one editor pane: which blocks can fold (`Folding` in NotepadSCore finds
/// them) and which are folded now.
///
/// Folding only changes how this pane *draws* the text; the text itself is untouched (no undo
/// step, nothing saved). TextKit 1 lets the layout manager's delegate change the glyphs it
/// generates: characters in a folded block get the `.null` glyph property (they take no space)
/// and the first one is drawn as "…"; line breaks inside the block get `.zeroAdvancement`, so
/// the block doesn't start new lines. The other pane of a split editor folds independently.
final class FoldingController: NSObject, NSLayoutManagerDelegate {

    /// Called after folds were added or removed (the gutter redraws its markers).
    var onChange: (() -> Void)?

    private weak var layoutManager: NSLayoutManager?
    /// Foldable blocks by their start line.
    private(set) var regionsByStartLine: [Int: FoldRegion] = [:]
    /// The hidden ranges of the folded blocks, sorted by location. A block folded inside a
    /// folded block stays in the list, so it is still folded when the outer one opens.
    private(set) var foldedRanges: [NSRange] = []

    init(layoutManager: NSLayoutManager) {
        self.layoutManager = layoutManager
        super.init()
        layoutManager.delegate = self
    }

    // MARK: - Regions

    /// New foldable blocks, after the text or the language changed.
    func setRegions(_ regions: [FoldRegion]) {
        regionsByStartLine = Dictionary(regions.map { ($0.startLine, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func isFolded(_ region: FoldRegion) -> Bool {
        foldedRanges.contains(region.hiddenRange)
    }

    // MARK: - Folding and unfolding

    /// Folds or unfolds the block starting at `line`. Returns false if no block starts there.
    @discardableResult
    func toggle(line: Int) -> Bool {
        guard let region = regionsByStartLine[line] else { return false }
        if isFolded(region) {
            unfold(region.hiddenRange)
        } else {
            fold(region.hiddenRange)
        }
        return true
    }

    func fold(_ range: NSRange) {
        guard range.length > 0, !foldedRanges.contains(range) else { return }
        foldedRanges.append(range)
        foldedRanges.sort { $0.location < $1.location }
        invalidate(range)
    }

    func unfold(_ range: NSRange) {
        guard let index = foldedRanges.firstIndex(of: range) else { return }
        foldedRanges.remove(at: index)
        invalidate(range)
    }

    func foldAll() {
        let ranges = regionsByStartLine.values.map(\.hiddenRange).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return }
        foldedRanges = Array(Set(foldedRanges + ranges)).sorted { $0.location < $1.location }
        invalidateAll()
    }

    func unfoldAll() {
        guard !foldedRanges.isEmpty else { return }
        foldedRanges = []
        invalidateAll()
    }

    /// Unfolds every folded block that hides `location`, e.g. when Find or Go to Line puts the
    /// caret there. A caret right before or after a block isn't inside it.
    func unfoldBlocks(hiding location: Int) {
        let hiding = foldedRanges.filter { location > $0.location && location < NSMaxRange($0) }
        for range in hiding {
            unfold(range)
        }
    }

    /// True if a line starting at `location` is folded away, for the line-number gutter. A line
    /// starting right at the end of a folded block (a `}` at the start of a line) is shown as
    /// part of the fold's line, so it is hidden as well.
    func isLineHidden(startingAt location: Int) -> Bool {
        foldedRanges.contains { location > $0.location && location <= NSMaxRange($0) }
    }

    /// True if the character at `location` is inside a folded block.
    func isHidden(_ location: Int) -> Bool {
        foldedRanges.contains { NSLocationInRange(location, $0) }
    }

    // MARK: - Text changes

    /// Keeps folds in place when the text changes: a fold after the edit moves with the text,
    /// a fold the edit touches opens (its block isn't what it was).
    func textDidChange(editedRange: NSRange, changeInLength: Int) {
        guard !foldedRanges.isEmpty else { return }
        let oldEnd = NSMaxRange(editedRange) - changeInLength   // end of the edit in the old text
        foldedRanges = foldedRanges.compactMap { range in
            if NSMaxRange(range) <= editedRange.location {
                return range
            }
            if range.location >= oldEnd {
                return NSRange(location: range.location + changeInLength, length: range.length)
            }
            return nil
        }
        onChange?()
    }

    // MARK: - Layout manager delegate

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>,
                       font: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        guard !foldedRanges.isEmpty, glyphRange.length > 0 else { return 0 }   // 0: keep AppKit's glyphs
        let first = characterIndexes[0], last = characterIndexes[glyphRange.length - 1]
        guard foldedRanges.contains(where: { $0.location <= last && NSMaxRange($0) > first }) else { return 0 }

        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        var newProperties = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        var ellipsis: CGGlyph = 0
        var character: UniChar = 0x2026   // …
        CTFontGetGlyphsForCharacters(font as CTFont, &character, &ellipsis, 1)
        for index in 0..<glyphRange.length {
            let characterIndex = characterIndexes[index]
            guard isHidden(characterIndex) else { continue }
            if isEllipsis(characterIndex) {
                newGlyphs[index] = ellipsis
                newProperties[index] = []   // a plain visible glyph, even if the character is a line break
            } else {
                newProperties[index] = .null
            }
        }
        layoutManager.setGlyphs(newGlyphs, properties: newProperties, characterIndexes: characterIndexes,
                                font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt characterIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        // Line breaks and tabs inside a folded block take no space and break no lines. The
        // typesetter asks this for every line break, also the one shown as "…" (the first
        // character of an indentation fold): that one must not break the line either.
        guard isHidden(characterIndex) else { return action }
        return isEllipsis(characterIndex) ? .whitespace : .zeroAdvancement
    }

    /// The first character of an outermost folded block shows "…".
    private func isEllipsis(_ location: Int) -> Bool {
        foldedRanges.contains { $0.location == location }
            && !foldedRanges.contains { $0.location < location && NSLocationInRange(location, $0) }
    }

    // MARK: - Invalidation

    /// Makes the layout manager generate the glyphs of `range` again and lay them out. Whole
    /// lines (paragraphs): invalidating only the hidden characters leaves the fold's first line
    /// laid out as before, with its line break still breaking the line.
    private func invalidate(_ range: NSRange) {
        guard let layoutManager, let text = layoutManager.textStorage?.mutableString else { return }
        let clamped = text.paragraphRange(for: NSIntersectionRange(range, NSRange(location: 0, length: text.length)))
        layoutManager.invalidateGlyphs(forCharacterRange: clamped, changeInLength: 0, actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: clamped, actualCharacterRange: nil)
        onChange?()
    }

    private func invalidateAll() {
        guard let length = layoutManager?.textStorage?.length else { return }
        invalidate(NSRange(location: 0, length: length))
    }
}
