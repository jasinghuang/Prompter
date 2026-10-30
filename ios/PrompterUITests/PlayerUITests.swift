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

    /// 设置抽屉右拨收起：滑杆上的横向拖动归滑杆（抽屉不关、值变化），左缘把手右拨收起
    func testSettingsDrawerDragToDismiss() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-openSettings", "-resetSettings"]
        app.launch()
        let close = app.buttons["关闭设置"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))

        // ① 点关闭按钮 → 抽屉收起
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 3), "点关闭应收起抽屉")

        // ② 顶栏设置胶囊 → 重新打开
        app.buttons["设置"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 3), "胶囊应重新打开抽屉")

        // ③ 从面板左缘把手区快速右拨（终点离屏幕右缘 130pt，避开 Home 条系统手势区）
        let window = app.windows.firstMatch
        let header = app.staticTexts["设置"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        let windowFrame = window.frame
        let headerFrame = header.frame
        let stripX = headerFrame.minX - windowFrame.minX - 34 // 标题左移 34pt ≈ 面板左缘内 14pt
        let y = headerFrame.midY - windowFrame.minY
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: stripX, dy: y))
            .press(forDuration: 0.05,
                   thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                       .withOffset(CGVector(dx: windowFrame.width - windowFrame.minX - 130, dy: y)),
                   withVelocity: .fast,
                   thenHoldForDuration: 0.02)
        XCTAssertFalse(close.waitForExistence(timeout: 3), "右拨应关闭抽屉")
    }

    /// 高速滚到底自动停止 → 出现「回到顶部」胶囊
    func testReachBottomBackToTop() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-fastEnd", "-resetSettings"]
        app.launch()
        let backToTop = app.buttons["回到顶部"]
        XCTAssertTrue(backToTop.waitForExistence(timeout: 40), "读完自动停止后应出现回到顶部按钮")
        sleep(1)
        snapshot("08-landscape-atbottom-backtotop")
    }

    /// 列表删除动画：点删除 → 卡片数 -1（退场动画由 cardsGrid 的 animation 驱动）
    func testListDeleteAnimation() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-skipOnboard"]
        app.launch()
        let deletes = app.buttons.matching(identifier: "card.delete")
        XCTAssertTrue(deletes.firstMatch.waitForExistence(timeout: 10))
        let before = deletes.count
        XCTAssertGreaterThanOrEqual(before, 2)
        deletes.firstMatch.tap()
        usleep(120_000) // 抓退场动画中的一帧
        snapshot("09-list-delete-mid")
        sleep(1)
        XCTAssertEqual(deletes.count, before - 1, "删除后卡片数应减一")
        snapshot("10-list-delete-after")
    }

    /// 卡片文件夹按钮 → 新建文件夹 → 目标稿件应移入新文件夹（此前 alert 读不到目标而静默丢失）
    func testCreateFolderFromCard() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-skipOnboard"]
        app.launch()
        let folderButtons = app.buttons.matching(identifier: "card.folder")
        XCTAssertTrue(folderButtons.firstMatch.waitForExistence(timeout: 10))
        folderButtons.firstMatch.tap()

        let newFolder = app.buttons["folder.new"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 5))
        newFolder.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "点新建应弹出命名 alert")
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText("测试分组")
        alert.buttons["创建"].tap()

        sleep(1)
        XCTAssertTrue(
            app.staticTexts["测试分组"].waitForExistence(timeout: 5),
            "创建后卡片/筛选 chips 应出现新文件夹名"
        )
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
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-pauseParagraph", "-resetSettings"]
        app.launch()
        let toast = app.staticTexts["已暂停：段落分隔"]
        XCTAssertTrue(toast.waitForExistence(timeout: 20), "滚到段落起点应自动暂停并提示")
        snapshot("07-landscape-paragraph-pause")
    }
}
