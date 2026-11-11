import XCTest

final class SpeechFollowUITests: XCTestCase {
    func testTouchTemporarilyPausesVoiceAndExplicitPauseCancelsResume() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-openSettings"]
        app.launch()
        let modes = app.segmentedControls["settings.playbackMode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        modes.buttons["语音跟随"].tap()
        app.buttons["关闭设置"].tap()
        let center = app.windows.firstMatch.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        center.tap()
        let pause = app.buttons["player.voicePause"]
        let status = app.staticTexts["player.speechStatus"]
        guard pause.waitForExistence(timeout: 10) else {
            if status.label.contains("麦克风暂不可用") {
                throw XCTSkip("Requires an available microphone; simulator audio input is unavailable")
            }
            XCTFail("Voice mode did not arm: \(status.label)")
            return
        }
        let listening = NSPredicate { _, _ in status.label.contains("等待朗读") || status.label.contains("停顿中") }
        expectation(for: listening, evaluatedWith: status)
        waitForExpectations(timeout: 15)
        center.press(forDuration: 0.5)
        XCTAssertTrue(status.label.contains("手动调整中"))
        XCTAssertTrue(pause.exists, "Touch must retain the armed voice session")
        expectation(for: NSPredicate { _, _ in status.label.contains("等待朗读") || status.label.contains("停顿中") }, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "voice-upper-third-anchor"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Dragging is another temporary handoff, then the dedicated pause must
        // cancel it permanently and restore access to settings.
        center.press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.35)))
        pause.tap()
        XCTAssertTrue(app.buttons["player.settings"].waitForExistence(timeout: 3))
        let remainsStopped = NSPredicate { _, _ in !pause.exists && status.label.contains("轻点正文开始") }
        expectation(for: remainsStopped, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.sliders["player.slider.速度"].exists)
    }

    func testComparisonEnginesCanBeSelectedWithoutStartingCloudRecognition() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-openSettings"]
        app.launch()
        let modes = app.segmentedControls["settings.playbackMode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        modes.buttons["语音跟随"].tap()
        let picker = app.buttons["speech.enginePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Zipformer 流式"].tap()
        XCTAssertTrue(app.staticTexts["中文流式模型 · 2025-06-30 INT8"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["speech.modelReady"].exists)
        picker.tap()
        app.buttons["SenseVoice 分段"].tap()
        XCTAssertTrue(app.staticTexts["非流式模型 · 分段快照识别，可能有更长等待"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["speech.modelReady"].exists)
        picker.tap()
        app.buttons["Apple 本地"].tap()
        XCTAssertTrue(app.staticTexts["音频仅在本机识别 · 系统语言资源首次可能需下载"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists, "Choosing an engine alone must not request speech/mic access")
        picker.tap()
        app.buttons["Paraformer 流式"].tap()
        XCTAssertTrue(app.staticTexts["speech.modelReady"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["speech.showDiagnostics"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "local-engine-comparison-settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInstalledAppShowsOfflineModelReadyWithoutDownloading() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-openSettings"]
        app.launch()
        let modes = app.segmentedControls["settings.playbackMode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        modes.buttons["语音跟随"].tap()
        XCTAssertTrue(app.staticTexts["离线模型已随 App 安装 · 无需下载"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["speech.downloadModel"].exists)
        XCTAssertFalse(app.staticTexts["speech.downloadPhase"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "bundled-model-ready"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDownloadShowsConnectionAndByteStatusAndCanCancel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-openSettings"]
        app.launch()
        let modes = app.segmentedControls["settings.playbackMode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        modes.buttons["语音跟随"].tap()
        if app.staticTexts["speech.modelReady"].exists { throw XCTSkip("Model is already installed on this simulator") }
        app.buttons["speech.downloadModel"].tap()
        XCTAssertTrue(app.staticTexts["speech.downloadPhase"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["speech.downloadBytes"].exists)
        XCTAssertFalse(app.staticTexts["正在下载 0%"].exists)
        app.buttons["speech.cancelDownload"].tap()
        XCTAssertTrue(app.buttons["speech.downloadModel"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["已取消下载，可稍后重试。"].exists)
    }

    func testVoiceModeKeepsConstantModeAndExplainsOfflineSetup() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard", "-openPlayer", "-openSettings"]
        app.launch()
        let modes = app.segmentedControls["settings.playbackMode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 10))
        XCTAssertTrue(modes.buttons["匀速"].isSelected)
        modes.buttons["语音跟随"].tap()
        let ready = app.staticTexts["speech.modelReady"].exists
        if !ready {
            XCTAssertTrue(app.buttons["speech.downloadModel"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["首次需下载约 237 MB 的模型，完成后可断网使用。"].exists)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "voice-mode-settings"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["关闭设置"].tap()
        XCTAssertTrue(app.staticTexts["player.speechStatus"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.sliders["player.slider.速度"].exists)
        // Starting before installation opens setup, without asking for microphone permission.
        if !ready { app.windows.firstMatch.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap() }
        else { app.buttons["player.settings"].tap() }
        XCTAssertTrue(modes.waitForExistence(timeout: 3))
        modes.buttons["匀速"].tap()
        app.buttons["关闭设置"].tap()
        XCTAssertTrue(app.sliders["player.slider.速度"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["player.speechStatus"].exists)
    }
}
