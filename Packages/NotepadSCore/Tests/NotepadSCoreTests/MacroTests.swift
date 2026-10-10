import XCTest
@testable import NotepadSCore

final class MacroTests: XCTestCase {

    func testTypingIsJoinedButCommandsSeparateIt() {
        var macro = Macro()
        for piece in ["H", "é", "😀"] { macro.append(.insert(piece)) }
        macro.append(.keyCommand("insertNewline:"))
        macro.append(.insert("x"))
        macro.append(.clipboard("paste:"))
        macro.append(.transform("uppercase"))
        macro.append(.lineCommand("duplicate"))
        XCTAssertEqual(macro.steps, [.insert("Hé😀"), .keyCommand("insertNewline:"), .insert("x"), .clipboard("paste:"),
                                     .transform("uppercase"), .lineCommand("duplicate")])
        XCTAssertTrue(Macro().isEmpty)
    }
}
