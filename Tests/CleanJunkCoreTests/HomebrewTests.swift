import Foundation
import XCTest
@testable import CleanJunkCore

final class HomebrewTests: XCTestCase {
    func testHomebrewV2InventoryDecoding() throws {
        let json = """
        {
          "formulae": [{
            "name": "openssl@3", "desc": "TLS",
            "dependencies": [],
            "installed": [{
              "version": "3.0.1",
              "installed_on_request": false,
              "installed_as_dependency": true,
              "runtime_dependencies": []
            }]
          }],
          "casks": [{"token": "visual-studio-code", "name": ["Visual Studio Code"]}]
        }
        """
        let result = try JSONDecoder().decode(BrewInventory.self, from: Data(json.utf8))
        XCTAssertEqual(result.formulae.first?.name, "openssl@3")
        XCTAssertEqual(result.formulae.first?.installed.first?.installed_on_request, false)
        XCTAssertEqual(result.casks.count, 1)
    }
}
