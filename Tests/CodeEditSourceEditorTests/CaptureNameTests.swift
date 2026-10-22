import XCTest
@testable import CodeEditSourceEditor

final class CaptureNameTests: XCTestCase {
    func testKnownHighlightCaptures() {
        XCTAssertTrue(CaptureName.isKnown("comment"))
        XCTAssertTrue(CaptureName.isKnown("string.special.key"))
        XCTAssertTrue(CaptureName.isKnown("variable.builtin"))
    }

    func testConventionalIgnoredCapturesAreKnown() {
        XCTAssertTrue(CaptureName.isKnown("injection.content"))
        XCTAssertTrue(CaptureName.isKnown("markup.heading"))
        XCTAssertTrue(CaptureName.isKnown("punctuation.bracket"))
        XCTAssertTrue(CaptureName.isKnown("_private"))
        XCTAssertTrue(CaptureName.isKnown("Conceal"))
    }

    func testUnknownCaptureIsNotKnown() {
        XCTAssertFalse(CaptureName.isKnown("my-plugin.special"))
    }
}
