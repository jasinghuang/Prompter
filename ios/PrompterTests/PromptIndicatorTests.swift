import XCTest
import CoreGraphics
@testable import Prompter

final class PromptIndicatorTests: XCTestCase {
    func testIPhone16ProGeometryRotatesToBothEdgesAndHidesInPortrait() throws {
        let size = CGSize(width: 874, height: 402)
        let left = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: true, model: "iPhone17,1"))
        let right = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: false, model: "iPhone17,1"))
        XCTAssertEqual(left.midY, 201)
        XCTAssertEqual(left.midX + right.midX, size.width, accuracy: 0.001)
        XCTAssertEqual(left.width, right.width)
        XCTAssertGreaterThan(left.height, left.width * 3)
        XCTAssertEqual(left.midX, (7.71 - 2.44) * 402 / 66.57, accuracy: 0.001)
        XCTAssertNil(IslandIndicatorGeometry.frame(size: CGSize(width: 402, height: 874), cameraOnLeft: true, model: "iPhone17,1"))
        let path = IslandIndicatorGeometry.path(in: left)
        var first: CGPoint?
        path.applyWithBlock { pointer in
            if first == nil && pointer.pointee.type == .moveToPoint { first = pointer.pointee.points[0] }
        }
        XCTAssertEqual(try XCTUnwrap(first).x, left.midX, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(first).y, left.minY, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.width, left.width, accuracy: 0.001)
        XCTAssertEqual(path.boundingBoxOfPath.height, left.height, accuracy: 0.001)
    }

    func testCalibrationChangesOnlyGeometryAndNormalizesCorruptValues() throws {
        let invalid = IslandIndicatorCalibration(edgeOffset: .nan, verticalOffset: 999, lengthAdjustment: -999, thicknessAdjustment: .infinity).normalized
        XCTAssertEqual(invalid.edgeOffset, 0); XCTAssertEqual(invalid.verticalOffset, 24)
        XCTAssertEqual(invalid.lengthAdjustment, -24); XCTAssertEqual(invalid.thicknessAdjustment, 0)
        let size = CGSize(width: 874, height: 402)
        let original = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: false, model: "iPhone17,1"))
        let moved = try XCTUnwrap(IslandIndicatorGeometry.frame(size: size, cameraOnLeft: false, model: "iPhone17,1",
                                                                calibration: .init(edgeOffset: 4, verticalOffset: 3, lengthAdjustment: 6, thicknessAdjustment: 2)))
        XCTAssertEqual(moved.midX, original.midX - 4, accuracy: 0.001)
        XCTAssertEqual(moved.midY, original.midY + 3, accuracy: 0.001)
        XCTAssertEqual(moved.height, original.height + 6, accuracy: 0.001)
        XCTAssertEqual(moved.width, original.width + 2, accuracy: 0.001)
    }

    @MainActor
    func testReadingProgressCanGoBackAfterCompletionWithoutConfusingLateLayoutReports() {
        let progress = PromptReadingProgress()
        progress.update(0.97); progress.complete(); progress.update(0.97)
        XCTAssertTrue(progress.completed); XCTAssertEqual(progress.value, 1)
        progress.update(0.7)
        XCTAssertFalse(progress.completed); XCTAssertEqual(progress.value, 0.7)
        progress.update(0)
        XCTAssertEqual(progress.value, 0)
    }

    @MainActor
    func testCalibrationPersistsLocallyAndIsExcludedFromTransferSettings() throws {
        let suite = "indicator-test-\(UUID())"; let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.islandCalibration = .init(edgeOffset: 3, lengthAdjustment: 4)
        settings.flush()
        XCTAssertEqual(AppSettings(defaults: defaults).islandCalibration.edgeOffset, 3)
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(settings.data), encoding: .utf8))
        XCTAssertFalse(json.contains("islandCalibration"))
        XCTAssertTrue(try JSONDecoder().decode(SettingsData.self, from: Data("{}".utf8)).islandIndicatorEnabled)
    }
}
