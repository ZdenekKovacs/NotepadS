import AppKit
import NotepadSCore

/// One open file, or untitled text.
///
/// The document owns the `NSTextStorage`; the editor's layout manager attaches to it.
/// Two invariants keep saving safe (see CLAUDE.md):
/// 1. `textStorage` contains only LF line breaks. The file's style (`lineEnding`) is
///    restored when saving.
/// 2. Every character in `textStorage` can be represented in `encoding`, so saving and
///    autosaving can never fail or silently replace characters.
final class TextDocument: NSDocument {

    /// The text, always with LF line breaks.
    let textStorage = NSTextStorage()

    private(set) var encoding: TextEncoding = .utf8   // new documents: UTF-8 without BOM
    private(set) var lineEnding: LineEnding = .lf
    /// True if the file mixed LF/CRLF/CR when it was opened. Saving writes `lineEnding` everywhere.
    private(set) var hadMixedLineEndings = false

    /// Called after the text was replaced from disk (revert, external change, reopen with encoding).
    var onTextReplaced: (() -> Void)?
    /// Called after the encoding or line ending changed.
    var onSettingsChanged: (() -> Void)?

    /// Set by `reopen(with:)` right before reverting; consumed by `read(from:ofType:)`.
    private var encodingForNextRead: TextEncoding?

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
        hadMixedLineEndings = decoded.hadMixedLineEndings
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
        try TextFile.encode(textStorage.string, encoding: encoding, lineEnding: lineEnding)
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
        undoManager?.setActionName("Change Encoding")
        encoding = newEncoding
        onSettingsChanged?()
    }

    /// Changes the line ending written on save. Undoable.
    func setLineEnding(_ newLineEnding: LineEnding) {
        guard newLineEnding != lineEnding else { return }
        let oldLineEnding = lineEnding
        undoManager?.registerUndo(withTarget: self) { document in
            document.setLineEnding(oldLineEnding)
        }
        undoManager?.setActionName("Change Line Endings")
        lineEnding = newLineEnding
        onSettingsChanged?()
    }

    /// Returns a user-facing message if `text` can't be represented in the current encoding
    /// (invariant 2), or nil if it may be inserted.
    func rejectionReason(forInserting text: String) -> String? {
        guard !encoding.canEncode(text) else { return nil }
        let character = encoding.firstUnencodableCharacter(in: text).map { "“\($0.character)”" } ?? "This text"
        return "\(character) can’t be saved in \(encoding.displayName). To use it, convert the document to UTF-8 with the encoding menu in the status bar."
    }
}
