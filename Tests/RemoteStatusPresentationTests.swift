import XCTest
@testable import Redmargin

final class RemoteStatusPresentationTests: XCTestCase {
    func testConnectingWithContentShowsNonDimmingPill() {
        let presentation = RemoteStatusPresentation(.connecting, host: "devtest", hasContent: true)
        XCTAssertEqual(presentation.style, .pill)
        XCTAssertFalse(presentation.dimsContent)
        XCTAssertFalse(presentation.showsRetry)
    }

    func testConnectingWithoutContentShowsPlaceholder() {
        let presentation = RemoteStatusPresentation(.connecting, host: "devtest", hasContent: false)
        XCTAssertEqual(presentation.style, .placeholder)
        XCTAssertTrue(presentation.showsBackdrop)
    }

    func testNoRouteShowsRetry() {
        let presentation = RemoteStatusPresentation(.unavailable(.noRoute), host: "wraith", hasContent: true)
        XCTAssertEqual(presentation.style, .pill)
        XCTAssertFalse(presentation.dimsContent)
        XCTAssertTrue(presentation.showsRetry)
        XCTAssertTrue(presentation.label.contains("wraith"), "Label is host-named")
    }

    func testConnectedShowsNothing() {
        let presentation = RemoteStatusPresentation(.connected, host: "devtest", hasContent: true)
        XCTAssertEqual(presentation.style, .none)
    }
}
