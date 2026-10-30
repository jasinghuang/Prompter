import SwiftUI

/// 稿件卡片 —— 逐项对齐 Web 版 SwipeableCard 的间距/字号/颜色/布局
struct ScriptCardView: View {
    enum Action {
        case open, edit, delete, toggleStar, showFolderPicker
    }

    let script: Script
    let wordsPerMinute: Int
    let folders: [String]
    let onAction: (Action) -> Void

    private var charCount: Int { PrompterCore.readableCharCount(script.content) }

    var body: some View {
        Button { onAction(.open) } label: {
            cardContent
        }
        .buttonStyle(PressableCardStyle())
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {  // Web: mb-1.5 = 6pt
            // ── 标题行 ──
            titleRow

            // ── 正文摘要（Web: text-sm text-white/25 line-clamp-2） ──
            if !script.content.isEmpty {
                Text(script.content)
                    .font(.system(size: 14))                       // Web: text-sm = 14pt
                    .foregroundStyle(.white.opacity(script.isFilmed ? 0.15 : 0.25))
                    .lineLimit(2)
                    .lineSpacing(4)                                 // Web: leading-relaxed ≈ 1.6
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // ── 元信息行（Web: text-xs text-white/50） ──
            metaRow
        }
        .padding(.horizontal, 16)   // Web: px-4 = 16pt
        .padding(.top, 12)          // Web: pt-3 = 12pt
        .padding(.bottom, 10)       // Web: pb-2.5 = 10pt
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            script.isFilmed
                ? AnyShapeStyle(Color.successGreen.opacity(0.06))
                : AnyShapeStyle(Color.surface.opacity(0.7)),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    script.isFilmed
                        ? Color.successGreen.opacity(0.3)
                        : Color.accentGold.opacity(0.15),
                    lineWidth: 1
                )
        )
    }

    // MARK: 卡片底色与边框

    private var cardBackground: some ShapeStyle {
        script.isFilmed
            ? AnyShapeStyle(Color.successGreen.opacity(0.06))
            : AnyShapeStyle(Color.surface.opacity(0.7))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)   // Web: rounded-2xl = 16pt
            .strokeBorder(
                script.isFilmed
                    ? Color.successGreen.opacity(0.3)
                    : Color.accentGold.opacity(0.15),
                lineWidth: 1
            )
    }

    // MARK: 标题行（Web: items-start justify-between，标题截断，按钮在右侧）

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左侧：已拍勾 + 标题（Web: items-center gap-2 min-w-0）
            HStack(spacing: 6) {
                if script.isFilmed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.successGreen)
                }
                Text(script.title)
                    .font(.system(size: 16, weight: .semibold))    // Web: text-base font-semibold
                    .foregroundStyle(script.isFilmed ? .white.opacity(0.5) : .white)
                    .strikethrough(script.isFilmed)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧：操作按钮（Web: ghost 样式 32pt 高、rounded-lg、无底色）
            HStack(spacing: 4) {                                   // Web: gap-1 = 4pt
                ghostButton(icon: "pencil", tint: .white.opacity(0.40)) {
                    onAction(.edit)
                }
                ghostButton(icon: "trash", tint: .accentGold.opacity(0.70)) {
                    onAction(.delete)
                }
            }
        }
    }

    /// 幽灵按钮（Web: 无底色，hover 才现淡底；h-[ctl-3] 32pt 高，rounded-lg，px-2.5）
    private func ghostButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))                            // Web: size={13}
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)                      // Web: h-[var(--ctl-3-h)] = 32pt
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 元信息行

    private var metaRow: some View {
        HStack(spacing: 10) {                                       // Web: gap-2.5 = 10pt
            // 左侧：日期 | 字数 | 时长
            HStack(spacing: 10) {
                Text(script.updatedAt, format: mdyFormat)
                separator
                Text("\(charCount)字")
                separator
                Text("约\(durationText)")
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧：文件夹 + 星标（Web: ml-auto gap-1.5）
            HStack(spacing: 6) {
                folderButton
                starButton
            }
        }
        .font(.system(size: 12))                                    // Web: text-xs = 12pt
        .foregroundStyle(.white.opacity(script.isFilmed ? 0.35 : 0.50))
    }

    private var separator: some View {
        Text("|").foregroundStyle(.white.opacity(0.15))
    }

    // MARK: 文件夹按钮

    private var folderButton: some View {
        Button {
            onAction(.showFolderPicker)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: script.folder != nil ? "folder.fill" : "folder")
                    .font(.system(size: 14))                        // Web: size={14}
                if let folder = script.folder {
                    Text(folder)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.50))      // Web: text-white/50
                        .lineLimit(1)
                        .frame(maxWidth: 120, alignment: .leading)  // Web: max-w-[16vw]
                }
            }
            .foregroundStyle(script.folder != nil ? .accentGold : .white.opacity(0.35))
            .frame(height: 32)
            .padding(.horizontal, 8)                                // Web: px-2
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 星标按钮

    private var starButton: some View {
        Button {
            onAction(.toggleStar)
        } label: {
            Image(systemName: script.starred ? "star.fill" : "star")
                .font(.system(size: 15))                            // Web: size={15}
                .foregroundStyle(script.starred ? .accentGold : .white.opacity(0.35))
                .frame(width: 32, height: 32)                       // Web: p-1.5 + 15pt icon
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 工具

    private var durationText: String {
        PrompterCore.formatTime(
            PrompterCore.estimateDurationSeconds(charCount: charCount, wordsPerMinute: wordsPerMinute)
        )
    }

    private var mdyFormat: Date.FormatStyle {
        .dateTime.year().month().day()
    }
}
