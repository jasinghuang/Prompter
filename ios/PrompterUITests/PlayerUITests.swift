import XCTest

/// 播放页自动截图验证（横屏）：暂停/播放/设置抽屉/拖拽回看
/// 附件导出：xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>
final class PlayerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapScreenCenter() {
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .tap()
    }

    func testPlayerLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard"]
        app.launch()
        sleep(2) // 等首次排版稳定
        snapshot("01-landscape-paused")

        // 轻点播放：右侧胶囊与底部控件应隐藏，红点亮起
        tapScreenCenter()
        sleep(4)
        snapshot("02-landscape-playing")

        // 再轻点暂停：控件回来，计时应走字
        tapScreenCenter()
        sleep(1)
        snapshot("03-landscape-paused-elapsed")

        // 拖拽回看上文：手指按住时中央提示应隐藏
        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            .press(forDuration: 0.6, thenDragTo: app.windows.firstMatch
                .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        sleep(1)
        snapshot("04-landscape-dragged")
    }

    func testSettingsDrawerLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-openSettings"]
        app.launch()
        sleep(2)
        snapshot("05-landscape-settings")
    }

    func testPlayerPortrait() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard"]
        app.launch()
        sleep(2)
        snapshot("06-portrait-paused")
    }

    /// 段落自动暂停端到端：高速播放滚到第二段起点行时应自动暂停并出现提示
    func testParagraphAutoPause() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-pauseParagraph"]
        app.launch()
        let toast = app.staticTexts["已暂停：段落分隔"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "滚到段落起点应自动暂停并提示")
        snapshot("07-landscape-paragraph-pause")
    }
}
