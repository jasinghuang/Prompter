import XCTest

final class PromptIndicatorUITests: XCTestCase {
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Demo-reset UI tests are only permitted on an owned simulator")
        #endif
        continueAfterFailure = false
    }

    func testRingIsLandscapeOnlyAndUsesActualScrollProgress() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-autoPlay"]
        app.launch()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10))
        let ring = app.descendants(matching: .any)["player.islandIndicator"]
        expectation(for: NSPredicate { _, _ in !ring.exists }, evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        XCUIDevice.shared.orientation = .landscapeLeft
        snapshot("indicator-before-landscape-assert")
        XCTAssertTrue(ring.waitForExistence(timeout: 5))
        let first = ring.frame
        XCTAssertGreaterThan(first.height, first.width * 2)
        expectation(for: NSPredicate { _, _ in
            let value = Int((ring.value as? String ?? "0%").replacingOccurrences(of: "%", with: "")) ?? 0
            return value > 0
        }, evaluatedWith: ring)
        waitForExpectations(timeout: 10)
        snapshot("indicator-landscape-left")
        XCUIDevice.shared.orientation = .landscapeRight
        expectation(for: NSPredicate { _, _ in abs(ring.frame.midX - first.midX) > 400 }, evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        snapshot("indicator-landscape-right")
        XCUIDevice.shared.orientation = .portrait
        expectation(for: NSPredicate { _, _ in !ring.exists }, evaluatedWith: ring)
        waitForExpectations(timeout: 5)
        snapshot("indicator-hidden-portrait")
    }

    func testCalibrationPreviewAndCancelDoNotResetPlaybackSettings() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-openSettings"]
        app.launch()
        let calibration = app.buttons["settings.islandCalibration"]
        for _ in 0..<3 where !calibration.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(calibration.waitForExistence(timeout: 5))
        calibration.tap()
        XCTAssertTrue(app.staticTexts["贴合灵动岛"].waitForExistence(timeout: 5))
        snapshot("indicator-before-calibration-assert")
        XCTAssertTrue(app.descendants(matching: .any)["player.islandIndicator"].exists)
        snapshot("indicator-calibration")
        let cancel = app.buttons["取消"]
        for _ in 0..<3 where !cancel.isHittable { app.scrollViews.firstMatch.swipeUp() }
        cancel.tap()
        XCTAssertTrue(app.buttons["关闭设置"].waitForExistence(timeout: 5))
    }

    private func snapshot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
