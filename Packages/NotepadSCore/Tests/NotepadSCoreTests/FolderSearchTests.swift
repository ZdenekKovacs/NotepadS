import XCTest
@testable import NotepadSCore

final class FolderSearchTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("FolderSearchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func write(_ path: String, _ data: Data) throws {
        let url = folder.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    private func names(_ options: FolderSearch.Options) -> [String] {
        FolderSearch.files(in: folder, options: options).map {
            String($0.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count + 1))
        }
    }

    // MARK: - Files

    func testFilesHiddenSubfoldersAndFilters() throws {
        for path in ["a.swift", "b.txt", "Sub/c.swift", ".git/config", "node_modules/d.swift", "app.min.js", "app.js"] {
            try write(path, Data("x".utf8))
        }
        XCTAssertEqual(names(.init()), ["a.swift", "app.js", "app.min.js", "b.txt", "node_modules/d.swift", "Sub/c.swift"])
        XCTAssertEqual(names(.init(filter: FileFilter("*.SWIFT"))), ["a.swift", "node_modules/d.swift", "Sub/c.swift"])
        XCTAssertEqual(names(.init(filter: FileFilter("*.js, !*.min.js"))), ["app.js"])
        XCTAssertEqual(names(.init(filter: FileFilter("*.swift !node_modules"))), ["a.swift", "Sub/c.swift"])
        XCTAssertEqual(names(.init(filter: FileFilter("*.swift"), includesSubfolders: false)), ["a.swift"])
        XCTAssertTrue(names(.init(skipsHiddenItems: false)).contains(".git/config"))
    }

    func testTooLargeFilesAreSkipped() throws {
        try write("big.txt", Data(repeating: 0x61, count: 2_000))
        try write("small.txt", Data("a".utf8))
        XCTAssertEqual(names(.init(maximumFileSize: 1_000)), ["small.txt"])
    }

    func testFilterSyntax() {
        let filter = FileFilter(" *.py;Makefile  !test_*.py ")
        XCTAssertEqual(filter.includes, ["*.py", "Makefile"])
        XCTAssertEqual(filter.excludes, ["test_*.py"])
        XCTAssertTrue(filter.includesFile(named: "main.py"))
        XCTAssertTrue(filter.includesFile(named: "makefile"))
        XCTAssertFalse(filter.includesFile(named: "test_main.py"))
        XCTAssertFalse(filter.includesFile(named: "main.pyc"))
        XCTAssertTrue(FileFilter("a?.txt").includesFile(named: "ab.txt"))
        XCTAssertFalse(FileFilter("a?.txt").includesFile(named: "abc.txt"))
        XCTAssertTrue(FileFilter("[x].txt").includesFile(named: "[x].txt"), "brackets are literal, not a regex class")
    }

    // MARK: - Matches

    func testMatchesWithLinesAndColumnsInEveryLineBreakStyle() throws {
        let search = try TextSearch(pattern: "needle", options: .init())
        let matches = try XCTUnwrap(FolderSearch.matches(in: Data("a\r\nb needle\rc\n😀 needle needle".utf8), search: search))
        XCTAssertEqual(matches.map(\.line), [1, 3, 3])
        XCTAssertEqual(matches.map(\.lineText), ["b needle", "😀 needle needle", "😀 needle needle"])
        XCTAssertEqual(matches.map(\.rangeInLine), [NSRange(location: 2, length: 6), NSRange(location: 3, length: 6),
                                                    NSRange(location: 10, length: 6)])
        XCTAssertEqual(matches[2].rangeInLineText, matches[2].rangeInLine)
    }

    func testDetectsTheEncodingLikeOpening() throws {
        let search = try TextSearch(pattern: "café", options: .init(ignoresCase: true))
        let windows1252 = Data([0x43, 0x61, 0x66, 0xE9, 0x0D, 0x0A])   // "Café\r\n"
        XCTAssertEqual(FolderSearch.matches(in: windows1252, search: search)?.first?.lineText, "Café")
    }

    func testBinaryFilesAreSkippedAndNoMatchIsEmpty() throws {
        let search = try TextSearch(pattern: "a", options: .init())
        XCTAssertNil(FolderSearch.matches(in: Data([0x00, 0x01, 0x61, 0x00, 0xFF, 0x00]), search: search))
        XCTAssertEqual(FolderSearch.matches(in: Data("xyz".utf8), search: search), [])
    }

    func testRegexAcrossALineBreakIsCutAtTheLineEnd() throws {
        let search = try TextSearch(pattern: "b\\nc", options: .init(isRegularExpression: true))
        let match = try XCTUnwrap(FolderSearch.matches(in: Data("ab\ncd".utf8), search: search)?.first)
        XCTAssertEqual(match.line, 0)
        XCTAssertEqual(match.rangeInLine, NSRange(location: 1, length: 1))
    }

    func testLongLinesAreShortenedAroundTheMatch() throws {
        let line = String(repeating: "x", count: 1_000) + "needle" + String(repeating: "y", count: 1_000)
        let search = try TextSearch(pattern: "needle", options: .init())
        let match = try XCTUnwrap(FolderSearch.matches(in: Data(line.utf8), search: search)?.first)
        XCTAssertLessThanOrEqual(match.lineText.count, FolderSearch.maximumLineTextLength + 2)
        XCTAssertTrue(match.lineText.hasPrefix("…") && match.lineText.hasSuffix("…"))
        XCTAssertEqual((match.lineText as NSString).substring(with: match.rangeInLineText), "needle")
        XCTAssertEqual(match.rangeInLine, NSRange(location: 1_000, length: 6))
    }
}
