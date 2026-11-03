import XCTest
import UIKit
@testable import Prompter

@MainActor
final class NativeScriptListLifecycleTests: XCTestCase {
    private func owner(_ scripts: [Script]) -> NativeScriptList {
        NativeScriptList(state: .init(rows: scripts.map { .script(ScriptSnapshot($0)) }, summaries: [:],
                                      wordsPerMinute: 160, selecting: false, selected: [], highlighted: nil)) { _, _ in }
    }
    private func window() -> UIWindow {
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            return UIWindow(windowScene: scene)
        }
        return UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 700))
    }
    private func settle() async throws { try await Task.sleep(for: .milliseconds(80)) }

    func testOnlyLatestRevisionIsAppliedAfterMountingAndRemounting() async throws {
        let a = Script(title: "A"), b = Script(title: "B")
        let table = NativeScriptList.MountedTableView(frame: CGRect(x: 0, y: 0, width: 402, height: 614), style: .plain)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "script")
        let coordinator = owner([a]).makeCoordinator()
        coordinator.attach(table)
        coordinator.update(owner([a, b]))
        try await settle()
        XCTAssertNil(table.window)
        XCTAssertEqual(table.numberOfSections, 0, "离屏时不应提交数据快照并强制布局")
        let window = window(); let host = UIViewController()
        window.rootViewController = host; window.isHidden = false
        defer { coordinator.detach(); window.isHidden = true; window.rootViewController = nil }
        host.view.addSubview(table)
        try await settle()
        XCTAssertEqual(table.numberOfRows(inSection: 0), 2, "首次挂载应用最新的待处理快照")
        table.removeFromSuperview()
        coordinator.update(owner([b]))
        try await settle()
        XCTAssertEqual(table.numberOfRows(inSection: 0), 2, "移出窗口后保持已提交状态，等重新挂载")
        host.view.addSubview(table)
        try await settle()
        XCTAssertEqual(table.numberOfRows(inSection: 0), 1)
    }

    func testDismantleDropsQueuedWorkAndReleasesDataSource() async throws {
        let table = NativeScriptList.MountedTableView(frame: CGRect(x: 0, y: 0, width: 402, height: 614), style: .plain)
        let coordinator = owner([]).makeCoordinator()
        coordinator.attach(table)
        let window = window(); let host = UIViewController()
        window.rootViewController = host; window.isHidden = false
        host.view.addSubview(table)
        coordinator.detach()
        try await settle()
        XCTAssertNil(table.dataSource)
        XCTAssertNil(table.delegate)
        XCTAssertNil(table.onLayoutReady)
        window.isHidden = true; window.rootViewController = nil
    }
}
