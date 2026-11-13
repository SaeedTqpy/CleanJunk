import Foundation
import XCTest
@testable import CleanJunkCore

final class InstallerReceiptInspectorTests: XCTestCase {
    func testReceiptsAreDeduplicatedAndSorted() {
        let input = """
        com.apple.pkg.CLTools_Executables
        com.example.vendor.app
        com.apple.pkg.CLTools_Executables

        # ignored comment
        """
        XCTAssertEqual(InstallerReceiptInspector.parse(input), [
            "com.apple.pkg.CLTools_Executables",
            "com.example.vendor.app"
        ])
    }

    func testReadOnlyPackageEvidenceDoesNotAuthorizeRemoval() {
        let result = DeepStorageClassifier.classify(
            path: "/opt/homebrew/Cellar/python@3.14/3.14.0/bin/python3",
            home: "/Users/fixture"
        )
        XCTAssertEqual(result.category, .installedPackage)
        XCTAssertEqual(result.advice, .preserve)
        XCTAssertEqual(result.owner, "python@3.14")
        XCTAssertFalse(result.advice.isDeletionAuthorized)
    }

    func testMacOSApplicationsStayProtected() {
        let result = DeepStorageClassifier.classify(
            path: "/Applications/Safari.app/Contents/MacOS/Safari",
            home: "/Users/fixture"
        )
        XCTAssertEqual(result.category, .application)
        XCTAssertEqual(result.owner, "Safari.app")
        XCTAssertEqual(result.advice, .preserve)
    }
}
