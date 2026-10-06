import AppKit
import NotepadSCore

/// One open file, or untitled text.
///
/// The document owns the `NSTextStorage`; the editor's layout manager attaches to it.
/// Two invariants keep saving safe (see CLAUDE.md):
/// 1. `textStorage` keeps every line break exactly as in the file (`\n`, `\r\n`, `\r`,
///    possibly mixed), and saving writes them unchanged. `lineEnding` is only the style for
///    line breaks the editor inserts.
/// 2. Every character in `textStorage` can be represented in `encoding`, so saving and
///    autosaving can never fail or silently replace characters.
final class TextDocument: NSDocument {

    /// The text, with line breaks exactly as in the file.
    let textStorage = NSTextStorage()

    private(set) var encoding: TextEncoding = .utf8   // new documents: UTF-8 without BOM
    /// Style for line breaks the editor inserts (Enter, paste, drop). Set to the file's dominant
    /// style when it is read; changed only by "Convert Line Endings".
    private(set) var lineEnding: LineEnding = .lf

    /// Called after the text was replaced from disk (revert, external change, reopen with encoding).
    var onTextReplaced: (() -> Void)?
    /// Called after the encoding or line ending changed.
    var onSettingsChanged: (() -> Void)?

    /// Where the user was in the text: saved with window restoration, so a relaunch puts the
    /// caret and the scroll position back.
    struct EditorPosition: Equatable {
        var selection: NSRange
        /// The first character at the top of the visible area.
        var firstVisibleCharacter: Int
    }

    /// Set by the editor; asked when AppKit saves the restorable state.
    var editorPositionProvider: (() -> EditorPosition?)?
    /// Set by the editor; called when AppKit restores the state after the editor exists.
    var onRestoreEditorPosition: ((EditorPosition) -> Void)?
    /// A restored position that arrived before the editor existed.
    private var pendingEditorPosition: EditorPosition?

    /// Set by `reopen(with:)` right before reverting; consumed by `read(from:ofType:)`.
    private var encodingForNextRead: TextEncoding?

    /// Re-entrancy guard for `writableTypes(for:)`.
    private var isComputingWritableTypes = false

    /// Larger files are refused: TextKit 1 becomes unusable long before memory runs out.
    static let maximumFileSize = 100 * 1024 * 1024

    // MARK: - NSDocument configuration

    /// Autosave in place + versions: the basis of "never lose text". Untitled documents are
    /// autosaved too, and are reopened by window restoration.
    override class var autosavesInPlace: Bool { true }

    /// We write every type we can open (it is all plain text), so AppKit must never treat a
    /// file as "converted" and force "Save As" — e.g. for a `.yaml` or an extensionless file.
    override class func isNativeType(_ type: String) -> Bool { true }

    override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        var types = super.writableTypes(for: saveOperation)
        // While `fileType` is nil, reading it makes NSDocument compute a default by calling this
        // method again, which would recurse until the stack overflows. Skip on re-entry.
        guard !isComputingWritableTypes else { return types }
        isComputingWritableTypes = true
        defer { isComputingWritableTypes = false }
        if let fileType, !types.contains(fileType) {
            types.insert(fileType, at: 0)
        }
        return types
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: - Reading

    override func read(from data: Data, ofType typeName: String) throws {
        guard data.count <= Self.maximumFileSize else {
            throw TextCodecError.fileTooLarge(byteCount: data.count, limit: Self.maximumFileSize)
        }
        let forcedEncoding = encodingForNextRead
        encodingForNextRead = nil

        // Decode first: if this throws, the document is left untouched.
        let decoded = try TextFile.decode(data, encoding: forcedEncoding)

        encoding = decoded.encoding
        lineEnding = decoded.lineEnding
        // Loading is not an edit: change the storage directly, so nothing is recorded for undo,
        // and drop undo steps that refer to the old text (relevant when reverting).
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: decoded.text)
        undoManager?.removeAllActions()
        onTextReplaced?()
    }

    // MARK: - Writing

    /// Used for Save, Save As, Duplicate and autosave. Runs on the main thread
    /// (`canAsynchronouslyWrite` is not overridden), so reading the text storage is safe.
    override func data(ofType typeName: String) throws -> Data {
        try TextFile.encode(textStorage.string, encoding: encoding)
    }

    // MARK: - Save panel

    /// No "File Format" pop-up in the save panel: there is only one format, plain text.
    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        guard super.prepareSavePanel(savePanel) else { return false }
        // An empty list means "any extension": AppKit won't append ".txt" and won't ask
        // "Use .json or .txt?" when the user types a name with their own extension.
        savePanel.allowedContentTypes = []
        savePanel.allowsOtherFileTypes = true
        // Always show the real, full file name.
        savePanel.isExtensionHidden = false
        savePanel.canSelectHiddenExtension = false
        // Allow saving dotfiles such as ".env" next to other dotfiles.
        savePanel.showsHiddenFiles = true
        return true
    }

    /// Extension suggested in the save panel: the current file's own extension (so "x.yml"
    /// stays ".yml", not ".yaml"); none for untitled documents, so "Makefile" stays "Makefile".
    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        guard let pathExtension = fileURL?.pathExtension, !pathExtension.isEmpty else { return nil }
        return pathExtension
    }

    // MARK: - Printing

    /// File › Print… (⌘P): the text in the editor font, wrapped to the page width.
    ///
    /// Prints a separate text view, not the one on screen: the window's view is as wide as the
    /// window, not the paper. It is built like the editor (storage → layout manager → container
    /// → text view) so it is TextKit 1 too (CLAUDE.md, invariant 3).
    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let printInfo = (self.printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        printInfo.dictionary().addEntries(from: printSettings)
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin

        let storage = NSTextStorage(attributedString: textStorage)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: pageWidth, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: 0), textContainer: textContainer)
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: pageWidth, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = .zero
        // The text is colored with `.textColor`; in Light appearance that is black on white.
        view.appearance = NSAppearance(named: .aqua)
        layoutManager.ensureLayout(for: textContainer)
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: printInfo)
        operation.jobTitle = displayName
        return operation
    }

    // MARK: - Restoring the caret and scroll position

    private enum RestorationKey {
        static let selectionLocation = "NotepadSSelectionLocation"
        static let selectionLength = "NotepadSSelectionLength"
        static let firstVisibleCharacter = "NotepadSFirstVisibleCharacter"
    }

    /// AppKit calls this after `invalidateRestorableState()`, and when the app quits.
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        guard let position = editorPositionProvider?() else { return }
        coder.encode(position.selection.location, forKey: RestorationKey.selectionLocation)
        coder.encode(position.selection.length, forKey: RestorationKey.selectionLength)
        coder.encode(position.firstVisibleCharacter, forKey: RestorationKey.firstVisibleCharacter)
    }

    /// AppKit calls this after reopening the document at launch. The editor may or may not exist
    /// yet, depending on the order AppKit restores things in; both cases are handled.
    override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard coder.containsValue(forKey: RestorationKey.selectionLocation) else { return }
        let position = EditorPosition(
            selection: NSRange(location: max(coder.decodeInteger(forKey: RestorationKey.selectionLocation), 0),
                               length: max(coder.decodeInteger(forKey: RestorationKey.selectionLength), 0)),
            firstVisibleCharacter: max(coder.decodeInteger(forKey: RestorationKey.firstVisibleCharacter), 0))
        if let onRestoreEditorPosition {
            onRestoreEditorPosition(position)
        } else {
            pendingEditorPosition = position
        }
    }

    /// A position restored before the editor existed, once.
    func takePendingEditorPosition() -> EditorPosition? {
        defer { pendingEditorPosition = nil }
        return pendingEditorPosition
    }

    // MARK: - Encoding and line endings

    /// Reads the file again, interpreting its bytes as `newEncoding` ("Reopen with Encoding").
    /// Uses NSDocument's revert, which coordinates file access and resets the change count.
    func reopen(with newEncoding: TextEncoding) throws {
        guard let fileURL, let fileType else { return }
        encodingForNextRead = newEncoding
        defer { encodingForNextRead = nil }
        try revert(toContentsOf: fileURL, ofType: fileType)
    }

    /// Changes the encoding used for saving ("Convert to Encoding"). Undoable.
    /// Throws if some character can't be represented — the document is then left unchanged.
    func convert(to newEncoding: TextEncoding) throws {
        guard newEncoding != encoding else { return }
        let text = textStorage.string
        guard newEncoding.canEncode(text) else {
            throw TextCodecError.cannotEncode(newEncoding, newEncoding.firstUnencodableCharacter(in: text))
        }
        setEncoding(newEncoding)
    }

    /// Registering an undo action also marks the document as edited, so the change is autosaved.
    private func setEncoding(_ newEncoding: TextEncoding) {
        let oldEncoding = encoding
        undoManager?.registerUndo(withTarget: self) { document in
            document.setEncoding(oldEncoding)
        }
        undoManager?.setActionName(String(localized: "Change Encoding", comment: "Undo action name"))
        encoding = newEncoding
        onSettingsChanged?()
    }

    /// Changes the style for inserted line breaks. Undoable.
    ///
    /// Only the editor's "Convert Line Endings" command calls this, inside the same undo group
    /// as the text change, so one ⌘Z restores both the text and the style. The caller sets the
    /// undo action name.
    func setLineEnding(_ newLineEnding: LineEnding) {
        guard newLineEnding != lineEnding else { return }
        let oldLineEnding = lineEnding
        undoManager?.registerUndo(withTarget: self) { document in
            document.setLineEnding(oldLineEnding)
        }
        lineEnding = newLineEnding
        onSettingsChanged?()
    }

    /// The first character of `text` that the current encoding can't store, or nil if `text`
    /// may be inserted as is (invariant 2). The editor then offers to convert to UTF-8.
    func rejectionReason(forInserting text: String) -> UnencodableCharacter? {
        // Checking the scalars first is faster than building Characters for every keystroke.
        guard !encoding.canEncode(text) else { return nil }
        return encoding.firstUnencodableCharacter(in: text)
    }
}
