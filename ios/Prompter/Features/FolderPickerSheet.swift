import SwiftUI

/// 文件夹选择弹窗 —— 复刻 Web 版 FolderPickerSheet 样式（单篇/批量共用）
struct FolderPickerSheet: View {
    /// 目标稿件：1 篇 = 单卡流程；多篇 = 批量移动（勾选只在单篇时显示）
    let targets: [Script]
    let folders: [String]
    let allScripts: [Script]
    let onSelect: (String?) -> Void
    let onNewFolder: () -> Void

    private var currentFolder: String? {
        // 所有选中项在同一个文件夹 → 显示该文件夹的勾；混合/全未分组 → 不勾
        guard !targets.isEmpty else { return nil }
        let allFolders = targets.compactMap(\.folder)
        if allFolders.count == targets.count, Set(allFolders).count == 1 {
            return allFolders.first // 全部在同一个文件夹
        }
        return nil // 全未分组 或 混合 → 不勾任何文件夹行
    }

    var body: some View {
        VStack(spacing: 0) {
            // 自定义拖拽指示条（与编辑弹窗同款间距：上 10pt / 下 14pt）
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 60, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // 标题
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.4))
                Text("移动到文件夹")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)     // Web: px-6 = 24pt
            .padding(.top, 12)
            .padding(.bottom, 4)          // Web: pb-2 = 8pt（减去指示条已占的）

            // 选项列表（Web: p-3 = 12pt padding）
            ScrollView {
                VStack(spacing: 2) {
                    optionRow(label: "未分组", active: currentFolder == nil) {
                        onSelect(nil)
                    }

                    ForEach(folders, id: \.self) { folder in
                        let count = allScripts.filter { $0.folder == folder }.count
                        optionRow(label: folder, count: count, active: currentFolder == folder) {
                            onSelect(folder)
                        }
                    }

                    // 新建（Web: isNew=true → 金色）
                    newFolderRow
                }
                .padding(12)              // Web: p-3 = 12pt
            }
        }
        .background(Color.canvas)         // 纯黑，与编辑弹窗一致
    }

    // MARK: 选项行（Web: FolderOption —— rounded-xl px-3 py-3 text-sm）

    private func optionRow(label: String, count: Int? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 14))               // Web: text-sm = 14pt
                    .foregroundStyle(active ? .white : .white.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 8) {
                    if let count {
                        Text("\(count)")
                            .font(.system(size: 12))        // Web: text-xs
                            .foregroundStyle(.white.opacity(0.25))
                            .monospacedDigit()
                    }
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.accentGold)
                    }
                }
            }
            .padding(.horizontal, 12)   // Web: px-3 = 12pt
            .padding(.vertical, 12)     // Web: py-3 = 12pt
            .frame(minHeight: 48)
            .background(
                active ? Color.white.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 12)      // Web: rounded-xl
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var newFolderRow: some View {
        Button {
            onNewFolder()
        } label: {
            HStack {
                Text("＋ 新建文件夹…")
                    .font(.system(size: 14))
                    .foregroundStyle(.accentGold)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("folder.new")
    }
}
