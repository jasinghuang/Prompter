import XCTest
@testable import Prompter

@MainActor
final class ScriptListUpdateTests: XCTestCase {
    private func state(_ scripts: [Script], selected: Set<UUID> = [], highlighted: UUID? = nil,
                       selecting: Bool = false, speed: Int = 160,
                       summaries: [UUID: ScriptLibraryState.Summary] = [:]) -> NativeScriptList.State {
        let rows: [ScriptLibraryState.Row] = [.heading(group: .pending, count: scripts.count)]
            + scripts.map { .script(ScriptSnapshot($0)) }
        return .init(rows: rows, summaries: summaries, wordsPerMinute: speed,
                     selecting: selecting, selected: selected, highlighted: highlighted)
    }

    func testCardOnlyUpdatesDoNotReconfigureOtherCardsOrHeadings() {
        let a = Script(title: "A"), b = Script(title: "B"), c = Script(title: "C")
        let scripts = [a, b, c]
        let selecting = state(scripts, selecting: true)
        XCTAssertEqual(state(scripts, selected: [b.id], selecting: true).reconfiguredRowIDs(from: selecting), [.script(b.id)])
        let highlightA = state(scripts, highlighted: a.id)
        XCTAssertEqual(state(scripts, highlighted: b.id).reconfiguredRowIDs(from: highlightA), [.script(a.id), .script(b.id)])
        let summary = ScriptLibraryState.Summary(content: b.content, characterCount: 3, excerpt: "新摘要")
        XCTAssertEqual(state(scripts, summaries: [b.id: summary]).reconfiguredRowIDs(from: state(scripts)), [.script(b.id)])
        XCTAssertEqual(state(scripts, speed: 200).reconfiguredRowIDs(from: state(scripts)), scripts.map { .script($0.id) })
        XCTAssertEqual(state(scripts).reconfiguredRowIDs(from: state(scripts)), [])
    }

    func testProjectionIsReusedForSelectionAndHighlightIndependentReads() {
        let library = ScriptLibraryState()
        let scripts = (0..<100).map { Script(title: "稿件\($0)", content: "正文\($0)") }
        library.refresh(scripts)
        let original = library.projection(in: scripts)
        library.selecting = true; library.selected = [scripts[0].id]
        for _ in 0..<20 { XCTAssertTrue(library.projection(in: scripts) === original) }
        XCTAssertEqual(library.visible(in: scripts).map(\.id), original.visibleIDs)
    }

    func testProjectionInvalidatesForEveryOrderingAndContentInput() {
        let library = ScriptLibraryState()
        let a = Script(title: "A", content: "一", folder: "口播"), b = Script(title: "B", content: "二三")
        let scripts = [a, b]; library.refresh(scripts)
        var previous = library.projection(in: scripts)
        func changed(_ mutation: () -> Void) {
            mutation()
            let next = library.projection(in: scripts)
            XCTAssertFalse(next === previous)
            previous = next
        }
        changed { library.sortKey = .title }
        changed { library.sortAscending.toggle() }
        changed { library.query = "A" }
        XCTAssertEqual(previous.visibleIDs, [a.id])
        changed { library.query = ""; library.filter = .folder("口播") }
        XCTAssertEqual(previous.visibleIDs, [a.id])
        changed { a.folder = nil }
        XCTAssertTrue(previous.rows.isEmpty)
        changed { library.filter = .all; a.isFilmed = true; a.starred = true }
        XCTAssertEqual(previous.rows.last, .script(ScriptSnapshot(a)))
        changed { a.title = "改标题"; a.content = "修改正文" }
        changed { library.refresh(scripts) }
        changed { b.deletedAt = Date() }
        XCTAssertEqual(previous.visibleIDs, [a.id])
        changed { b.deletedAt = nil }
        XCTAssertEqual(Set(previous.visibleIDs), Set(scripts.map(\.id)))
    }

    func testCacheResolvesCurrentModelsAndRetainsImmutableRenderedRevision() {
        let library = ScriptLibraryState(), a = Script(title: "A", content: "旧正文")
        library.refresh([a])
        let previous = library.projection(in: [a])
        let replacement = Script(title: "A", content: "旧正文")
        replacement.id = a.id
        ScriptSnapshot(a).apply(to: replacement)
        XCTAssertTrue(library.visible(in: [replacement]).first === replacement)
        a.content = "新正文"
        XCTAssertEqual(previous.rows.last, .script(ScriptSnapshot(replacement)))
        XCTAssertEqual(library.projection(in: [a]).rows.last, .script(ScriptSnapshot(a)))
        XCTAssertTrue(library.projection(in: []).rows.isEmpty)
    }
}
