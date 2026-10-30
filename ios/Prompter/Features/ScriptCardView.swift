import SwiftUI

/// 稿件卡片：三级视觉层级（标题 > 元信息 > 正文摘要）、幽灵操作钮、星标/文件夹
struct ScriptCardView: View {
    enum Action {
        case open, edit, delete, toggleStar
    }

    let script: Script
    let wordsPerMinute: Int
    let onAction: (Action) -> Void

    private var charCount: Int { PrompterCore.readableCharCount(script.content) }

    var body: some View {
        Button { onAction(.open) } label: {
            VStack(alignment: .leading, spacing: 6) {
                titleRow
                if !script.content.isEmpty {
                    Text(script.content)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(script.isFilmed ? 0.15 : 0.25))
                        .lineLimit(2)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                metaRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                script.isFilmed
                    ? Color.successGreen.opacity(0.06)
                    : Color.surface.opacity(0.7),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        script.isFilmed ? Color.successGreen.opacity(0.3) : Color.accentGold.opacity(0.15),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PressableCardStyle())
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if script.isFilmed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.successGreen)
            }
            Text(script.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(script.isFilmed ? .white.opacity(0.5) : .white)
                .strikethrough(script.isFilmed)
                .lineLimit(1)
            Spacer(minLength: 4)
            // 幽灵操作钮（无底色，按下才现淡底）
            HStack(spacing: 2) {
                ghostButton(icon: "pencil", tint: .white.opacity(0.4)) { onAction(.edit) }
                ghostButton(icon: "trash", tint: .accentGold.opacity(0.7)) { onAction(.delete) }
            }
        }
    }

    private func ghostButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var metaRow: some View {
        HStack(spacing: 10) {
            Text(script.updatedAt, format: mdyFormat)
            Text("|").foregroundStyle(.white.opacity(0.15))
            Text("\(charCount)字")
            Text("|").foregroundStyle(.white.opacity(0.15))
            Text("约\(PrompterCore.formatTime(PrompterCore.estimateDurationSeconds(charCount: charCount, wordsPerMinute: wordsPerMinute)))")
            Spacer(minLength: 8)
            if let folder = script.folder {
                HStack(spacing: 3) {
                    Image(systemName: "folder.fill").font(.system(size: 11))
                    Text(folder).lineLimit(1)
                }
                .foregroundStyle(.accentGold)
            }
            Button { onAction(.toggleStar) } label: {
                Image(systemName: script.starred ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(script.starred ? .accentGold : .white.opacity(0.35))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white.opacity(script.isFilmed ? 0.35 : 0.5))
    }

    private var mdyFormat: Date.FormatStyle {
        .dateTime.year().month().day()
    }
}
