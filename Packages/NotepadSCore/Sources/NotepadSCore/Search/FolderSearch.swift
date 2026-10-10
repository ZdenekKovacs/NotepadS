import Foundation

/// Which files Find in Files searches, from a text field such as `*.swift *.py !*.min.js !build`.
///
/// Patterns are separated by spaces, commas or semicolons. `*` matches any characters, `?` one
/// character; letter case doesn't matter. A pattern starting with `!` excludes files *and
/// folders* with matching names (`!node_modules` skips that folder). Without include patterns,
/// every file is included.
public struct FileFilter: Equatable, Sendable {
    public let includes: [String]
    public let excludes: [String]

    public init(_ text: String) {
        let patterns = text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }).map(String.init)
        includes = patterns.filter { !$0.hasPrefix("!") }
        excludes = patterns.filter { $0.hasPrefix("!") }.map { String($0.dropFirst()) }.filter { !$0.isEmpty }
    }

    public func includesFile(named name: String) -> Bool {
        !isExcluded(name) && (includes.isEmpty || includes.contains { Self.matches(name, pattern: $0) })
    }

    /// Folders are only ever excluded by name, never required to match an include pattern.
    public func includesFolder(named name: String) -> Bool {
        !isExcluded(name)
    }

    private func isExcluded(_ name: String) -> Bool {
        excludes.contains { Self.matches(name, pattern: $0) }
    }

    /// Glob matching on whole names: `*` any run of characters, `?` one character.
    static func matches(_ name: String, pattern: String) -> Bool {
        let regex = "^" + pattern.map { character -> String in
            switch character {
            case "*": return ".*"
            case "?": return "."
            default: return NSRegularExpression.escapedPattern(for: String(character))
            }
        }.joined() + "$"
        return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// One match of Find in Files.
public struct LineMatch: Equatable, Sendable {
    /// 0-based line number in the file.
    public let line: Int
    /// The line's text without its break, shortened around the match if the line is very long.
    public let lineText: String
    /// The match within `lineText` (UTF-16), for highlighting it in the results.
    public let rangeInLineText: NSRange
    /// Where the match starts in its line (UTF-16 offset from the line start) and its length,
    /// cut off at the end of the line; for selecting it after the file is opened.
    public let rangeInLine: NSRange
}

/// Find in Files: which files to search in a folder, and the matches in one file's bytes.
/// The app runs these on a background thread.
public enum FolderSearch {

    public struct Options: Equatable, Sendable {
        public var filter: FileFilter
        public var includesSubfolders: Bool
        /// Skips files and folders whose name starts with "." (.git, .DS_Store …).
        public var skipsHiddenItems: Bool
        /// Larger files are skipped, like the editor refuses to open them.
        public var maximumFileSize: Int

        public init(filter: FileFilter = FileFilter(""), includesSubfolders: Bool = true,
                    skipsHiddenItems: Bool = true, maximumFileSize: Int = 50_000_000) {
            self.filter = filter
            self.includesSubfolders = includesSubfolders
            self.skipsHiddenItems = skipsHiddenItems
            self.maximumFileSize = maximumFileSize
        }
    }

    /// Only this many characters of a line are kept for the results list.
    static let maximumLineTextLength = 300

    /// The files to search in `folder`, sorted by path so results come in a stable order.
    /// Packages (.app, .xcodeproj …) are searched like folders, as the Open panel shows them.
    public static func files(in folder: URL, options: Options) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        var enumeratorOptions: FileManager.DirectoryEnumerationOptions = []
        if options.skipsHiddenItems { enumeratorOptions.insert(.skipsHiddenFiles) }
        if !options.includesSubfolders { enumeratorOptions.insert(.skipsSubdirectoryDescendants) }
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                              options: enumeratorOptions, errorHandler: { _, _ in true })
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = url.lastPathComponent
            if values.isDirectory == true {
                // Symbolic links to folders aren't followed (they could loop).
                if !options.filter.includesFolder(named: name) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  (values.fileSize ?? 0) <= options.maximumFileSize,
                  options.filter.includesFile(named: name) else { continue }
            files.append(url)
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The matches in a file's bytes, with its encoding detected as when opening it. nil for
    /// binary files and files that can't be decoded; [] for text files without a match.
    public static func matches(in data: Data, search: TextSearch) -> [LineMatch]? {
        guard let decoded = try? TextFile.decode(data) else { return nil }
        let text = decoded.text as NSString
        let ranges = search.matches(in: text).filter { $0.length > 0 }   // `^` alone would match every line
        guard !ranges.isEmpty else { return [] }
        let lineIndex = LineIndex(text: text)
        return ranges.map { range in
            let line = lineIndex.line(containing: range.location)
            let content = lineIndex.contentRange(ofLine: line)
            let start = range.location - content.location
            let length = min(range.length, NSMaxRange(content) - range.location)   // a match may run past the line
            let (lineText, offset) = excerpt(of: text, line: content, around: NSRange(location: range.location, length: length))
            let locationInText = range.location - offset
            return LineMatch(line: line, lineText: lineText,
                             rangeInLineText: NSRange(location: locationInText,
                                                      length: max(0, min(length, (lineText as NSString).length - locationInText))),
                             rangeInLine: NSRange(location: start, length: length))
        }
    }

    /// The line's text, or for a long line a piece of it around the match (with "…"), and where
    /// that piece starts in the text, so the match can be found in it.
    private static func excerpt(of text: NSString, line: NSRange, around match: NSRange) -> (String, Int) {
        guard line.length > maximumLineTextLength else {
            return (text.substring(with: line), line.location)
        }
        // Start a little before the match; keep whole characters (no half emoji).
        var start = max(line.location, match.location - 40)
        start = text.rangeOfComposedCharacterSequence(at: start).location
        var end = min(NSMaxRange(line), start + maximumLineTextLength)
        if end < NSMaxRange(line) {
            end = text.rangeOfComposedCharacterSequence(at: end).location
        }
        let prefix = start > line.location ? "…" : ""
        let suffix = end < NSMaxRange(line) ? "…" : ""
        // The "…" before the piece moves the match one place to the right.
        return (prefix + text.substring(with: NSRange(location: start, length: end - start)) + suffix,
                start - (prefix as NSString).length)
    }
}
