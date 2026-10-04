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
            return String(localized: "The file doesn’t contain plain text.", bundle: .module,
                          comment: "Error when opening an image, archive or other binary file")
        case .fileTooLarge(let byteCount, let limit):
            let formatter = ByteCountFormatter()
            let size = formatter.string(fromByteCount: Int64(byteCount))
            let maximum = formatter.string(fromByteCount: Int64(limit))
            return String(localized: "The file is too large (\(size)). NotepadS opens files up to \(maximum).",
                          bundle: .module, comment: "Error when opening a huge file; sizes like “250 MB”")
        case .cannotDecode(let encoding):
            let encodingName = encoding.displayName
            return String(localized: "The file isn’t valid \(encodingName) text.", bundle: .module,
                          comment: "Error when reopening a file with the wrong encoding")
        case .cannotEncode(let encoding, let character):
            let encodingName = encoding.displayName
            if let character {
                let characterText = String(character.character)
                let line = character.line
                return String(localized: "“\(characterText)” on line \(line) can’t be saved in \(encodingName).",
                              bundle: .module, comment: "Error when converting to an encoding that lacks a character")
            }
            return String(localized: "The text can’t be saved in \(encodingName).", bundle: .module,
                          comment: "Error when converting to an encoding that lacks a character")
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .binaryFile:
            return String(localized: "NotepadS edits text files only.", bundle: .module,
                          comment: "Advice after the binary-file error")
        case .fileTooLarge:
            return nil
        case .cannotDecode:
            return String(localized: "Choose a different encoding with “Reopen with Encoding” in the status bar.",
                          bundle: .module, comment: "Advice after the wrong-encoding error")
        case .cannotEncode:
            return String(localized: "Remove the character, or choose a Unicode encoding such as UTF-8.",
                          bundle: .module, comment: "Advice after the unsupported-character error")
        }
    }
}
