import AppKit
import NotepadSCore

/// Applies edits that EditorTextView computed for several cursors. EditorViewController checks
/// the new text against the document's encoding first (the edit gatekeeper, invariant 2).
protocol EditorTextViewMultiCursorDelegate: AnyObject {
    func textView(_ textView: EditorTextView, perform edit: MultiCursorEdit, actionName: String)
}

/// VS Code-style multiple cursors: Edit › Add Cursor Above/Below (⌃⌥↑ / ⌃⌥↓) and Option-drag
/// (a column selection, which NSTextView makes natively). With several cursors, typing, Return,
/// Tab, Delete, the arrow keys (also with Shift and ⌥), Copy, Cut and Paste work at every cursor;
/// Esc or a click goes back to one. The logic is `MultiCursor` in NotepadSCore.
extension EditorTextView {

    var hasMultipleCursors: Bool { cursors.count > 1 }

    // MARK: - Adding and removing cursors

    @objc func addCursorAbove(_ sender: Any?) {
        addCursor(above: true)
    }

    @objc func addCursorBelow(_ sender: Any?) {
        addCursor(above: false)
    }

    private func addCursor(above: Bool) {
        guard let text = textStorage?.mutableString else { return }
        if !adoptMultipleSelections() {
            let selection = selectedRange()
            cursors = [Cursor(anchor: selection.location, head: NSMaxRange(selection))]
            columnForAddedCursors = MultiCursor.column(of: NSMaxRange(selection), in: text)
        }
        guard let added = MultiCursor.addingCursor(to: cursors, above: above, column: columnForAddedCursors, in: text) else {
            if !hasMultipleCursors { cursors = [] }
            NSSound.beep()
            return
        }
        setCursors(added, primary: above ? 0 : added.count - 1)
    }

    /// Back to one cursor: the primary one.
    func removeExtraCursors() {
        guard hasMultipleCursors else { return }
        setCursors([cursors[primaryCursorIndex]], primary: 0)
    }

    /// Several selections that NSTextView made itself (Option-drag selects a column) become
    /// cursors, so typing goes into every line. Returns true if there are several cursors.
    @discardableResult
    func adoptMultipleSelections() -> Bool {
        if cursors.isEmpty, selectedRanges.count > 1 {
            cursors = MultiCursor.normalized(selectedRanges.map { value in
                let range = value.rangeValue
                return Cursor(anchor: range.location, head: NSMaxRange(range))
            })
            primaryCursorIndex = cursors.count - 1
            if let text = textStorage?.mutableString {
                columnForAddedCursors = MultiCursor.column(of: cursors[primaryCursorIndex].head, in: text)
            }
        }
        return hasMultipleCursors
    }

    /// Replaces all cursors. NSTextView's own selection becomes the primary cursor, which it
    /// draws (blinking) and scrolls to; `draw(_:)` draws the others.
    func setCursors(_ newCursors: [Cursor], primary: Int) {
        isUpdatingCursors = true
        defer { isUpdatingCursors = false }
        guard !newCursors.isEmpty else { return }
        let primaryIndex = min(max(primary, 0), newCursors.count - 1)
        cursors = newCursors.count > 1 ? newCursors : []
        primaryCursorIndex = cursors.isEmpty ? 0 : primaryIndex
        let primaryRange = newCursors[primaryIndex].range
        setSelectedRange(primaryRange)
        scrollRangeToVisible(primaryRange)
        setNeedsDisplay(visibleRect)
    }

    // MARK: - Editing at every cursor

    func typeAtEveryCursor(_ typed: String) {
        guard let text = textStorage?.mutableString else { return }
        var targets = cursors
        // Overwrite mode replaces the characters after each caret (never a line break).
        if isOverwriteMode, !typed.utf8.contains(where: { $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }) {
            targets = MultiCursor.normalized(targets.map { cursor in
                guard cursor.isEmpty else { return cursor }
                let range = Overwrite.rangeReplaced(byTyping: typed.count, at: cursor.head, in: text)
                return Cursor(anchor: range.location, head: NSMaxRange(range))
            })
        }
        requestEdit(MultiCursor.replacing(targets, with: Array(repeating: typed, count: targets.count)),
                    actionName: String(localized: "Typing", comment: "Undo action name"))
    }

    /// Hands the edit to the gatekeeper, which calls `applyMultiCursorEdit` when it may go ahead.
    private func requestEdit(_ edit: MultiCursorEdit, actionName: String) {
        guard !edit.replacements.isEmpty else {
            setCursors(edit.cursors, primary: primaryCursorIndex)   // nothing to change, e.g. Delete at the end
            return
        }
        multiCursorDelegate?.textView(self, perform: edit, actionName: actionName)
    }

    /// Applies all replacements as one undo step. `shouldChangeText(inRanges:…)` records the
    /// original text of every range for Undo, like NSTextView does for its own edits.
    func applyMultiCursorEdit(_ edit: MultiCursorEdit, actionName: String) {
        guard let storage = textStorage else { return }
        breakUndoCoalescing()
        let ranges = edit.replacements.map { NSValue(range: $0.range) }
        guard shouldChangeText(inRanges: ranges, replacementStrings: edit.replacements.map(\.string)) else { return }
        isUpdatingCursors = true   // NSTextView adjusts its selection while the text changes
        storage.beginEditing()
        for replacement in edit.replacements.reversed() {   // from the end, so earlier ranges stay valid
            storage.replaceCharacters(in: replacement.range, with: replacement.string)
        }
        storage.endEditing()
        didChangeText()
        isUpdatingCursors = false
        undoManager?.setActionName(actionName)
        setCursors(edit.cursors, primary: primaryCursorIndex)
    }

    // MARK: - Keys

    /// Key presses that aren't typing arrive here as action selectors (moveLeft:, deleteBackward:
    /// …; see "Text System Defaults and Key Bindings"). With several cursors the ones below act at
    /// every cursor; anything else first goes back to one cursor.
    override func doCommand(by selector: Selector) {
        guard adoptMultipleSelections(), let text = textStorage?.mutableString else {
            super.doCommand(by: selector)
            return
        }
        if let (movement, extending) = Self.movements[selector] {
            setCursors(MultiCursor.moving(cursors, movement, extending: extending, in: text), primary: primaryCursorIndex)
            return
        }
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertNewlineIgnoringFieldEditor(_:)),
             #selector(insertLineBreak(_:)), #selector(insertParagraphSeparator(_:)):
            let breaks = cursors.map { cursor in
                lineBreakToInsert.string
                    + (EditorDefaults.autoIndents ? leadingWhitespace(ofLineBefore: cursor.range.location) : "")
            }
            requestEdit(MultiCursor.replacing(cursors, with: breaks), actionName: String(localized: "Typing", comment: "Undo action name"))
        case #selector(insertTab(_:)):
            requestEdit(MultiCursor.replacing(cursors, with: cursors.map { tabText(at: $0.range.location) }),
                        actionName: String(localized: "Typing", comment: "Undo action name"))
        case #selector(deleteBackward(_:)), #selector(deleteBackwardByDecomposingPreviousCharacter(_:)):
            delete(forward: false, byWord: false)
        case #selector(deleteForward(_:)):
            delete(forward: true, byWord: false)
        case #selector(deleteWordBackward(_:)):
            delete(forward: false, byWord: true)
        case #selector(deleteWordForward(_:)):
            delete(forward: true, byWord: true)
        case #selector(cancelOperation(_:)), #selector(complete(_:)):
            removeExtraCursors()   // Esc
        default:
            removeExtraCursors()
            super.doCommand(by: selector)
        }
    }

    private func delete(forward: Bool, byWord: Bool) {
        guard let text = textStorage?.mutableString else { return }
        requestEdit(MultiCursor.deleting(cursors, forward: forward, byWord: byWord, in: text),
                    actionName: String(localized: "Delete", comment: "Undo action name"))
    }

    /// The arrow-key actions and what they do at every cursor (Shift variants extend).
    private static let movements: [Selector: (CursorMovement, Bool)] = [
        #selector(moveLeft(_:)): (.left, false),
        #selector(moveBackward(_:)): (.left, false),
        #selector(moveRight(_:)): (.right, false),
        #selector(moveForward(_:)): (.right, false),
        #selector(moveUp(_:)): (.up, false),
        #selector(moveDown(_:)): (.down, false),
        #selector(moveWordLeft(_:)): (.wordLeft, false),
        #selector(moveWordBackward(_:)): (.wordLeft, false),
        #selector(moveWordRight(_:)): (.wordRight, false),
        #selector(moveWordForward(_:)): (.wordRight, false),
        #selector(moveToLeftEndOfLine(_:)): (.lineStart, false),
        #selector(moveToBeginningOfLine(_:)): (.lineStart, false),
        #selector(moveToBeginningOfParagraph(_:)): (.lineStart, false),
        #selector(moveToRightEndOfLine(_:)): (.lineEnd, false),
        #selector(moveToEndOfLine(_:)): (.lineEnd, false),
        #selector(moveToEndOfParagraph(_:)): (.lineEnd, false),
        #selector(moveLeftAndModifySelection(_:)): (.left, true),
        #selector(moveBackwardAndModifySelection(_:)): (.left, true),
        #selector(moveRightAndModifySelection(_:)): (.right, true),
        #selector(moveForwardAndModifySelection(_:)): (.right, true),
        #selector(moveUpAndModifySelection(_:)): (.up, true),
        #selector(moveDownAndModifySelection(_:)): (.down, true),
        #selector(moveWordLeftAndModifySelection(_:)): (.wordLeft, true),
        #selector(moveWordBackwardAndModifySelection(_:)): (.wordLeft, true),
        #selector(moveWordRightAndModifySelection(_:)): (.wordRight, true),
        #selector(moveWordForwardAndModifySelection(_:)): (.wordRight, true),
        #selector(moveToLeftEndOfLineAndModifySelection(_:)): (.lineStart, true),
        #selector(moveToBeginningOfLineAndModifySelection(_:)): (.lineStart, true),
        #selector(moveToBeginningOfParagraphAndModifySelection(_:)): (.lineStart, true),
        #selector(moveToRightEndOfLineAndModifySelection(_:)): (.lineEnd, true),
        #selector(moveToEndOfLineAndModifySelection(_:)): (.lineEnd, true),
        #selector(moveToEndOfParagraphAndModifySelection(_:)): (.lineEnd, true),
    ]

    // MARK: - Copy, Cut, Paste

    /// Copies the text of every selection, one per line (for pasting at as many cursors later).
    func copySelectionsAtEveryCursor() -> Bool {
        guard let text = textStorage?.mutableString else { return false }
        let pieces = cursors.filter { !$0.isEmpty }.map { text.substring(with: $0.range) }
        guard !pieces.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pieces.joined(separator: lineBreakToInsert.string), forType: .string)
        return true
    }

    func cutAtEveryCursor() {
        guard copySelectionsAtEveryCursor() else {
            NSSound.beep()
            return
        }
        requestEdit(MultiCursor.replacing(cursors, with: Array(repeating: "", count: cursors.count)),
                    actionName: String(localized: "Cut", comment: "Undo action name"))
    }

    /// Pastes at every cursor. If the clipboard has as many lines as there are cursors, each
    /// cursor gets one line (as in VS Code); otherwise each gets the whole text.
    func pasteAtEveryCursor() {
        guard let string = NSPasteboard.general.string(forType: .string) else {
            NSSound.beep()
            return
        }
        // Invariant 1: pasted line breaks get the document's style.
        let converted = LineEnding.convertAll(string, to: lineBreakToInsert)
        let lines = TextLines(converted).lines
        let strings = lines.count == cursors.count && lines.count > 1
            ? lines.map(\.content)
            : Array(repeating: converted, count: cursors.count)
        requestEdit(MultiCursor.replacing(cursors, with: strings), actionName: String(localized: "Paste", comment: "Undo action name"))
    }

    // MARK: - Drawing the other cursors

    /// Highlights of the other cursors' selections, under the text.
    func drawSelectionsOfOtherCursors() {
        let color: NSColor = window?.firstResponder === self && window?.isKeyWindow == true
            ? .selectedTextBackgroundColor : .unemphasizedSelectedTextBackgroundColor
        color.setFill()
        for cursor in visibleOtherCursors() where !cursor.isEmpty {
            for rect in rects(forCharacterRange: cursor.range) {
                rect.fill()
            }
        }
    }

    /// The other cursors' carets (solid; NSTextView blinks only its own).
    func drawCaretsOfOtherCursors() {
        guard window?.firstResponder === self, window?.isKeyWindow == true else { return }
        insertionPointColor.setFill()
        for cursor in visibleOtherCursors() {
            if let rect = caretRect(at: cursor.head) {
                NSRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height).fill()
            }
        }
    }

    /// Cursors other than the primary one in the visible part, so drawing never lays out the
    /// whole document.
    private func visibleOtherCursors() -> [Cursor] {
        guard let layoutManager, let textContainer else { return [] }
        let glyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return cursors.enumerated().compactMap { index, cursor in
            guard index != primaryCursorIndex,
                  NSMaxRange(cursor.range) >= characters.location, cursor.range.location <= NSMaxRange(characters) else { return nil }
            return cursor
        }
    }

    private func rects(forCharacterRange range: NSRange) -> [NSRect] {
        guard let layoutManager, let textContainer else { return [] }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: glyphs, in: textContainer) { rect, _ in
            rects.append(rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y))
        }
        return rects
    }

    /// Where a caret at `location` is drawn. For an empty glyph range, the layout manager
    /// returns a zero-width rectangle at the insertion point.
    private func caretRect(at location: Int) -> NSRect? {
        guard let layoutManager, let textContainer, let storage = textStorage else { return nil }
        let text = storage.mutableString
        // After a final line break the caret is on the "extra line fragment", which has no glyph.
        if location == text.length, text.length == 0 || [0x0A, 0x0D].contains(text.character(at: text.length - 1)) {
            let extra = layoutManager.extraLineFragmentRect
            guard !extra.isEmpty else { return nil }
            return NSRect(x: extra.minX + textContainer.lineFragmentPadding + textContainerOrigin.x,
                          y: extra.minY + textContainerOrigin.y, width: 0, height: extra.height)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        var result: NSRect?
        layoutManager.enumerateEnclosingRects(forGlyphRange: NSRange(location: glyph, length: 0),
                                              withinSelectedGlyphRange: NSRange(location: glyph, length: 0),
                                              in: textContainer) { rect, stop in
            result = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
            stop.pointee = true
        }
        return result
    }
}
