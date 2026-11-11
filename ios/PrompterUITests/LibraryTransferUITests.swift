import XCTest
import Foundation

final class LibraryTransferUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(landscape: Bool = false) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        app.launchArguments = ["-seedDemo", "-resetDemo", "-resetSettings", "-skipOnboard"]
        app.launch()
        XCTAssertTrue(app.buttons["新建稿件"].waitForExistence(timeout: 10))
        // Opening a document may cold-launch the app: never reset its library then.
        app.launchArguments = ["-skipOnboard"]
    }
    private func snapshot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func fixture(changed: Bool = false) throws -> URL {
        let records: [[String: Any]] = [
            ["id": "C53B680D-BF71-4C07-98DA-900000000001", "title": "收到的稿件甲", "content": changed ? "另一台手机修改后的正文" : "收到的完整正文\n第二行",
             "folder": "收到的目录", "starred": !changed, "isFilmed": changed,
             "createdAt": 1_000_000_000_000 as Int64, "updatedAt": (changed ? 2_000_000_001_000 : 2_000_000_000_000) as Int64],
            ["id": "C53B680D-BF71-4C07-98DA-900000000002", "title": "收到的稿件乙", "content": "另一篇正文",
             "folder": "收到的目录", "starred": false, "isFilmed": true,
             "createdAt": 1_000_000_000_000 as Int64, "updatedAt": 2_000_000_000_000 as Int64]
        ]
        let value: [String: Any] = ["format": "com.jasing.prompter.library", "version": 1,
                                   "exportedAt": "2026-11-06T00:00:00Z", "folders": ["收到的目录"], "scripts": records]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("收到的稿件库.prompter")
        try JSONSerialization.data(withJSONObject: value).write(to: url)
        return url
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func waitForCount(_ count: Int) {
        let filter = app.buttons["library.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "value BEGINSWITH %@", "共 \(count) 篇稿件，"), evaluatedWith: filter)
        waitForExpectations(timeout: 5)
    }

    func testFileOpeningImportsAndRepeatedImportDoesNotCreateDuplicates() throws {
        launch()
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        app.terminate()
        XCUIDevice.shared.system.open(url)
        let confirm = app.buttons["archive.confirmImport"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(element("archive.plan.new").label.contains("2 篇"))
        snapshot("archive-import-preview")
        confirm.tap()
        XCTAssertTrue(element("archive.importSuccess").waitForExistence(timeout: 5))
        snapshot("archive-import-result")
        app.buttons["archive.done"].tap(); waitForCount(6)
        app.open(url)
        XCTAssertTrue(app.buttons["archive.done"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["archive.confirmImport"].exists)
        XCTAssertTrue(element("archive.plan.same").label.contains("2 篇"))
        snapshot("archive-repeat-skipped")
        app.buttons["archive.done"].tap(); waitForCount(6)
    }

    func testConflictingFileCanKeepLocalOrUpdateStatusWithoutAddingCopies() throws {
        launch()
        let original = try fixture(), changed = try fixture(changed: true)
        defer {
            try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: changed.deletingLastPathComponent())
        }
        app.open(original)
        XCTAssertTrue(app.buttons["archive.confirmImport"].waitForExistence(timeout: 10))
        app.buttons["archive.confirmImport"].tap(); app.buttons["archive.done"].tap(); waitForCount(6)
        app.open(changed)
        XCTAssertTrue(app.buttons["archive.confirmImport"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("archive.plan.conflicts").label.contains("1 篇"))
        snapshot("archive-conflict-keep-local")
        app.buttons["archive.confirmImport"].tap()
        XCTAssertTrue(element("archive.result.updated").label.contains("0 篇"))
        app.buttons["archive.done"].tap(); waitForCount(6)
        app.open(changed)
        XCTAssertTrue(app.buttons["archive.confirmImport"].waitForExistence(timeout: 10))
        app.segmentedControls["archive.conflictPolicy"].buttons["使用文件版本"].tap()
        snapshot("archive-conflict-use-file")
        app.buttons["archive.confirmImport"].tap()
        XCTAssertTrue(element("archive.result.updated").label.contains("1 篇"))
        app.buttons["archive.done"].tap(); waitForCount(6)
        let card = app.buttons.matching(identifier: "card").matching(NSPredicate(format: "label CONTAINS %@", "收到的稿件甲")).firstMatch
        XCTAssertTrue(card.exists)
        XCTAssertEqual(card.value as? String, "已拍摄")
    }

    func testExportEntryCreatesAFileAndSupportsFolderAndSelectionScopes() {
        launch()
        let export = app.buttons["library.export"]
        let filter = app.buttons["library.filter"]
        XCTAssertEqual(app.buttons.matching(identifier: "library.export").count, 1)
        XCTAssertGreaterThanOrEqual(export.frame.width, 44)
        XCTAssertGreaterThanOrEqual(export.frame.height, 44)
        XCTAssertGreaterThanOrEqual(export.frame.minX, filter.frame.maxX)
        XCTAssertLessThanOrEqual(export.frame.maxX, app.buttons["library.search"].frame.minX)
        XCTAssertEqual(export.frame.midY, filter.frame.midY, accuracy: 1)
        XCTAssertFalse(app.buttons["library.import"].exists)
        snapshot("archive-direct-export-entry")
        export.tap()
        XCTAssertTrue(app.buttons["archive.share"].waitForExistence(timeout: 10))
        snapshot("archive-export-all")
        app.buttons["关闭导出稿件库"].tap()
        app.buttons["library.filter"].tap()
        app.buttons["口播"].tap()
        export.tap()
        XCTAssertTrue(app.buttons["archive.share"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.segmentedControls["archive.exportScope"].exists)
        snapshot("archive-export-folder")
        app.buttons["关闭导出稿件库"].tap()
        app.buttons.matching(identifier: "card").firstMatch.press(forDuration: 0.8)
        XCTAssertFalse(app.buttons["batch.export"].exists)
        export.tap()
        XCTAssertTrue(app.buttons["archive.share"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.segmentedControls["archive.exportScope"].exists)
        snapshot("archive-export-selected")
    }

    func testInvalidDocumentDoesNotModifyLibraryAndExportWorksInLandscape() throws {
        launch(landscape: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".prompter")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a library".utf8).write(to: url)
        app.open(url)
        XCTAssertTrue(app.alerts["文件未能打开"].waitForExistence(timeout: 10))
        app.buttons["知道了"].tap(); waitForCount(4)
        app.buttons["library.export"].tap()
        XCTAssertTrue(app.buttons["archive.share"].waitForExistence(timeout: 10))
        snapshot("archive-export-landscape")
    }

    func testReceivedFileWaitsForEditorToClose() throws {
        launch()
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        app.buttons["新建稿件"].tap()
        XCTAssertTrue(app.buttons["editor.done"].waitForExistence(timeout: 5))
        XCUIDevice.shared.system.open(url)
        XCTAssertTrue(app.buttons["editor.done"].exists, "接收文件不应强行关闭正在编辑的稿件")
        XCTAssertFalse(app.buttons["archive.confirmImport"].exists)
        app.buttons["editor.done"].tap()
        XCTAssertTrue(app.buttons["archive.confirmImport"].waitForExistence(timeout: 10))
        snapshot("archive-received-after-editor")
    }

    func testDirectExportOpensSystemSharing() {
        launch()
        app.buttons["library.export"].tap()
        XCTAssertTrue(app.buttons["archive.share"].waitForExistence(timeout: 10))
        app.buttons["archive.share"].tap()
        let fileAction = app.cells.matching(NSPredicate(format: "label IN %@", ["保存到“文件”", "存储到“文件”", "Save to Files"])).firstMatch
        XCTAssertTrue(fileAction.waitForExistence(timeout: 10), "系统分享面板应把导出内容识别为可保存的文件")
        snapshot("archive-system-share-file")
        // The system uses a popover here and exposes no Close button.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.2)).tap()
        XCTAssertTrue(fileAction.waitForNonExistence(timeout: 5))
    }
}
