import XCTest
@testable import RedmarginCore

final class AppVersionTests: XCTestCase {
    func testVersionUsesBundleShortVersion() {
        let version = AppVersion.value(from: [
            "CFBundleShortVersionString": "1.5.0",
            "CFBundleVersion": "42"
        ])

        XCTAssertEqual(version, "1.5.0")
    }

    func testVersionFallsBackToBundleVersion() {
        let version = AppVersion.value(from: [
            "CFBundleVersion": "42"
        ])

        XCTAssertEqual(version, "42")
    }

    func testVersionFallsBackWhenBundleHasNoVersion() {
        let version = AppVersion.value(from: [:])

        XCTAssertEqual(version, "0.0.0")
    }
}
