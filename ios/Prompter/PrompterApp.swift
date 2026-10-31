import SwiftUI
import SwiftData

@main
struct PrompterApp: App {
    @StateObject private var settings = AppSettings()
    private let container: ModelContainer

    init() {
        let modelContainer = try! ModelContainer(for: Script.self)
        container = modelContainer
        // UI 测试用：-resetDemo 清空全部数据并重置播种标记（每批次干净起点，防跨轮污染）
        if ProcessInfo.processInfo.arguments.contains("-resetDemo") {
            let context = ModelContext(modelContainer)
            try? context.delete(model: Script.self) // iOS 17 批量删除（erase 要 18）
            try? context.save()
            UserDefaults.standard.set(false, forKey: "demo_seeded")
        }
        // 模拟器演示：launch argument -seedDemo 插入示例数据（真机不受影响）
        if ProcessInfo.processInfo.arguments.contains("-seedDemo"),
           !UserDefaults.standard.bool(forKey: "demo_seeded") {
            let context = ModelContext(modelContainer)
            let demo: [(String, String, String?, Bool, Bool)] = [
                ("脚本1-广发新客开户", "朋友们，广发证券新客开户福利来了！从现在起，新客来开户，可立享专属 VIP 优惠佣金、沪深 Level-2 十档行情、超 30 款智能投资工具等多重新客福利。\n\n总有人问我，为什么我的交易更频繁了，但手续费却更省了？答案就是开户时选对了渠道，佣金低到你不敢相信。\n\n新客开户即享价值约 1688 元的新客福利包，名额有限，先到先得。点击下方链接，三分钟完成开户。", "口播", true, false),
                ("脚本2-佣金优惠", "总有人问我，为什么我的交易更频繁了，但手续费却更省了？", "口播", false, false),
                ("脚本3-新客福利包", "新客开户即享价值约 1688 元的新客福利包。", nil, false, false),
                ("脚本4-已拍示例", "这一条已经拍完了，应当沉底显示。", "口播", false, true),
            ]
            for (title, content, folder, starred, filmed) in demo {
                context.insert(Script(title: title, content: content, folder: folder, starred: starred, isFilmed: filmed))
            }
            try? context.save()
            UserDefaults.standard.set(true, forKey: "demo_seeded")
        }
    }

    var body: some Scene {
        WindowGroup {
            ScriptListView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .tint(.accentGold)
        }
        .modelContainer(container)
    }
}
