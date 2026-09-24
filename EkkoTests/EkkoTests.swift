import XCTest
@testable import Ekko

final class EkkoSmokeTests: XCTestCase {
    func testCatalogIsNotEmpty() {
        XCTAssertFalse(ModelCatalog.all.isEmpty)
    }
}
