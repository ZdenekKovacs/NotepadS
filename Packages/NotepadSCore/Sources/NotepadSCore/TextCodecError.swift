import Foundation

/// Errors from reading or writing a text file. The messages are shown by `NSAlert(error:)`.
public enum TextCodecError: Error, Equatable, LocalizedError {
    /// The file looks like binary data (an image, an archive, …), not text.
    case binaryFile
    /// The file is larger than the editor can handle.
    case fileTooLarge(byteCount: Int, limit: Int)
    /// The bytes are not valid in the requested encoding (e.g. "Reopen with UTF-8" on a
    /// Windows-1252 file).
    case cannotDecode(TextEncoding)
    /// Some character can't be stored in the encoding.
    case cannotEncode(TextEncoding, UnencodableCharacter?)

    public var errorDescription: String? {
        switch self {
        case .binaryFile:
            return "The file doesn’t contain plain text."
        case .fileTooLarge(let byteCount, let limit):
            let formatter = ByteCountFormatter()
            return "The file is too large (\(formatter.string(fromByteCount: Int64(byteCount))))."
                + " NotepadS opens files up to \(formatter.string(fromByteCount: Int64(limit)))."
        case .cannotDecode(let encoding):
            return "The file isn’t valid \(encoding.displayName) text."
        case .cannotEncode(let encoding, let character):
            if let character {
                return "“\(character.character)” on line \(character.line) can’t be saved in \(encoding.displayName)."
            }
            return "The text can’t be saved in \(encoding.displayName)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .binaryFile:
            return "NotepadS edits text files only."
        case .fileTooLarge:
            return nil
        case .cannotDecode:
            return "Choose a different encoding with “Reopen with Encoding” in the status bar."
        case .cannotEncode:
            return "Remove the character, or choose a Unicode encoding such as UTF-8."
        }
    }
}
