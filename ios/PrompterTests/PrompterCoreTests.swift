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
}
