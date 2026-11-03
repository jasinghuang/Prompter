import XCTest

/// Compare identical optimized builds on the same simulator/device; do not treat these as phone FPS.
final class ScriptListPerformanceTests: XCTestCase {
    func testRepeatedListScroll() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-seedMany", "-resetDemo", "-resetSettings", "-skipOnboard", "-profileLibraryScroll"]
        app.launch()
        let list = app.tables["script.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        XCTAssertTrue((app.buttons["library.filter"].value as? String ?? "").hasPrefix("共 44 篇稿件，"),
                      "Release 基准须先通过 Debug 测试包准备相同的 44 篇数据")
        var metrics: [XCTMetric] = [XCTOSSignpostMetric.scrollingAndDecelerationMetric,
                                  XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
        if #available(iOS 26.0, *) { metrics.append(XCTHitchMetric(application: app)) }
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: metrics, options: options) {
            for _ in 0..<3 { list.swipeUp(velocity: .fast) }
            for _ in 0..<3 { list.swipeDown(velocity: .fast) }
        }
        XCTAssertFalse(app.buttons["返回"].exists, "滚动不能误开播放页")
    }
}
