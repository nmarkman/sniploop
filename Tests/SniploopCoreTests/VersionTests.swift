import XCTest
@testable import SniploopCore

final class VersionTests: XCTestCase {
    func testCoreVersionIsSet() {
        XCTAssertEqual(Sniploop.coreVersion, "0.1.0")
    }
}
