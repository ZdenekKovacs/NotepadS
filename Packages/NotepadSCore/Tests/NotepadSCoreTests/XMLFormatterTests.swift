import XCTest
@testable import NotepadSCore

final class XMLFormatterTests: XCTestCase {

    private func format(_ text: String, lineEnding: LineEnding = .lf) throws -> String {
        try TextTransform.formatXML.apply(to: text, context: TransformContext(lineEnding: lineEnding, indentation: "  "))
    }

    func testIndentsNestedElementsAndKeepsTextOnOneLine() throws {
        let xml = #"<?xml version="1.0"?><root><item id="1"><name>Ann</name><empty/></item><b></b></root>"#
        XCTAssertEqual(try format(xml), """
        <?xml version="1.0"?>
        <root>
          <item id="1">
            <name>Ann</name>
            <empty/>
          </item>
          <b></b>
        </root>
        """)
    }

    func testCopiesTagsCommentsCDATAAndTextExactly() throws {
        let xml = "<a  x = 'b>c'>\r\n   <!-- a <comment> -->\r\n<![CDATA[ <raw> & ]]>  <t>Žluťoučký 😀 &amp;</t></a>\r\n"
        XCTAssertEqual(try format(xml, lineEnding: .crlf),
                       "<a  x = 'b>c'>\r\n  <!-- a <comment> -->\r\n  <![CDATA[ <raw> & ]]>\r\n  <t>Žluťoučký 😀 &amp;</t>\r\n</a>\r\n")
    }

    func testMixedContentAndDoctype() throws {
        let xml = "<!DOCTYPE note [<!ELEMENT note (#PCDATA)>]><p>Hello <b>you</b> there</p>"
        XCTAssertEqual(try format(xml), """
        <!DOCTYPE note [<!ELEMENT note (#PCDATA)>]>
        <p>
          Hello
          <b>you</b>
          there
        </p>
        """)
    }

    func testMinifyRemovesOnlyWhitespaceBetweenTags() throws {
        let xml = "<a>\n  <b x=\"1\">  text  </b>\n  <!-- c -->\n</a>\n"
        XCTAssertEqual(try TextTransform.minifyXML.apply(to: xml, context: .init(lineEnding: .lf)),
                       #"<a><b x="1">text</b><!-- c --></a>"#)
    }

    func testErrorsWithLineAndColumn() {
        XCTAssertThrowsError(try format("<a>\n  <b>\n</a>")) { error in
            let error = error as? TransformError
            XCTAssertEqual(error?.line, 3)
            XCTAssertEqual(error?.column, 1)
            XCTAssertEqual(error?.message, "Expected “</b>”, found “</a>”.")
        }
        XCTAssertThrowsError(try format("<a>\n<!-- never")) { XCTAssertEqual(($0 as? TransformError)?.line, 2) }
        XCTAssertThrowsError(try format("<a><br></a>"), "HTML-style unclosed tags aren't XML")
        XCTAssertThrowsError(try format("é <a/>")) { XCTAssertEqual(($0 as? TransformError)?.column, 1) }
        XCTAssertThrowsError(try format("<a x='1'"))
        XCTAssertThrowsError(try format("</a>"))
    }

    func testAllWhitespaceInputStaysEmpty() throws {
        XCTAssertEqual(try format("  \n"), "\n")
    }
}
