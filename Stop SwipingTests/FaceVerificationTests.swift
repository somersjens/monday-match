import XCTest
@testable import Stop_Swiping

@MainActor
final class FaceVerificationTests: XCTestCase {
    func testReceiptIsBoundToBothPhotoIDAndExactContents() {
        let id = UUID()
        let data = Data([1, 2, 3])
        let receipt = PhotoVerificationReceipt(photoID: id, imageData: data, outcome: .match)
        XCTAssertTrue(receipt.belongs(to: id, imageData: data))
        XCTAssertFalse(receipt.belongs(to: UUID(), imageData: data))
        XCTAssertFalse(receipt.belongs(to: id, imageData: Data([1, 2, 4])))
    }
}
