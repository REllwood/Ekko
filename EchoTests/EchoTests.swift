import XCTest
@testable import Echo

final class EchoSmokeTests: XCTestCase {
    func testCatalogIsNotEmpty() {
        XCTAssertFalse(ModelCatalog.all.isEmpty)
    }
}
