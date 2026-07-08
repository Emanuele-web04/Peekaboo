import XCTest
@testable import Peakaboo

final class PanelGeometryTests: XCTestCase {
    func testHotspotsOccupyExactScreenCorners() {
        let frame = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .topLeft), CGRect(x: -1_440, y: 884, width: 16, height: 16))
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .topRight), CGRect(x: -16, y: 884, width: 16, height: 16))
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .bottomLeft), CGRect(x: -1_440, y: 0, width: 16, height: 16))
        XCTAssertEqual(PanelGeometry.hotspot(in: frame, corner: .bottomRight), CGRect(x: -16, y: 0, width: 16, height: 16))
    }

    func testPanelAnchorsInsideVisibleFrame() {
        let frame = CGRect(x: 0, y: 25, width: 1_920, height: 1_030)
        let size = CGSize(width: 340, height: 400)

        XCTAssertEqual(
            PanelGeometry.panelFrame(in: frame, size: size, corner: .topRight),
            CGRect(x: 1_568, y: 643, width: 340, height: 400)
        )
        XCTAssertEqual(
            PanelGeometry.panelFrame(in: frame, size: size, corner: .bottomLeft),
            CGRect(x: 12, y: 37, width: 340, height: 400)
        )
    }

    func testPreferredHeightIsClamped() {
        XCTAssertEqual(PanelGeometry.preferredHeight(taskCount: 0, sectionCount: 0, isComposing: false), PanelGeometry.minimumHeight)
        XCTAssertEqual(PanelGeometry.preferredHeight(taskCount: 100, sectionCount: 3, isComposing: true), PanelGeometry.maximumHeight)
    }
}
