import XCTest
import UIKit

final class PlayerUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(player: Bool = false, landscape: Bool = false, extra: [String] = []) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        app.launchArguments = ["-seedDemo", "-skipOnboard", "-resetSettings", "-resetDemo"]
            + (player ? ["-openPlayer"] : []) + extra
        app.launch()
        XCTAssertTrue(app.buttons[player ? "返回" : "新建稿件"].waitForExistence(timeout: 10))
    }
    private func snapshot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func waitForCount(_ count: Int) {
        let filter = app.buttons["library.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value BEGINSWITH %@", "共 \(count) 篇稿件，"), evaluatedWith: filter)
        waitForExpectations(timeout: 5)
    }
    private func deleteFirst() {
        app.buttons.matching(identifier: "card").firstMatch.swipeLeft()
        app.buttons["删除"].tap()
    }
    private func revealInEditor(_ element: XCUIElement) {
        for _ in 0..<4 {
            if element.isHittable { return }
            app.scrollViews["editor.form"].swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }
    private func waitForStableFrame(_ element: XCUIElement) {
        var lastFrame = CGRect.null
        var steadySamples = 0
        let stable = NSPredicate { _, _ in
            guard element.exists && element.isHittable else { return false }
            let frame = element.frame
            steadySamples = frame == lastFrame ? steadySamples + 1 : 0
            lastFrame = frame
            return steadySamples >= 2
        }
        expectation(for: stable, evaluatedWith: element)
        waitForExpectations(timeout: 5)
    }
    private func assertPlayerToolbarOrder() {
        let elements = [app.buttons["返回"], app.buttons["player.returnToTop"], app.buttons["player.mirror"],
                        app.buttons["player.filmed"], app.buttons["player.settings"]]
        for pair in zip(elements, elements.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.frame.maxX, pair.1.frame.minX)
            XCTAssertEqual(pair.0.frame.midY, pair.1.frame.midY, accuracy: 1)
        }
    }
    private func assertParameterTrackWidths(landscape: Bool) {
        let font = app.sliders["player.slider.字号"]
        let speed = app.sliders["player.slider.速度"]
        if landscape {
            XCTAssertGreaterThan(speed.frame.width, font.frame.width * 1.4,
                                 "横屏时速度滑杆应更长")
        } else {
            XCTAssertEqual(speed.frame.width, font.frame.width, accuracy: 1,
                           "竖屏两行滑杆应等长")
            XCTAssertEqual(speed.frame.minX, font.frame.minX, accuracy: 1)
        }
    }
    private func play() { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }

    func testLibrarySearchExpandsFiltersAndCancelsInBothOrientations() {
        for landscape in [false, true] {
            launch(landscape: landscape)
            let field = app.textFields["script.search"]
            XCTAssertFalse(field.exists)
            let list = app.tables["script.list"]
            XCTAssertEqual(list.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 1,
                           "列表应延伸到屏幕底部，而非在安全区上方截断")
            snapshot(landscape ? "library-compact-landscape" : "library-compact-portrait")
            app.buttons["library.search"].tap()
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
            field.typeText("VIP")
            expectation(for: NSPredicate { _, _ in
                self.app.buttons.matching(identifier: "card").count == 1
            }, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            snapshot(landscape ? "library-search-landscape" : "library-search-portrait")
            app.buttons["library.search.cancel"].tap()
            XCTAssertFalse(field.exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            XCTAssertTrue((app.buttons["library.filter"].value as? String ?? "").contains("当前 4 篇"))
        }
    }

    func testLibraryLastRowCanScrollAboveSelectionShelf() {
        launch(extra: ["-seedMany"])
        app.buttons.matching(identifier: "card").firstMatch.press(forDuration: 0.8)
        let all = app.buttons["select.all"]
        XCTAssertTrue(all.waitForExistence(timeout: 3))
        let list = app.tables["script.list"]
        for _ in 0..<10 { list.swipeUp(velocity: .fast) }
        let lastRow = list.cells.element(boundBy: list.cells.count - 1)
        XCTAssertTrue(lastRow.isHittable)
        XCTAssertLessThanOrEqual(lastRow.frame.maxY, all.frame.minY,
                                "末张卡片应能完整滚到批量操作栏上方")
        snapshot("library-last-row-above-actions")
    }

    private func dragPlayerBack(to fraction: CGFloat, hold: TimeInterval = 0.1) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            .press(forDuration: 0.05,
                   thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: hold)
    }

    private func revealAirPodsSettings() {
        let toggle = app.switches["settings.airPodsNod"]
        let calibrate = app.buttons["settings.calibrateNod"]
        for _ in 0..<14 {
            if toggle.isHittable && calibrate.isHittable { return }
            let scroll = app.scrollViews["settings.scroll"]
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.85))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.60)),
                       withVelocity: .slow, thenHoldForDuration: 0.05)
        }
    }

    func testAirPodsNodDefaultsOffAndCalibrationCanCancel() {
        launch(player: true, extra: ["-openSettings"])
        let toggle = app.switches["settings.airPodsNod"]
        revealAirPodsSettings()
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch.exists,
                       "默认关闭时不得提前弹出运动权限请求")
        snapshot("airpods-settings-default-off")
        toggle.tap()
        XCTAssertTrue(app.buttons["nod.cancelCalibration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["轻轻低头"].exists)
        snapshot("airpods-six-action-guide")
        app.buttons["nod.startCalibration"].tap()
        // Simulator has no headphone motion; the guide must remain truthful and cancellable.
        XCTAssertTrue(app.staticTexts["nod.calibrationError"].waitForExistence(timeout: 5))
        snapshot("airpods-hardware-unavailable")
        app.buttons["nod.cancelCalibration"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "取消首次校准不得悄悄开启")
        app.buttons["关闭设置"].tap()
        play()
        XCTAssertTrue(app.sliders["字号"].waitForNonExistence(timeout: 3))
        play()
        XCTAssertTrue(app.sliders["字号"].waitForExistence(timeout: 3))
    }

    func testAirPodsSettingsLandscape() {
        launch(player: true, landscape: true, extra: ["-openSettings"])
        let toggle = app.switches["settings.airPodsNod"]
        revealAirPodsSettings()
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        snapshot("airpods-settings-landscape")
        app.buttons["settings.calibrateNod"].tap()
        XCTAssertTrue(app.buttons["nod.cancelCalibration"].waitForExistence(timeout: 5))
        snapshot("airpods-guide-landscape")
        app.buttons["nod.cancelCalibration"].tap()
        XCTAssertTrue(app.buttons["关闭设置"].waitForExistence(timeout: 5))
    }

    private func openCalibrationDemo(landscape: Bool = false, extra: [String] = []) {
        launch(player: true, landscape: landscape, extra: ["-openSettings", "-simulateNodCalibration"] + extra)
        revealAirPodsSettings()
        app.buttons["settings.calibrateNod"].tap()
        XCTAssertTrue(app.buttons["nod.cancelCalibration"].waitForExistence(timeout: 5))
    }
    private func completeCalibrationAction() {
        let start = app.buttons["nod.startCalibration"]
        start.tap()
        let ready = NSPredicate(format: "isEnabled == true")
        expectation(for: ready, evaluatedWith: start)
        waitForExpectations(timeout: 12)
    }

    private func completePersonalCalibration() {
        snapshot("calibration-habit-ready")
        for index in 0..<3 {
            XCTAssertTrue(app.buttons["nod.startCalibration"].label.contains("自然点头 \(index + 1)/3"))
            completeCalibrationAction()
            XCTAssertFalse(app.staticTexts["nod.calibrationError"].exists)
        }
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "试一次点头")
        snapshot("calibration-habit-independent-verification")
        completeCalibrationAction()
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "完成并开启")
    }

    private func openNodDiagnostics() {
        let entry = app.buttons["settings.nodDiagnostics"]
        let scroll = app.scrollViews["settings.scroll"]
        for _ in 0..<16 {
            if entry.isHittable { break }
            // Short drags avoid jumping past the row in the shallow landscape panel.
            let towardTop = entry.exists && entry.frame.midY < scroll.frame.midY
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: towardTop ? 0.35 : 0.80))
                .press(forDuration: 0.05, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: towardTop ? 0.65 : 0.50)),
                       withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.switches["nod.diagnosticsRecording"].waitForExistence(timeout: 5))
    }

    private func revealInDiagnostics(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.scrollViews["nod.diagnosticsScroll"].swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    func testGuidedCalibrationAllSixActionsAndVerification() {
        openCalibrationDemo()
        snapshot("calibration-redesign-ready-synthetic")
        for index in 0..<6 {
            completeCalibrationAction()
            XCTAssertFalse(app.staticTexts["nod.calibrationError"].exists)
            XCTAssertTrue(app.buttons["nod.step.\(index)"].label.contains("已记录"))
            if index == 0 {
                XCTAssertEqual(app.staticTexts["nod.action"].label, "轻轻抬头")
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "nod.stepNumber").firstMatch.label, "动作 2，共 6 个")
                XCTAssertFalse(app.staticTexts["这个动作已完成"].exists)
                snapshot("calibration-redesign-step-done-synthetic")
            }
        }
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "开始：自然点头 1/3")
        snapshot("calibration-redesign-final-test-synthetic")
        completePersonalCalibration()
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "完成并开启")
        snapshot("calibration-redesign-verified-synthetic")
        app.buttons["nod.startCalibration"].tap()
        XCTAssertTrue(app.switches["settings.airPodsNod"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["settings.airPodsNod"].value as? String, "1")
    }

    func testGuidedCalibrationRetriesOnlyIncorrectAction() {
        openCalibrationDemo(extra: ["-calibrationBadUpOnce"])
        completeCalibrationAction()
        completeCalibrationAction()
        XCTAssertTrue(app.staticTexts["nod.calibrationError"].exists)
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "只重试抬头")
        XCTAssertTrue(app.buttons["nod.step.0"].label.contains("已记录"))
        XCTAssertFalse(app.buttons["nod.step.1"].label.contains("已记录"))
        snapshot("calibration-redesign-specific-retry-synthetic")
        completeCalibrationAction()
        XCTAssertFalse(app.staticTexts["nod.calibrationError"].exists)
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "继续：右歪头")
        XCTAssertTrue(app.buttons["nod.step.0"].label.contains("已记录"))
        XCTAssertTrue(app.buttons["nod.step.1"].label.contains("已记录"))
        snapshot("calibration-redesign-recovered-synthetic")
        app.buttons["nod.cancelCalibration"].tap()
        XCTAssertEqual(app.switches["settings.airPodsNod"].value as? String, "0")
    }

    func testGuidedCalibrationLandscapeLayout() {
        openCalibrationDemo(landscape: true)
        XCTAssertTrue(app.buttons["nod.startCalibration"].isHittable)
        snapshot("calibration-redesign-landscape-ready-synthetic")
        completeCalibrationAction()
        XCTAssertTrue(app.buttons["nod.startCalibration"].isHittable)
        snapshot("calibration-redesign-landscape-done-synthetic")
        app.buttons["nod.cancelCalibration"].tap()
    }

    func testNodActuallyStartsAndPausesPlayerAfterSavingCalibration() {
        openCalibrationDemo(extra: ["-simulateNodPlayback", "-simulateLargeNodCalibration", "-simulateNaturalNodPlayback", "-simulateNodRestShift", "-simulateEarHandoff"])
        for _ in 0..<6 { completeCalibrationAction() }
        completePersonalCalibration() // Explicit learning and independent verification, before enabling.
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "完成并开启")
        app.buttons["nod.startCalibration"].tap()
        XCTAssertTrue(app.switches["settings.airPodsNod"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["settings.airPodsNod"].value as? String, "1")
        openNodDiagnostics()
        let recording = app.switches["nod.diagnosticsRecording"]
        XCTAssertEqual(recording.value as? String, "0")
        recording.tap()
        snapshot("nod-diagnostics-recording")
        app.buttons["nod.closeDiagnostics"].tap()
        app.buttons["关闭设置"].tap()
        XCTAssertTrue(app.staticTexts["player.nodStatus"].waitForExistence(timeout: 5))
        let status = app.buttons["player.returnToTop"]
        dragPlayerBack(to: 0.15, hold: 0.4)
        XCTAssertTrue(status.exists, "取消返回后应继续接收耳机点头事件")
        expectation(for: NSPredicate(format: "value CONTAINS %@", "提词中"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.sliders["player.slider.字号"].exists)
        snapshot("nod-playback-started-from-motion-synthetic")
        expectation(for: NSPredicate(format: "value CONTAINS %@", "已暂停"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.sliders["player.slider.字号"].exists)
        XCTAssertNotEqual(app.staticTexts["player.elapsed"].label, "00:00")
        snapshot("nod-playback-paused-from-motion-synthetic")
        app.buttons["player.settings"].tap()
        openNodDiagnostics()
        XCTAssertEqual(app.staticTexts["nod.count.detected"].label, "2")
        XCTAssertEqual(app.staticTexts["nod.count.applied"].label, "2")
        XCTAssertEqual(app.staticTexts["nod.count.sensorChanges"].label, "1")
        recording.tap() // Stop sampling; manual annotations must still be available.
        snapshot("nod-diagnostics-two-responses")
        revealInDiagnostics(app.buttons["nod.markMiss"]); app.buttons["nod.markMiss"].tap()
        app.buttons["nod.markFalsePositive"].tap()
        XCTAssertEqual(app.staticTexts["nod.count.misses"].label, "1")
        XCTAssertEqual(app.staticTexts["nod.count.falsePositives"].label, "1")
        XCTAssertFalse(app.buttons["nod.markFalsePositive"].isEnabled)
        revealInDiagnostics(app.buttons["nod.undoMark"]); app.buttons["nod.undoMark"].tap()
        XCTAssertEqual(app.staticTexts["nod.count.falsePositives"].label, "0")
        app.buttons["nod.undoMark"].tap()
        XCTAssertEqual(app.staticTexts["nod.count.misses"].label, "0")
        revealInDiagnostics(app.buttons["nod.exportDiagnostics"])
        snapshot("nod-diagnostics-events-and-export")
        app.buttons["nod.clearDiagnostics"].tap()
        XCTAssertEqual(app.staticTexts["nod.count.applied"].label, "0")
        app.buttons["nod.closeDiagnostics"].tap()
        app.buttons["关闭设置"].tap()
    }

    func testNodDiagnosticsLandscapeUsesReadableNativeSheet() {
        openCalibrationDemo(landscape: true)
        for _ in 0..<6 { completeCalibrationAction() }
        completePersonalCalibration()
        XCTAssertEqual(app.buttons["nod.startCalibration"].label, "完成并开启")
        app.buttons["nod.startCalibration"].tap()
        XCTAssertTrue(app.buttons["nod.cancelCalibration"].waitForNonExistence(timeout: 5))
        openNodDiagnostics()
        let recording = app.switches["nod.diagnosticsRecording"]
        XCTAssertTrue(recording.isHittable); recording.tap()
        snapshot("nod-diagnostics-landscape")
        revealInDiagnostics(app.buttons["nod.markMiss"])
        XCTAssertTrue(app.buttons["nod.markMiss"].isHittable)
        app.buttons["nod.closeDiagnostics"].tap()
        XCTAssertTrue(app.buttons["关闭设置"].waitForExistence(timeout: 5))
    }

    func testFinalCalibrationCanSkipHabitsAndKeepTheSixRecordedActions() {
        openCalibrationDemo()
        for _ in 0..<6 { completeCalibrationAction() }
        app.buttons["nod.skipHabit"].tap()
        let save = app.buttons["nod.startCalibration"]
        expectation(for: NSPredicate(format: "label == %@ AND isEnabled == true", "完成并开启"), evaluatedWith: save)
        waitForExpectations(timeout: 12)
        snapshot("calibration-default-skipped-habit")
        for index in 0..<6 { XCTAssertTrue(app.buttons["nod.step.\(index)"].label.contains("已记录")) }
        save.tap()
        XCTAssertEqual(app.switches["settings.airPodsNod"].value as? String, "1")
    }

    func testPlayerLandscape() {
        launch(player: true, landscape: true)
        assertPlayerToolbarOrder()
        assertParameterTrackWidths(landscape: true)
        snapshot("player-landscape-paused")
        play()
        XCTAssertTrue(app.sliders["字号"].waitForNonExistence(timeout: 3), "播放时底部参数栏应隐藏")
        snapshot("player-landscape-playing")
        sleep(2)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.sliders["字号"].waitForExistence(timeout: 3))
        snapshot("player-landscape-paused-again")
    }
    func testPlayerPortrait() {
        launch(player: true)
        XCTAssertTrue(app.sliders["字号"].isHittable)
        assertPlayerToolbarOrder()
        assertParameterTrackWidths(landscape: false)
        XCTAssertFalse(app.buttons["player.play"].exists)
        XCTAssertTrue(app.buttons["前置镜子"].isHittable)
        XCTAssertTrue(app.buttons["player.filmed"].isHittable)
        XCTAssertFalse(app.buttons["更多播放操作"].exists)
        XCTAssertFalse(app.buttons["编辑稿件"].exists)
        XCTAssertFalse(app.buttons["操作提示"].exists)
        snapshot("player-portrait")
        play()
        XCTAssertTrue(app.sliders["字号"].waitForNonExistence(timeout: 3))
        snapshot("player-portrait-playing")
        play()
        XCTAssertTrue(app.sliders["字号"].waitForExistence(timeout: 3))
    }
    func testSettingsDrawerLandscape() {
        launch(player: true, landscape: true, extra: ["-openSettings"])
        XCTAssertTrue(app.buttons["关闭设置"].waitForExistence(timeout: 5))
        snapshot("settings-landscape")
    }
    func testSettingsDrawerDragToDismiss() {
        launch(player: true, landscape: true, extra: ["-openSettings"])
        let close = app.buttons["关闭设置"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let slider = app.sliders["slider.字号"], before = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.7)
        XCTAssertTrue(close.exists, "调节滑杆不能收起抽屉")
        XCTAssertNotEqual(before, slider.value as? String)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3), "等待面板关闭，避免重开点击落在退出动画上")
        app.buttons["设置"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let title = app.staticTexts["设置"].firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: title.minX - 34, dy: title.midY))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: title.minX + 170, dy: title.midY)),
                   withVelocity: .fast, thenHoldForDuration: 0.02)
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 3))
        XCTAssertFalse(close.exists)
    }
    func testSettingsPortraitUsesSheet() {
        launch(player: true)
        app.buttons["设置"].tap()
        XCTAssertTrue(app.buttons["关闭设置"].waitForExistence(timeout: 5))
        let slider = app.sliders["slider.字号"]
        slider.adjust(toNormalizedSliderPosition: 0.4)
        XCTAssertTrue(app.buttons["关闭设置"].exists)
        snapshot("settings-portrait")
        app.buttons["关闭设置"].tap()
        XCTAssertTrue(app.sliders["字号"].isHittable)
    }
    func testSettingsDrawerCancelledDragReturnsToItsOriginalPosition() {
        launch(player: true, landscape: true, extra: ["-openSettings"])
        let close = app.buttons["关闭设置"]
        let original = close.frame
        let title = app.staticTexts["设置"].firstMatch.frame
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: title.minX - 34, dy: title.midY))
        start.press(forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: title.minX + 6, dy: title.midY)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.frame.minX, original.minX, accuracy: 1)
        snapshot("drawer-cancelled-drag-returned")
        app.sliders["slider.字号"].adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 3))
        app.buttons["player.settings"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertEqual(close.frame.minX, original.minX, accuracy: 1)
    }

    func testHelpAppearsAfterSettingsDismissalInBothOrientations() {
        for landscape in [false, true] {
            launch(player: true, landscape: landscape, extra: ["-openSettings"])
            let help = app.buttons["settings.help"]
            for _ in 0..<12 {
                if help.isHittable { break }
                app.scrollViews["settings.scroll"].swipeUp()
            }
            XCTAssertTrue(help.isHittable)
            help.tap()
            let done = app.buttons["知道了"]
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["关闭设置"].exists)
            let instruction = app.staticTexts["player.onboardingInstruction"]
            XCTAssertTrue(instruction.exists)
            XCTAssertGreaterThanOrEqual(done.frame.minY, instruction.frame.maxY + 8,
                                       "确认按钮不能覆盖最后一行操作说明")
            dragPlayerBack(to: 0.85)
            XCTAssertTrue(done.isHittable, "引导打开时边缘拖动不能退出播放页")
            snapshot(landscape ? "help-reopened-landscape" : "help-reopened-portrait")
            done.tap()
            XCTAssertTrue(done.waitForNonExistence(timeout: 3))
            XCTAssertTrue(app.sliders["字号"].isHittable)
            app.buttons["player.settings"].tap()
            XCTAssertTrue(app.buttons["关闭设置"].waitForExistence(timeout: 3))
            app.buttons["关闭设置"].tap()
            XCTAssertTrue(app.buttons["关闭设置"].waitForNonExistence(timeout: 3))
            XCTAssertFalse(done.exists, "普通关闭设置不能遗留待显示的引导")
        }
    }

    func testFolderCreationCanCancelAndReopenWithKeyboardFocus() {
        launch()
        app.buttons.matching(identifier: "card.folder").firstMatch.tap()
        app.buttons["folder.new"].tap()
        let field = app.textFields["folder.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.typeText("Temporary")
        app.buttons["folder.cancelCreation"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
        app.buttons["folder.new"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "文件夹名称")
        field.typeText("Focus works")
        snapshot("folder-creation-reopened-with-focus")
        field.typeText("\n")
        XCTAssertTrue(app.buttons["folder.new"].waitForNonExistence(timeout: 3))
        app.buttons["library.filter"].tap()
        XCTAssertTrue(app.buttons["Focus works"].exists)
    }

    func testDirectPlayerFilmedActionPersists() {
        launch(player: true)
        let filmed = app.buttons["player.filmed"]
        XCTAssertEqual(filmed.value as? String, "待拍摄")
        snapshot("player-filmed-inactive")
        let frame = filmed.frame
        filmed.tap()
        XCTAssertEqual(filmed.value as? String, "已拍摄")
        XCTAssertEqual(filmed.frame, frame, "绿色状态不能改变按钮布局")
        assertPlayerToolbarOrder()
        snapshot("player-filmed-direct")
        filmed.tap()
        XCTAssertEqual(filmed.value as? String, "待拍摄")
        filmed.tap()
        app.buttons["返回"].tap()
        let card = app.buttons.matching(identifier: "card")
            .matching(NSPredicate(format: "label CONTAINS %@", "脚本1-广发新客开户")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "已拍摄")
    }
    func testCompletionChoicesAreInlineAndKeepSelection() {
        for landscape in [false, true] {
            launch(player: true, landscape: landscape, extra: ["-openSettings"])
            let choices = app.segmentedControls["settings.completion"]
            let scroll = app.scrollViews["settings.scroll"]
            for _ in 0..<5 {
                if choices.buttons["标记并返回"].isHittable { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(choices.buttons["标记并返回"].isHittable)
            for label in ["回到开头", "标记并返回", "停在末尾", "标记并返回"] {
                choices.buttons[label].tap()
                XCTAssertTrue(choices.buttons[label].isSelected)
            }
            XCTAssertTrue(app.staticTexts["读完后标记为已拍摄，并返回稿件列表。"].exists)
            snapshot(landscape ? "completion-landscape" : "completion-portrait")
            app.buttons["关闭设置"].tap()
            app.buttons["设置"].tap()
            for _ in 0..<5 {
                if choices.buttons["标记并返回"].isHittable { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(choices.buttons["标记并返回"].isSelected)
            app.buttons["关闭设置"].tap()
        }
    }
    func testCardSwipeFilmed() {
        launch()
        let cards = app.buttons.matching(identifier: "card")
        XCTAssertTrue(cards.firstMatch.label.contains("脚本1"))
        cards.firstMatch.swipeRight()
        if app.buttons["已拍摄"].isHittable { app.buttons["已拍摄"].tap() }
        XCTAssertFalse(app.buttons["返回"].exists)
        XCTAssertFalse(cards.firstMatch.label.contains("脚本1"), "已拍稿件应沉入已拍分层")
        snapshot("card-mark-filmed")
    }
    func testRepeatedFilmedSwipesKeepRowsAndHeadersSeparate() {
        launch()
        let list = app.tables["script.list"]
        XCTAssertTrue(list.exists)
        func target(_ title: String) -> XCUIElement {
            app.buttons.matching(identifier: "card").matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        }
        func reveal(_ title: String) -> XCUIElement {
            let card = target(title)
            if !card.isHittable { list.swipeUp() }
            if !card.isHittable { list.swipeDown() }
            XCTAssertTrue(card.isHittable)
            return card
        }
        for cycle in 0..<3 {
            for title in ["脚本1-广发新客开户", "脚本2-佣金优惠"] {
                for filmed in [true, false] {
                    let swiped = reveal(title)
                    if cycle == 1 {
                        swiped.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
                            .press(forDuration: 0.05,
                                   thenDragTo: swiped.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)),
                                   withVelocity: .fast, thenHoldForDuration: 0.02)
                    } else { swiped.swipeRight() }
                    let action = app.buttons[filmed ? "已拍摄" : "取消已拍"]
                    if action.isHittable { action.tap() }
                    let card = reveal(title)
                    XCTAssertEqual(card.value as? String, filmed ? "已拍摄" : "待拍摄", "滑动应只切换目标稿件状态")
                    XCTAssertEqual(app.buttons.matching(identifier: "card").matching(NSPredicate(format: "label CONTAINS %@", title)).count, 1)
                    let frames = list.cells.allElementsBoundByIndex.map(\.frame).filter { $0.height > 0 }
                        .sorted { $0.minY < $1.minY }
                    for pair in zip(frames, frames.dropFirst()) {
                        XCTAssertLessThanOrEqual(pair.0.maxY, pair.1.minY + 1, "分区标题与卡片不能重叠")
                    }
                    waitForCount(4)
                    XCTAssertFalse(app.staticTexts["星标置顶"].exists)
                    XCTAssertFalse(app.staticTexts["已拍摄 · 星标"].exists)
                    XCTAssertFalse(app.buttons["返回"].exists)
                    snapshot("filmed-cycle-\(cycle)-\(title)-\(filmed)")
                }
            }
        }
    }

    func testCardSwipeDelete() {
        launch()
        app.buttons.matching(identifier: "card").firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 3), "先揭示删除操作")
        snapshot("delete-action-gold")
        app.buttons["删除"].tap()
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 3))
        waitForCount(3)
        snapshot("delete-bottom-undo")
    }

    func testLongCardSwipesAtScrolledPositionsKeepContentInsideRows() {
        launch(extra: ["-seedSwipeStress"])
        app.buttons["library.filter"].tap()
        app.buttons["123"].tap()
        let list = app.tables["script.list"]
        func assertLayout() {
            // One accessibility snapshot: separate frame queries can span scroll deceleration
            // and compare content from different moments, producing false overlap reports.
            guard let snapshot = try? list.snapshot() else { return XCTFail("无法读取列表布局快照") }
            func flatten(_ node: any XCUIElementSnapshot) -> [any XCUIElementSnapshot] {
                [node] + node.children.flatMap(flatten)
            }
            let nodes = flatten(snapshot), bounds = snapshot.frame
            let cells = nodes.filter { $0.elementType == .cell && $0.frame.intersects(bounds) }.map(\.frame)
            for frame in cells {
                XCTAssertLessThan(frame.height, 300, "固定两行标题/摘要的稿件不应撑出整屏空白，\(frame)")
            }
            let footers = nodes.filter { $0.elementType == .button && $0.identifier == "card.star" }.map(\.frame)
            for body in nodes where body.elementType == .button && body.identifier == "card" {
                let content = body.frame
                guard content.minY > bounds.minY + 1, content.maxY < bounds.maxY - 50 else { continue }
                guard let frame = cells.first(where: { $0.minY <= content.minY + 1 && $0.maxY > content.minY + 1 }) else {
                    XCTFail("卡片正文没有对应的列表行：\(content)"); continue
                }
                guard frame.minY >= bounds.minY + 1, frame.maxY <= bounds.maxY - 1 else { continue }
                XCTAssertLessThanOrEqual(content.maxY, frame.maxY + 1)
                let matching = footers.filter { $0.minY >= content.maxY - 1 && $0.minY < frame.maxY }
                XCTAssertEqual(matching.count, 1, "每行应有一个完整的底部星标按钮")
                if let footer = matching.first {
                    XCTAssertLessThanOrEqual(footer.maxY, frame.maxY + 1, "底部按钮不能画到下一行")
                    XCTAssertLessThanOrEqual(frame.maxY - footer.maxY, 18, "行内不能留下陈旧高度形成的空白")
                }
            }
            let ordered = cells.sorted { $0.minY < $1.minY }
            for pair in zip(ordered, ordered.dropFirst()) { XCTAssertLessThanOrEqual(pair.0.maxY, pair.1.minY + 1) }
        }
        assertLayout()
        for index in 0..<8 {
            if index % 3 == 0 { list.swipeUp() }
            if index % 3 == 2 { list.swipeDown() }
            let candidates = list.buttons.matching(identifier: "card").allElementsBoundByIndex
                .filter { $0.isHittable && $0.frame.minY > list.frame.minY + 20 && $0.frame.maxY < list.frame.maxY - 50 }
            XCTAssertFalse(candidates.isEmpty)
            let card = candidates[candidates.count / 2]
            let wasFilmed = card.value as? String == "已拍摄"
            if index % 2 == 0 {
                card.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)),
                           withVelocity: .fast, thenHoldForDuration: 0.02)
            } else {
                card.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
                    .press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5)),
                           withVelocity: .slow, thenHoldForDuration: 0.02)
                app.buttons[wasFilmed ? "取消已拍" : "已拍摄"].tap()
            }
            assertLayout()
            snapshot("long-card-scrolled-swipe-\(index)")
        }
    }

    func testChangingScopeWhileSwipeIsRevealedClosesItAndShowsTheNewRows() {
        launch(extra: ["-seedSwipeStress"])
        app.buttons.matching(identifier: "card").firstMatch.swipeLeft()
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 3))
        app.buttons["library.filter"].tap()
        app.buttons["星标稿件"].tap()
        let filter = app.buttons["library.filter"]
        expectation(for: NSPredicate(format: "value CONTAINS %@", "当前 5 篇"), evaluatedWith: filter)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons.matching(identifier: "card").count, 5)
        XCTAssertFalse(app.buttons["删除"].exists)
        snapshot("scope-change-closes-swipe")
    }
    func testMultiSelectBatchDelete() {
        launch()
        let cards = app.buttons.matching(identifier: "card")
        cards.firstMatch.press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["已选 1 篇"].waitForExistence(timeout: 3))
        cards.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已选 0 篇"].waitForExistence(timeout: 3), "长按结束后再次点选不能被吞掉")
        cards.firstMatch.tap()
        cards.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["已选 2 篇"].waitForExistence(timeout: 3))
        snapshot("batch-actions-red")
        app.buttons["batch.delete"].tap()
        app.buttons["删除 2 篇"].tap()
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 3))
        waitForCount(2)
        app.buttons["undo.pill"].tap()
        waitForCount(4)
        snapshot("batch-delete-restored")
    }
    func testCameraMirrorOverlay() {
        launch(player: true, landscape: true)
        app.buttons["前置镜子"].tap()
        let close = app.buttons["mirror.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        snapshot("mirror-simulator")
        close.tap()
        XCTAssertTrue(app.sliders["字号"].isHittable)
    }
    func testReturnHighlight() {
        launch()
        app.buttons.matching(identifier: "card").firstMatch.tap()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
        app.buttons["返回"].tap()
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
        snapshot("return-highlight")
    }
    func testEdgeSwipeBackToList() {
        launch(player: true, landscape: true)
        dragPlayerBack(to: 0.85)
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
    }
    func testNativePlayerBackCancelsAndCompletesInBothOrientations() {
        for landscape in [false, true] {
            launch(player: true, landscape: landscape)
            dragPlayerBack(to: 0.15, hold: 0.4)
            XCTAssertTrue(app.buttons["返回"].isHittable)
            XCTAssertTrue(app.sliders["字号"].isHittable)
            snapshot(landscape ? "native-back-landscape-cancelled" : "native-back-portrait-cancelled")
            dragPlayerBack(to: 0.85)
            XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["返回"].exists, "返回列表后不得由 DEBUG 入口再次打开播放页")
        }
    }

    func testNativePlayerBackCancellationKeepsPlaybackAndAllowsReentry() {
        launch(player: true)
        play()
        let status = app.buttons["player.returnToTop"]
        let before = app.staticTexts["player.elapsed"].label
        dragPlayerBack(to: 0.15, hold: 0.4)
        XCTAssertTrue(status.exists)
        XCTAssertTrue((status.value as? String ?? "").contains("提词中"))
        XCTAssertFalse(app.sliders["字号"].exists)
        XCTAssertNotEqual(app.staticTexts["player.elapsed"].label, before)
        snapshot("native-back-cancelled-keeps-playing")
        dragPlayerBack(to: 0.85)
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
            app.buttons.matching(identifier: "card").firstMatch.tap()
            XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5))
            dragPlayerBack(to: 0.85)
            XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
        }
    }

    func testNativePlayerBackUsesPhysicalLeftEdgeWithMirroredText() {
        launch(player: true)
        app.buttons["player.settings"].tap()
        let mirror = app.switches["镜像翻转"]
        for _ in 0..<12 {
            if mirror.isHittable { break }
            app.scrollViews["settings.scroll"].swipeUp()
        }
        XCTAssertTrue(mirror.isHittable); mirror.tap()
        app.buttons["关闭设置"].tap()
        dragPlayerBack(to: 0.15, hold: 0.4)
        XCTAssertTrue(app.buttons["返回"].isHittable)
        snapshot("native-back-mirrored-cancelled")
        dragPlayerBack(to: 0.85)
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
    }

    func testNativePlayerBackWaitsUntilModalToolsClose() {
        launch(player: true, landscape: true, extra: ["-openSettings"])
        dragPlayerBack(to: 0.85)
        XCTAssertTrue(app.buttons["关闭设置"].isHittable)
        app.buttons["关闭设置"].tap()
        XCTAssertTrue(app.buttons["关闭设置"].waitForNonExistence(timeout: 3))
        app.buttons["player.mirror"].tap()
        let closeMirror = app.buttons["mirror.close"]
        XCTAssertTrue(closeMirror.waitForExistence(timeout: 5))
        dragPlayerBack(to: 0.85)
        XCTAssertTrue(closeMirror.isHittable)
        closeMirror.tap()
        XCTAssertTrue(closeMirror.waitForNonExistence(timeout: 3))
        dragPlayerBack(to: 0.85)
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
    }
    func testReachBottomBackToTop() {
        launch(player: true, landscape: true, extra: ["-fastEnd"])
        let hint = app.staticTexts["player.returnHint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 40))
        let time = app.buttons["player.returnToTop"]
        XCTAssertEqual(app.buttons.matching(identifier: "player.returnToTop").count, 1)
        let before = time.value as? String
        sleep(2)
        XCTAssertEqual(before, time.value as? String, "读完后计时应暂停")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "回到顶部")).count, 1, "回顶入口只保留时间按钮")
        snapshot("at-bottom-time-hint")
        time.tap()
        XCTAssertTrue(hint.waitForNonExistence(timeout: 3))
        XCTAssertTrue((time.value as? String ?? "").contains("已暂停，00:00"))
        snapshot("time-returned-to-top")
        play()
        XCTAssertTrue(app.sliders["字号"].waitForNonExistence(timeout: 3))
        sleep(2)
        XCTAssertFalse(hint.exists, "回顶后应从开头重新播放，而不是立即再次结束")
    }
    func testNativePlayerCompletionMarksAndReturnsToList() {
        launch(player: true, landscape: true, extra: ["-openSettings", "-fastEnd"])
        let choices = app.segmentedControls["settings.completion"]
        for _ in 0..<8 {
            if choices.buttons["标记并返回"].isHittable { break }
            app.scrollViews["settings.scroll"].swipeUp()
        }
        XCTAssertTrue(choices.buttons["标记并返回"].isHittable)
        choices.buttons["标记并返回"].tap()
        app.buttons["关闭设置"].tap()
        play()
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 40))
        let marked = app.buttons.matching(identifier: "card")
            .matching(NSPredicate(format: "label CONTAINS %@", "脚本1-广发新客开户")).firstMatch
        for _ in 0..<5 {
            if marked.isHittable { break }
            app.tables["script.list"].swipeUp()
        }
        XCTAssertEqual(marked.value as? String, "已拍摄")
        XCTAssertFalse(app.buttons["返回"].exists)
        snapshot("native-back-completion-marked-and-returned")
    }
    func testTimeCanRestartFromMidPlayback() {
        launch(player: true)
        play(); sleep(2)
        let time = app.buttons["player.returnToTop"]
        XCTAssertTrue((time.value as? String ?? "").contains("提词中"))
        time.tap()
        XCTAssertTrue(app.sliders["字号"].waitForExistence(timeout: 3))
        XCTAssertTrue((time.value as? String ?? "").contains("已暂停，00:00"))
        XCTAssertFalse(app.staticTexts["player.returnHint"].exists)
        snapshot("time-reset-during-playback")
    }
    func testListDeleteAnimation() {
        launch()
        deleteFirst()
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 3))
        waitForCount(3)
        app.buttons["undo.pill"].tap()
        waitForCount(4)
    }
    func testUndoToolbarUpdatesConsecutiveDeletesAndCanReappear() {
        launch()
        deleteFirst()
        waitForCount(3)
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 3))
        deleteFirst()
        waitForCount(2)
        XCTAssertEqual(app.buttons.matching(identifier: "undo.pill").count, 1)
        XCTAssertTrue(app.staticTexts["已删除 1 篇"].exists)
        snapshot("motion-consecutive-delete-undo")
        app.buttons["undo.pill"].tap()
        waitForCount(3) // Only the most recent deletion is undone.
        XCTAssertTrue(app.buttons["undo.pill"].waitForNonExistence(timeout: 3))
        deleteFirst()
        waitForCount(2)
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 3))
        app.buttons["undo.pill"].tap()
        waitForCount(3)
        XCTAssertTrue(app.buttons["undo.pill"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["新建稿件"].isHittable)
    }
    func testCreateFolderFromCard() {
        launch()
        app.buttons.matching(identifier: "card.folder").firstMatch.tap()
        XCTAssertTrue(app.buttons["folder.new"].waitForExistence(timeout: 5))
        app.buttons["folder.new"].tap()
        let field = app.textFields["folder.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap(); field.typeText("测试分组\n")
        app.buttons["library.filter"].tap()
        let folder = app.buttons["测试分组"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.tap()
        XCTAssertEqual(app.buttons["library.filter"].label, "测试分组")
        snapshot("folder-created")
    }

    func testLibraryScopeAndAllSixSortCombinations() {
        launch()
        waitForCount(4)
        snapshot("library-menu-pill-portrait")
        let scope = app.buttons["library.filter"], sort = app.buttons["library.sort"]
        scope.tap()
        XCTAssertTrue(app.buttons["星标稿件"].waitForExistence(timeout: 3))
        snapshot("library-scope-menu")
        app.buttons["星标稿件"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "card").count, 1)
        scope.tap(); app.buttons["全部稿件"].tap()
        for (dimension, ascendingTitle, descendingTitle) in [
            ("时间", "脚本2-佣金优惠", "脚本3-新客福利包"),
            ("标题", "脚本2-佣金优惠", "脚本3-新客福利包"),
            ("字数", "脚本3-新客福利包", "脚本2-佣金优惠")
        ] {
            sort.tap()
            XCTAssertTrue(app.buttons[dimension].waitForExistence(timeout: 3))
            if dimension == "字数" { snapshot("library-sort-three-dimensions") }
            app.buttons[dimension].tap()
            for (order, expected) in [("升序", ascendingTitle), ("降序", descendingTitle)] {
                sort.tap(); app.buttons[order].tap()
                XCTAssertEqual(sort.value as? String, "\(dimension)，\(order)")
                let second = app.buttons.matching(identifier: "card").element(boundBy: 1)
                expectation(for: NSPredicate(format: "label CONTAINS %@", expected), evaluatedWith: second)
                waitForExpectations(timeout: 5)
            }
        }
        scope.tap(); app.buttons["口播"].tap()
        XCTAssertEqual(scope.label, "口播")
        XCTAssertEqual(app.buttons.matching(identifier: "card").count, 3)
        snapshot("library-folder-menu-selected")
    }

    func testLibraryMenusInLandscape() {
        launch(landscape: true)
        XCTAssertTrue(app.buttons["新建稿件"].isHittable)
        let filter = app.buttons["library.filter"], sort = app.buttons["library.sort"]
        XCTAssertLessThanOrEqual(filter.frame.maxX, sort.frame.minX)
        snapshot("library-menu-pill-landscape")
        sort.tap()
        XCTAssertTrue(app.buttons["字数"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["升序"].isHittable)
        XCTAssertTrue(app.buttons["降序"].isHittable)
        snapshot("library-sort-landscape")
    }
    func testFooterShortcutsAreDirectAndDoNotOpenPlayer() {
        launch()
        XCTAssertFalse(app.buttons["card.more"].exists)
        let star = app.buttons.matching(identifier: "card.star").firstMatch
        XCTAssertEqual(star.label, "取消星标")
        star.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "card.star").firstMatch.label, "添加星标")
        app.buttons.matching(identifier: "card.star").firstMatch.tap()
        XCTAssertEqual(app.buttons.matching(identifier: "card.star").firstMatch.label, "取消星标")
        XCTAssertFalse(app.buttons["返回"].exists)
        let folder = app.buttons.matching(identifier: "card.folder").firstMatch
        XCTAssertEqual(folder.value as? String, "口播")
        folder.tap()
        XCTAssertTrue(app.buttons["关闭移动到文件夹"].waitForExistence(timeout: 5))
        app.buttons["关闭移动到文件夹"].tap()
        snapshot("card-footer-shortcuts")
    }

    func testParagraphAutoPause() {
        launch(player: true, landscape: true, extra: ["-pauseParagraph"])
        XCTAssertTrue(app.staticTexts["已暂停：段落分隔"].waitForExistence(timeout: 25))
        snapshot("paragraph-pause")
    }
    func testNativeListStartsScrollingFromBodyDiagonalAndSelection() {
        for mode in ["body", "diagonal", "selection"] {
            launch(extra: ["-seedMany"])
            let cards = app.buttons.matching(identifier: "card")
            if mode == "selection" {
                cards.firstMatch.press(forDuration: 0.8)
                XCTAssertTrue(app.staticTexts["已选 1 篇"].waitForExistence(timeout: 3))
            }
            let anchor = app.staticTexts["脚本2-佣金优惠"].firstMatch
            XCTAssertTrue(anchor.exists)
            let before = anchor.frame.minY
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            let y = min(anchor.frame.midY + 35, app.windows.firstMatch.frame.height - 140)
            origin.withOffset(CGVector(dx: 105, dy: y)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: mode == "diagonal" ? 129 : 105, dy: y - 200)),
                withVelocity: .slow, thenHoldForDuration: 0.02)
            let moved = before - anchor.frame.minY
            print("NATIVE_SCROLL mode=\(mode) moved=\(moved)")
            XCTAssertGreaterThan(moved, 120, "200pt 轻拖应及时带动原生列表")
            XCTAssertFalse(app.buttons["返回"].exists, "滑动不能误开提词页")
            snapshot("native-scroll-\(mode)")
        }
    }
    func testDeletionStaysDeletedAfterRelaunchWithoutRecoveryMenu() {
        launch()
        XCTAssertFalse(app.buttons["导入稿件"].exists)
        XCTAssertFalse(app.buttons["导出备份"].exists)
        XCTAssertFalse(app.buttons["最近删除"].exists)
        snapshot("list-without-bottom-menu")
        deleteFirst(); waitForCount(3)
        app.terminate()
        app.launchArguments = ["-seedDemo", "-skipOnboard"]
        app.launch()
        waitForCount(3)
        XCTAssertFalse(app.buttons["最近删除"].exists)
        XCTAssertFalse(app.buttons["undo.pill"].exists)
        XCTAssertFalse(app.staticTexts["脚本1-广发新客开户"].exists)
        snapshot("deleted-after-relaunch")
    }
    func testEditorAutosaveAndSafeSplit() {
        launch()
        app.buttons.matching(identifier: "card.edit").firstMatch.tap()
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["拆分后替换原稿，原稿可在最近删除中恢复。"].exists)
        snapshot("editor-original-style")
        XCTAssertTrue(app.segmentedControls["editor.splitMode"].isHittable)
        revealInEditor(app.segmentedControls["editor.autoPause"])
        XCTAssertFalse(app.buttons["editor.tools"].exists)
        let split = app.buttons["editor.split"]
        XCTAssertEqual(split.label, "智能拆分")
        revealInEditor(split); split.tap()
        waitForCount(6)
        XCTAssertFalse(app.buttons["editor.done"].exists)
        XCTAssertFalse(app.staticTexts["脚本1-广发新客开户"].exists)
        snapshot("split-replaced-source")
        XCTAssertFalse(app.buttons["最近删除"].exists)
    }
    func testDirectKeywordSplitReplacesCurrentDraft() {
        launch()
        app.buttons["新建稿件"].tap()
        XCTAssertFalse(app.buttons["editor.split"].isEnabled)
        let title = app.textFields["稿件标题"]
        title.tap(); title.typeText("Keyword draft")
        let content = app.textViews["editor.content"]
        content.tap(); content.typeText("Part A#Part B")
        // Finish interactive keyboard dismissal before targeting a segmented control that moves with it.
        let form = app.scrollViews["editor.form"]
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.8))
            .press(forDuration: 0.05,
                   thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.25)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        revealInEditor(app.segmentedControls["editor.splitMode"])
        app.segmentedControls["editor.splitMode"].buttons["关键词"].tap()
        let keywordOption = app.segmentedControls["editor.splitMode"].buttons["关键词"]
        expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: keywordOption)
        waitForExpectations(timeout: 3)
        let keyword = app.textFields["editor.splitKeyword"]
        revealInEditor(keyword)
        keyword.tap(); keyword.typeText("#")
        snapshot("editor-keyword-keyboard")
        let split = app.buttons["editor.split"]
        XCTAssertTrue(split.isEnabled)
        revealInEditor(split); waitForStableFrame(split); split.tap()
        waitForCount(6)
        XCTAssertFalse(app.buttons["editor.done"].exists)
        snapshot("editor-keyword-direct-split")
        XCTAssertFalse(app.staticTexts["Keyword draft"].exists)
        XCTAssertTrue(app.staticTexts["Part A"].exists)
        XCTAssertTrue(app.staticTexts["#Part B"].exists)
    }
    func testPasteIntoBodyAppendsAndAutosaves() {
        launch()
        let previous = UIPasteboard.general.items
        defer { UIPasteboard.general.items = previous }
        UIPasteboard.general.string = "First pasted paragraph"
        app.buttons["新建稿件"].tap()
        let paste = app.buttons["editor.paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        snapshot("new-editor-layout")
        paste.tap()
        let content = app.textViews["editor.content"]
        XCTAssertEqual(content.value as? String, "First pasted paragraph")
        UIPasteboard.general.string = "Second pasted paragraph"
        paste.tap()
        XCTAssertEqual(content.value as? String, "First pasted paragraph\n\nSecond pasted paragraph")
        snapshot("editor-pasted-body")
        app.buttons["editor.done"].tap(); waitForCount(5)
        app.buttons.matching(identifier: "card.edit").element(boundBy: 1).tap()
        XCTAssertEqual(app.textViews["editor.content"].value as? String, "First pasted paragraph\n\nSecond pasted paragraph")
    }
    func testClearAllIsDirectAndCanBeCancelledOrUndone() {
        launch()
        XCTAssertFalse(app.buttons["稿件管理"].exists)
        app.buttons["library.clear"].tap()
        XCTAssertTrue(app.buttons["删除 4 篇"].waitForExistence(timeout: 5))
        snapshot("delete-confirmation-red")
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        else { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap() }
        XCTAssertTrue(app.buttons["删除 4 篇"].waitForNonExistence(timeout: 3))
        waitForCount(4)
        app.buttons["library.clear"].tap(); app.buttons["删除 4 篇"].tap()
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["还没有稿件"].exists)
        snapshot("clear-all-undo")
        app.buttons["undo.pill"].tap(); waitForCount(4)
        snapshot("list-direct-actions")
    }
    func testNewEditorSavesOneDraft() {
        launch()
        app.buttons["新建稿件"].tap()
        let title = app.textFields["稿件标题"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("自动保存测试")
        let content = app.textViews["editor.content"]
        content.tap(); content.typeText("第一行内容")
        app.buttons["editor.done"].tap()
        waitForCount(5)
        snapshot("new-draft-saved")
    }
    func testNoOpEditorKeepsListUsableAfterDismissal() {
        launch()
        app.buttons.matching(identifier: "card.edit").firstMatch.tap()
        app.buttons["editor.done"].tap()
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "card").firstMatch.tap()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 5), "弹层结束后不能有残留遮罩")
    }
}
