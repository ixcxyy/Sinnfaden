import XCTest
@testable import KlarApp

final class HoverGeometryTests: XCTestCase {
    func testPointerIsTheBodyCenterIndependentOfExplanationLength() {
        let pointer = CGPoint(x: 600, y: 400)
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 900)
        for height: CGFloat in [180, 260, 420] {
            let frame = AnnotationGeometry.centred(size: CGSize(width: 320, height: height),
                                                   around: pointer, boundary: bounds)
            XCTAssertEqual(frame.midX, pointer.x, accuracy: 0.1)
            XCTAssertEqual(frame.midY, pointer.y, accuracy: 0.1)
        }
    }
}
