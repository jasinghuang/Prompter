import SwiftUI
import SwiftData

@main
struct PrompterApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var transfers = LibraryTransferCoordinator()
    @Environment(\.scenePhase) private var scenePhase
    @State private var container: ModelContainer?
    @State private var storageError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ScriptListView().modelContainer(container)
                } else if let storageError {
                    VStack(spacing: 20) {
                        Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                        Text("暂时无法打开本机数据").font(.headline)
                        Text("已有稿件会保留。请重试，或检查设备剩余空间。")
                            .font(.subheadline).multilineTextAlignment(.center)
                        Text(storageError).font(.caption).foregroundStyle(.textSecondary)
                        Button("重试", action: openStore).buttonStyle(.borderedProminent).tint(.accentGold)
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
                } else {
                    ProgressView("正在打开稿件…").frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.canvas)
                }
            }
            .environmentObject(settings).environmentObject(transfers).preferredColorScheme(.dark).tint(.accentGold)
            .onOpenURL { transfers.receive($0) }
            .overlay(alignment: .top) {
                if transfers.isReading {
                    HStack(spacing: 8) { ProgressView(); Text("正在读取稿件库…").font(.subheadline) }
                        .padding(12).background(Color.surface, in: Capsule()).padding(.horizontal, 16)
                } else if !transfers.pending.isEmpty {
                    Text("稿件库已收到，返回稿件列表后确认导入")
                        .font(.subheadline).foregroundStyle(.textPrimary).padding(12)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16)
                }
            }
            .alert("文件未能打开", isPresented: Binding(get: { transfers.errorMessage != nil }, set: { if !$0 { transfers.errorMessage = nil } })) {
                Button("知道了", role: .cancel) { transfers.errorMessage = nil }
            } message: { Text(transfers.errorMessage ?? "") }
            .task { if container == nil { openStore() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { settings.flush() } }
        }
    }

    private func openStore() {
        do {
            let modelContainer = try ModelContainer(for: Script.self)
            #if DEBUG
            try seedDemo(in: modelContainer)
            #endif
            container = modelContainer; storageError = nil
        } catch { storageError = error.localizedDescription }
    }

    #if DEBUG
    private func seedDemo(in modelContainer: ModelContainer) throws {
        // DEBUG-only simulator fixtures.
        // UI 测试用：-resetDemo 清空全部数据并重置播种标记（每批次干净起点，防跨轮污染）
        if ProcessInfo.processInfo.arguments.contains("-resetDemo") {
            let context = ModelContext(modelContainer)
            try context.delete(model: Script.self) // iOS 17 批量删除（erase 要 18）
            try context.save()
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
            if ProcessInfo.processInfo.arguments.contains("-seedSwipeStress") {
                for i in 1...14 {
                    let title = i == 2 ? "---" : "脚本\(i)-客供-20261016-何沐瑾／余奕昕——新客来广发证券开户，有机会节省交易费用"
                    let text = String(repeating: "\(title) 朋友们，新客开户福利来了。正规、靠谱又省心！ ", count: i == 1 ? 24 : i % 3 + 1)
                    context.insert(Script(title: title, content: text, folder: "123", starred: [1, 5, 7, 13].contains(i),
                        isFilmed: ![1, 2, 3, 9, 10].contains(i),
                        createdAt: Date(timeIntervalSince1970: Double(2_000 - i)),
                        updatedAt: Date(timeIntervalSince1970: Double(2_000 - i))))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-seedMany") {
                for i in 1...40 {
                    context.insert(Script(title: String(format: "滚动测试稿件 %02d", i),
                        content: "这是一篇用于验证纵向滚动的演示稿件。轻拖正文、图标旁或卡片间隙都应及时开始滚动。",
                        createdAt: Date(timeIntervalSince1970: Double(1_000 - i)),
                        updatedAt: Date(timeIntervalSince1970: Double(1_000 - i))))
                }
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: "demo_seeded")
        }
    }
    #endif
}
