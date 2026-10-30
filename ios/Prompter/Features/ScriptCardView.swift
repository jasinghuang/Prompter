import SwiftUI

/// 稿件卡片：三级视觉层级 + 44pt 命中区操作钮 + 文件夹菜单 + 星标
struct ScriptCardView: View {
    enum Action {
        case open, edit, delete, toggleStar, moveFolder(String?)
    }

    let script: Script
    let wordsPerMinute: Int
    let folders: [String]
    let onAction: (Action) -> Void

    private var charCount: Int { PrompterCore.readableCharCount(script.content) }

    var body: some View {
        Button { onAction(.open) } label: {
            VStack(alignment: .leading, spacing: 4) {
                titleRow
                if !script.content.isEmpty {
                    Text(script.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(script.isFilmed ? 0.15 : 0.25))
                        .lineLimit(2)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                metaRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                script.isFilmed
                    ? Color.successGreen.opacity(0.06)
                    : Color.surface.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        script.isFilmed ? Color.successGreen.opacity(0.3) : Color.accentGold.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PressableCardStyle())
    }

    // 标题行：标题与编辑/删除按钮同一行，垂直居中对齐
    private var titleRow: some View {
        HStack(alignment: .center, spacing: 8) {
            if script.isFilmed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.successGreen)
            }
            Text(script.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(script.isFilmed ? .white.opacity(0.5) : .white)
                .strikethrough(script.isFilmed)
                .lineLimit(1)
                .layoutPriority(0)
            Spacer(minLength: 4)
            // 操作钮（44pt 命中区）
            actionButton(icon: "pencil", label: "编辑", tint: .white.opacity(0.45)) {
                onAction(.edit)
            }
            actionButton(icon: "trash", label: "删除", tint: .accentGold.opacity(0.7)) {
                onAction(.delete)
            }
        }
    }

    private func actionButton(icon: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // 元信息行：日期 | 字数 | 时长 ······ 文件夹菜单 + 星标
    private var metaRow: some View {
        HStack(spacing: 10) {
            Text(script.updatedAt, format: mdyFormat)
            Text("|").foregroundStyle(.white.opacity(0.15))
            Text("\(charCount)字")
            Text("|").foregroundStyle(.white.opacity(0.15))
            Text("约\(durationText)")
            Spacer(minLength: 8)
            folderMenu
            starButton
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(script.isFilmed ? 0.35 : 0.5))
    }

    private var durationText: String {
        PrompterCore.formatTime(
            PrompterCore.estimateDurationSeconds(charCount: charCount, wordsPerMinute: wordsPerMinute)
        )
    }

    // 文件夹：Menu 弹出可选文件夹（含未分组）；无分组时仅暗淡图标
    private var folderMenu: some View {
        Menu {
            ForEach(folders, id: \.self) { name in
                Button {
                    onAction(.moveFolder(name))
                } label: {
                    if script.folder == name {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            Divider()
            Button("未分组") {
                onAction(.moveFolder(nil))
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: script.folder != nil ? "folder.fill" : "folder")
                    .font(.system(size: 18))
                if let folder = script.folder {
                    Text(folder)
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(script.folder != nil ? .accentGold : .white.opacity(0.35))
            .frame(height: 44)
            .contentShape(Rectangle())
        }
    }

    private var starButton: some View {
        Button {
            onAction(.toggleStar)
        } label: {
            Image(systemName: script.starred ? "star.fill" : "star")
                .font(.system(size: 18))
                .foregroundStyle(script.starred ? .accentGold : .white.opacity(0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(script.starred ? "取消星标" : "星标")
    }

    private var mdyFormat: Date.FormatStyle {
        .dateTime.year().month().day()
    }
}
