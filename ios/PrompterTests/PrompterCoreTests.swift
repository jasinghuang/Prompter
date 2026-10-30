import XCTest
@testable import Prompter

final class PrompterCoreTests: XCTestCase {
    // MARK: 可读字数（与 Web 版 countReadableChars 对齐：Unicode 标量、去空白）

    func testReadableCharCountIgnoresWhitespace() {
        XCTAssertEqual(PrompterCore.readableCharCount("今天 介绍\n产品"), 6)
        XCTAssertEqual(PrompterCore.readableCharCount(""), 0)
        XCTAssertEqual(PrompterCore.readableCharCount("  \n\t "), 0)
        XCTAssertEqual(PrompterCore.readableCharCount("a b\nc"), 3)
    }

    // MARK: 口播时长估算

    func testEstimateDuration() {
        // 1600 字 @ 160 字/分 → 600 秒
        XCTAssertEqual(PrompterCore.estimateDurationSeconds(charCount: 1600, wordsPerMinute: 160), 600)
        XCTAssertEqual(PrompterCore.estimateDurationSeconds(charCount: 0, wordsPerMinute: 160), 0)
        XCTAssertEqual(PrompterCore.estimateDurationSeconds(charCount: 100, wordsPerMinute: 0), 0)
    }

    // MARK: 时间格式化

    func testFormatTime() {
        XCTAssertEqual(PrompterCore.formatTime(0), "00:00")
        XCTAssertEqual(PrompterCore.formatTime(65), "01:05")
        XCTAssertEqual(PrompterCore.formatTime(600), "10:00")
        XCTAssertEqual(PrompterCore.formatTime(-5), "00:00")
    }

    // MARK: 分层排序（星标未拍 0 → 未拍 1 → 星标已拍 2 → 已拍 3）

    func testTierOrdering() {
        XCTAssertTrue(PrompterCore.tier(starred: true, filmed: false) < PrompterCore.tier(starred: false, filmed: false))
        XCTAssertTrue(PrompterCore.tier(starred: false, filmed: false) < PrompterCore.tier(starred: true, filmed: true))
        XCTAssertTrue(PrompterCore.tier(starred: true, filmed: true) < PrompterCore.tier(starred: false, filmed: true))
    }

    // MARK: 智能拆分

    func testSplitByParagraphs() {
        XCTAssertEqual(Splitter.byParagraphs("标题甲\n内容甲\n\n标题乙\n内容乙"), ["标题甲\n内容甲", "标题乙\n内容乙"])
        XCTAssertEqual(Splitter.byParagraphs("单段"), ["单段"])
        XCTAssertEqual(Splitter.byParagraphs("  \n\n  \n\n甲"), ["甲"], "空段应被过滤")
        XCTAssertEqual(Splitter.byParagraphs("a\n\n\n\nb"), ["a", "b"], "3+ 连续换行视为一个分隔")
        XCTAssertTrue(Splitter.byParagraphs("   ").isEmpty)
    }

    func testSplitByKeyword() {
        XCTAssertEqual(Splitter.byKeyword("开场白\n主持人：大家好", keyword: "主持人："), ["开场白", "主持人：大家好"])
        // 新段以关键词开头（与 Web 版一致），不是去掉关键词
        XCTAssertEqual(Splitter.byKeyword("甲乙甲乙", keyword: "甲"), ["甲乙", "甲乙"])
        XCTAssertEqual(Splitter.byKeyword("任何", keyword: ""), [])
        XCTAssertEqual(Splitter.byKeyword("甲", keyword: "不存在"), ["甲"])
    }

    func testSegmentTitle() {
        XCTAssertEqual(Splitter.titleOfSegment("标题行\n正文"), "标题行")
        XCTAssertEqual(Splitter.titleOfSegment("  空格标题  \n正文"), "空格标题")
        XCTAssertEqual(Splitter.titleOfSegment("单行"), "单行")
    }

    // MARK: 迁移 JSON 解码

    func testMigrationDecode() {
        let json = """
        {"type":"prompter-export","v":1,
         "scripts":[{"id":"abc","title":"甲","content":"内容一","createdAt":1760000000000,"updatedAt":1760000000000,"starred":true,"folder":"口播"}],
         "filmedIds":["abc"],
         "settings":{"scrollSpeed":240,"mirror":true}}
        """
        let payload = MigrationService.decode(json)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.scripts?.count, 1)
        XCTAssertEqual(payload?.scripts?.first?.folder, "口播")
        XCTAssertEqual(payload?.filmedIds, ["abc"])
        XCTAssertEqual(payload?.settings?.scrollSpeed, 240)

        XCTAssertNil(MigrationService.decode("这不是JSON"))
    }

    func testMergeSettingsOnlyOverwritesPresentFields() {
        var data = SettingsData.defaults
        let exported = ExportedSettings(fontSize: 80, letterSpacing: nil, lineHeight: nil, scrollSpeed: 999, mirror: nil, horizontalPadding: nil, textAlign: nil, pauseKeyword: nil, pauseOnParagraph: nil, completeAction: nil, splitMode: nil, splitKeyword: nil)
        MigrationService.mergeSettings(exported, into: &data)
        XCTAssertEqual(data.fontSize, 80)
        XCTAssertEqual(data.scrollSpeed, PrompterCore.speedMax, "速度应夹到上限")
        XCTAssertEqual(data.lineHeight, SettingsData.defaults.lineHeight, "未提供的字段保持默认")
    }

    // MARK: 播放页：滚动速度换算（可滚动距离均摊到每个字）

    func testPointsPerSecond() {
        // 1000pt 可滚动 / 100 字 = 10pt/字；60 字/分 = 1 字/秒 → 10pt/s
        XCTAssertEqual(PrompterCore.pointsPerSecond(maxOffset: 1000, charCount: 100, wordsPerMinute: 60), 10, accuracy: 0.0001)
        XCTAssertEqual(PrompterCore.pointsPerSecond(maxOffset: 0, charCount: 100, wordsPerMinute: 60), 0)
        XCTAssertEqual(PrompterCore.pointsPerSecond(maxOffset: 1000, charCount: 0, wordsPerMinute: 60), 0)
        XCTAssertEqual(PrompterCore.pointsPerSecond(maxOffset: 1000, charCount: 100, wordsPerMinute: 0), 0)
    }

    // MARK: 播放页：捏合字号（步进 2 取偶 + 夹紧）

    func testPinchFontSize() {
        XCTAssertEqual(PrompterCore.pinchFontSize(scale: 1, startFontSize: 64), 64)
        XCTAssertEqual(PrompterCore.pinchFontSize(scale: 1.5, startFontSize: 64), 96)
        XCTAssertEqual(PrompterCore.pinchFontSize(scale: 1.1, startFontSize: 64), 70, "70.4 → 取偶 70")
        XCTAssertEqual(PrompterCore.pinchFontSize(scale: 10, startFontSize: 64), PrompterCore.fontSizeMax)
        XCTAssertEqual(PrompterCore.pinchFontSize(scale: 0.1, startFontSize: 64), PrompterCore.fontSizeMin)
        XCTAssertEqual(PrompterCore.pinchFontSize(scale: 0, startFontSize: 64), 64, "非法比例返回起始字号")
    }

    // MARK: 播放页：段落起点（连续 2+ 换行后的首字）

    func testParagraphStarts() {
        XCTAssertEqual(PrompterCore.paragraphStarts("ab\n\ncd"), [4])
        XCTAssertEqual(PrompterCore.paragraphStarts("a\n\n\n\nb"), [5], "3+ 连续换行只记一个起点")
        XCTAssertEqual(PrompterCore.paragraphStarts("a\nb"), [], "单个换行不是段落分隔")
        XCTAssertEqual(PrompterCore.paragraphStarts("a\n\n"), [], "末尾空行后无内容不记")
        XCTAssertEqual(PrompterCore.paragraphStarts(""), [])
    }

    // MARK: 播放页：关键词自动暂停（同一命中只触发一次，reset 后重新生效）

    func testKeywordPauseTracker() {
        var tracker = KeywordPauseTracker()
        let content = "ab\n\n主持人：cd"
        XCTAssertTrue(tracker.shouldPause(content: content, keyword: "主持人：", activeIndex: 4))
        XCTAssertEqual(tracker.pausedAt, 4)
        XCTAssertFalse(tracker.shouldPause(content: content, keyword: "主持人：", activeIndex: 4), "同一位置不重复触发")
        XCTAssertFalse(tracker.shouldPause(content: content, keyword: "主持人：", activeIndex: 100), "窗口越界安全")
        XCTAssertFalse(tracker.shouldPause(content: content, keyword: "", activeIndex: 4), "空关键词不触发")
        tracker.reset()
        XCTAssertTrue(tracker.shouldPause(content: content, keyword: "主持人：", activeIndex: 4), "reset 后重新生效")
    }

    func testKeywordPauseTrackerHitsWithinLookback() {
        var tracker = KeywordPauseTracker()
        // 关键词在当前行起点之前 30 字内也算命中（Web 版回看窗口）
        let content = "开场白停一下继续说后面的内容"
        XCTAssertTrue(tracker.shouldPause(content: content, keyword: "停一下", activeIndex: 10))
        XCTAssertEqual(tracker.pausedAt, 3)
    }

    // MARK: 播放页：段落自动暂停

    func testParagraphPauseTracker() {
        var tracker = ParagraphPauseTracker()
        let starts: Set<Int> = [4, 9]
        XCTAssertFalse(tracker.shouldPause(paragraphStarts: starts, activeIndex: 0))
        XCTAssertTrue(tracker.shouldPause(paragraphStarts: starts, activeIndex: 4))
        XCTAssertFalse(tracker.shouldPause(paragraphStarts: starts, activeIndex: 4), "同一起点不重复触发")
        XCTAssertTrue(tracker.shouldPause(paragraphStarts: starts, activeIndex: 9))
        tracker.reset()
        XCTAssertTrue(tracker.shouldPause(paragraphStarts: starts, activeIndex: 4))
    }
}
