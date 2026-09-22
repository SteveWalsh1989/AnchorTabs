import XCTest

@testable import anchorTabs

@MainActor
final class PinnedTabGeometryTests: XCTestCase {
  func testPlacesOnlyThreePointsBetweenPinnedTabs() {
    let geometry = PinnedTabGeometry(widths: [60, 80, 40], trailingSpacing: 1_800)

    XCTAssertEqual(geometry.frames[0].minX, 0)
    XCTAssertEqual(geometry.frames[1].minX, 63)
    XCTAssertEqual(geometry.frames[2].minX, 146)
    XCTAssertEqual(geometry.contentWidth, 186)
  }

  func testAppendsTrailingSpacingAfterFinalPinnedTab() {
    let geometry = PinnedTabGeometry(widths: [60, 80, 40], trailingSpacing: 1_800)

    XCTAssertEqual(geometry.frames.last?.maxX, 186)
    XCTAssertEqual(geometry.totalWidth, 1_986)
  }

  func testHitTestingExcludesInterTabAndTrailingSpacing() {
    let geometry = PinnedTabGeometry(widths: [60, 80], trailingSpacing: 1_800)

    XCTAssertEqual(geometry.index(at: CGPoint(x: 30, y: 10)), 0)
    XCTAssertNil(geometry.index(at: CGPoint(x: 61, y: 10)))
    XCTAssertEqual(geometry.index(at: CGPoint(x: 100, y: 10)), 1)
    XCTAssertNil(geometry.index(at: CGPoint(x: 500, y: 10)))
  }

  func testEmptyStripDoesNotAllocateTrailingSpacing() {
    let geometry = PinnedTabGeometry(widths: [], trailingSpacing: 1_800)

    XCTAssertTrue(geometry.frames.isEmpty)
    XCTAssertEqual(geometry.contentWidth, 0)
    XCTAssertEqual(geometry.totalWidth, 0)
  }
}
