import SwiftUI

/// 文件夹选择弹窗（复刻 Web 版底部弹窗）：未分组 + 文件夹列表 + 新建
struct FolderPickerSheet: View {
    let script: Script
    let folders: [String]
    let allScripts: [Script]
    let onSelect: (String?) -> Void
    let onNewFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 拖拽指示条
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 4)

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
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // 选项列表
            ScrollView {
                VStack(spacing: 2) {
                    optionRow(
                        label: "未分组",
                        count: nil,
                        active: script.folder == nil
                    ) {
                        onSelect(nil)
                    }

                    ForEach(folders, id: \.self) { folder in
                        let count = allScripts.filter { $0.folder == folder }.count
                        optionRow(
                            label: folder,
                            count: count,
                            active: script.folder == folder
                        ) {
                            onSelect(folder)
                        }
                    }

                    // 新建文件夹
                    Button {
                        onNewFolder()
                    } label: {
                        HStack {
                            Text("＋ 新建文件夹…")
                                .font(.system(size: 15))
                                .foregroundStyle(.accentGold)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
        .background(Color.surface)
    }

    private func optionRow(label: String, count: Int?, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(active ? .white : .white.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                        .monospacedDigit()
                }
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.accentGold)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(active ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
