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
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-resetSettings"]
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

        // ② 顶栏设置胶囊 → 重新打开（先等元素出现，避免高负载下竞态）
        let settingsButton = app.buttons["设置"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "顶栏设置按钮应可见")
        settingsButton.tap()
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

    /// 卡片右滑 → 标记已拍 → 沉到已拍层
    func testCardSwipeFilmed() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-skipOnboard", "-resetSettings", "-resetDemo"]
        app.launch()
        let cards = app.buttons.matching(identifier: "card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let firstBefore = cards.firstMatch.label
        XCTAssertTrue(firstBefore.contains("脚本1"), "演示数据第一张应为脚本1，实际：\(firstBefore)")

        let c = cards.firstMatch
        c.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        sleep(1)
        XCTAssertFalse(app.buttons["返回"].exists, "右滑不应误开播放页")
        let firstAfter = app.buttons.matching(identifier: "card").firstMatch
        XCTAssertTrue(firstAfter.exists)
        XCTAssertFalse(firstAfter.label.contains("脚本1"), "右滑标记已拍后脚本1应沉底，实际首卡：\(firstAfter.label)")
        let third = app.buttons.matching(identifier: "card").element(boundBy: 2)
        XCTAssertTrue(third.exists && third.label.contains("脚本1"), "脚本1 应沉到已拍层（第 3 位），实际：\(third.label)")
    }

    /// 卡片左滑越阈值松手 → 删除 + 撤销胶囊 + 卡片数减一
    func testCardSwipeDelete() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-skipOnboard", "-resetSettings", "-resetDemo"]
        app.launch()
        let cards = app.buttons.matching(identifier: "card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let beforeCount = cards.count

        let c = cards.firstMatch
        c.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            .press(forDuration: 0.15, thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)),
                   withVelocity: .slow, thenHoldForDuration: 0.05)
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 5), "左滑删除后应出现撤销胶囊")
        sleep(1)
        XCTAssertEqual(app.buttons.matching(identifier: "card").count, beforeCount - 1, "删除后卡片数应减一")
        snapshot("15-swipe-delete-undo")
    }

    /// 长按多选 → 点选 → 批量删除（确认）→ 撤销胶囊整批恢复
    func testMultiSelectBatchDelete() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-skipOnboard", "-resetSettings", "-resetDemo"]
        app.launch()
        let cards = app.buttons.matching(identifier: "card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let before = cards.count

        // 长按第一张进入多选（且不应误开播放页）
        cards.firstMatch.press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["已选 1 篇"].waitForExistence(timeout: 5), "长按应进入多选")
        XCTAssertFalse(app.buttons["返回"].exists, "长按不应误开播放页")

        // 点第二张 → 已选 2 篇
        app.buttons.matching(identifier: "card").element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["已选 2 篇"].waitForExistence(timeout: 3), "点第二张应变为已选 2 篇")

        // 批量删除（系统确认框）
        app.buttons["batch.delete"].tap()
        let confirm = app.buttons["删除 2 篇"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "应弹出批量删除确认")
        confirm.tap()
        XCTAssertTrue(app.buttons["undo.pill"].waitForExistence(timeout: 5), "批量删除后应出现撤销胶囊")
        XCTAssertTrue(app.staticTexts["已删除 2 篇"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "card").count, before - 2, "批量删除后卡片数应减二")

        // 撤销（2 秒窗口内立即点）→ 整批恢复
        app.buttons["undo.pill"].tap()
        sleep(1)
        XCTAssertEqual(app.buttons.matching(identifier: "card").count, before, "撤销应整批恢复")
        snapshot("17-multiselect-undo-restored")
    }

    /// 化妆镜：顶栏相机按钮 → 镜面卡片（模拟器无摄像头走错误态）→ 关闭
    func testCameraMirrorOverlay() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-resetSettings"]
        app.launch()
        let mirrorButton = app.buttons["前置镜子"]
        XCTAssertTrue(mirrorButton.waitForExistence(timeout: 10))
        mirrorButton.tap()
        let close = app.buttons["mirror.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "镜子卡片应出现")
        sleep(1) // 等错误态文案稳定（模拟器无摄像头）
        snapshot("18-mirror-simulator")
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 3), "点关闭应收起镜子")
    }

    /// 播放页左缘右滑 → 返回列表页（对齐系统返回手势习惯）
    func testEdgeSwipeBackToList() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-resetSettings"]
        app.launch()
        XCTAssertTrue(app.buttons["返回"].waitForExistence(timeout: 10), "播放页应已打开")
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.12, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 5), "左缘右滑应返回列表页")
    }

    /// 高速滚到底自动停止 → 出现「回到顶部」胶囊
    func testReachBottomBackToTop() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-fastEnd", "-resetSettings"]
        app.launch()
        let backToTop = app.buttons["回到顶部"]
        XCTAssertTrue(backToTop.waitForExistence(timeout: 40), "读完自动停止后应出现回到顶部按钮")
        sleep(1)
        // 自动停止后计时应冻结（用户反馈：播完时间还在跑）
        let elapsed = app.staticTexts["player.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 3), "计时应可读")
        let t1 = elapsed.label
        sleep(3)
        let t2 = app.staticTexts["player.elapsed"].label
        XCTAssertEqual(t1, t2, "自动停止后计时应冻结：\(t1) → \(t2)")
        snapshot("08-landscape-atbottom-backtotop")
    }

    /// 列表删除动画：点删除 → 卡片数 -1（退场动画由 cardsGrid 的 animation 驱动）
    func testListDeleteAnimation() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-seedDemo", "-skipOnboard", "-resetSettings", "-resetDemo"]
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
        app.launchArguments = ["-seedDemo", "-skipOnboard", "-resetSettings", "-resetDemo"]
        app.launch()
        let folderButtons = app.buttons.matching(identifier: "card.folder")
        XCTAssertTrue(folderButtons.firstMatch.waitForExistence(timeout: 10))
        snapshot("14-card-before-folder")
        // 演示数据：脚本1/2 已在「口播」，脚本3 无文件夹——用第三张卡走"无→有"链路
        folderButtons.element(boundBy: 2).tap()

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
        snapshot("13-card-with-folder")
    }

    func testPlayerPortrait() throws {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-seedDemo", "-openPlayer", "-skipOnboard", "-resetSettings"]
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
