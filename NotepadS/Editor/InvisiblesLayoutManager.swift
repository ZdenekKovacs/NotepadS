import AppKit

/// A layout manager that can draw marks for invisible characters: spaces, tabs and line breaks.
///
/// The marks are only drawn on top of the normal text; the text, the layout and the caret
/// positions stay exactly the same. Line breaks get a mark per style, so mixed files show which
/// lines end with LF, CRLF or CR.
final class InvisiblesLayoutManager: NSLayoutManager {

    /// Marks drawn for each invisible character.
    enum Mark {
        static let space = "·"
        static let tab = "→"
        static let lineFeed = "¬"          // LF  (\n)
        static let carriageReturnLineFeed = "↵"   // CRLF (\r\n)
        static let carriageReturn = "←"    // CR  (\r)
    }

    var showsInvisibles = false {
        didSet {
            guard showsInvisibles != oldValue, let textStorage else { return }
            invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
        }
    }

    /// AppKit calls this for the visible glyphs only, so the extra work stays small.
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard showsInvisibles, let textStorage else { return }

        let text = textStorage.mutableString
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        var index = characters.location
        while index < NSMaxRange(characters) {
            var length = 1
            let mark: String?
            switch text.character(at: index) {
            case 0x20:
                mark = Mark.space
            case 0x09:
                mark = Mark.tab
            case 0x0A:
                mark = Mark.lineFeed
            case 0x0D:
                // "\r\n" is one line break: one mark, at the "\r".
                if index + 1 < text.length && text.character(at: index + 1) == 0x0A {
                    mark = Mark.carriageReturnLineFeed
                    length = 2
                } else {
                    mark = Mark.carriageReturn
                }
            default:
                mark = nil
            }
            // No marks inside a folded block: its characters aren't shown (the first one is "…").
            let isFolded = (delegate as? FoldingController)?.isHidden(index) ?? false
            if let mark, !isFolded {
                draw(mark, atCharacter: index, origin: origin, in: textStorage)
            }
            index += length
        }
    }

    private func draw(_ mark: String, atCharacter index: Int, origin: NSPoint, in textStorage: NSTextStorage) {
        let glyph = glyphIndexForCharacter(at: index)
        let lineFragment = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        // `location(forGlyphAt:)` is the glyph's baseline point, relative to its line fragment.
        let glyphLocation = location(forGlyphAt: glyph)
        let font = textStorage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        // `draw(at:)` takes the top-left corner (the text view is flipped), so go up from the
        // baseline by the font's ascender.
        let point = NSPoint(x: origin.x + lineFragment.minX + glyphLocation.x,
                            y: origin.y + lineFragment.minY + glyphLocation.y - font.ascender)
        (mark as NSString).draw(at: point, withAttributes: attributes)
    }
}
