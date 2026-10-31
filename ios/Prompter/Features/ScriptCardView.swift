import SwiftUI

/// 稿件卡片 —— 逐项对齐 Web 版 SwipeableCard 的间距/字号/颜色/布局
struct ScriptCardView: View {
    enum Action {
        case open, edit, delete, toggleStar, toggleFilmed, showFolderPicker
        case longPress, toggleSelect // 长按进入多选 / 多选中点选
    }

    let script: Script
    let wordsPerMinute: Int
    let folders: [String]
    var selectMode = false
    var isSelected = false
    var highlighted = false // 最近打开：返回列表时金边常亮 + 光晕呼吸两次（Web: highlighted）
    let onAction: (Action) -> Void

    private var charCount: Int { PrompterCore.readableCharCount(script.content) }

    @State private var longPressFired = false // 长按刚触发时吞掉随后的 click（Web: longPressFiredRef）
    @State private var swipeArbiter = SwipeArbiter() // 滑动期间吞掉松手误触
    @State private var helloGlow: Double = 0 // 高亮光晕强度：常亮 0.14，呼吸峰值 0.32

    /// 静态外壳底色/描边（随 filmed/多选选中变化；不随拖动滑动）
    private var cardBackground: Color {
        script.isFilmed ? Color.successGreen.opacity(0.06) : Color.surface.opacity(0.7)
    }

    private var cardBorderColor: Color {
        if selectMode && isSelected { return Color.accentGold.opacity(0.6) } // Web 多选选中
        if highlighted { return Color.accentGold.opacity(0.45) } // Web: border-[#D4A432]/45
        return script.isFilmed
            ? Color.successGreen.opacity(0.3)
            : Color.accentGold.opacity(0.15)
    }

    var body: some View {
        SwipeableCard(
            isFilmed: script.isFilmed,
            swipeEnabled: !selectMode, // 多选中禁用滑动（Web: bind 移除）
            cardBackground: cardBackground,
            cardBorderColor: cardBorderColor,
            arbiter: swipeArbiter,
            onCommitFilmed: { onAction(.toggleFilmed) }, // 右滑提交
            onDelete: { onAction(.delete) }               // 左滑阶段2提交
        ) {
            Button {
                if swipeArbiter.didSwipe { return } // 刚发生过滑动，吞掉松手误触
                if longPressFired {
                    longPressFired = false // 长按刚触发，吞掉这次点击
                    return
                }
                onAction(selectMode ? .toggleSelect : .open)
            } label: {
                cardContent
                    .overlay(alignment: .topTrailing) {
                        if selectMode { selectCircle.padding(12) } // 占编辑/删除按钮的同一位置
                    }
                    // 底色已移到静态外壳，内容层透明区域需显式 contentShape 才可点
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableCardStyle())
            // 长按与点按共存（挂 Button 上）；>10pt 移动取消，对齐 Web slop
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)
                    .onEnded { _ in
                        guard !selectMode else { return }
                        longPressFired = true
                        onAction(.longPress)
                    }
            )
            .accessibilityIdentifier("card")
        }
        // 返回高亮：光晕呼吸两次（Web card-hello 1.7s×2）后保持常亮微光；离开高亮即灭
        .shadow(color: Color.accentGold.opacity(helloGlow), radius: 13)
        .onChange(of: highlighted) { _, isOn in
            if isOn {
                helloGlow = 0.14
                withAnimation(.easeInOut(duration: 1.7).repeatCount(2, autoreverses: true)) {
                    helloGlow = 0.32 // 0.14→0.32→0.14 两个来回，落回常亮值
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) { helloGlow = 0 }
            }
        }
        .onAppear {
            // Lazy 网格中卡片若在返回后才滚入视口，change 已错过 → 出场时补呼吸
            if highlighted && helloGlow == 0 {
                helloGlow = 0.14
                withAnimation(.easeInOut(duration: 1.7).repeatCount(2, autoreverses: true)) {
                    helloGlow = 0.32
                }
            }
        }
    }

    /// 多选圈（Web: 22pt 圆——选中=金底深色勾；未选=白30描边）
    private var selectCircle: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentGold : Color.black.opacity(0.4))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.canvas)
            }
        }
        .frame(width: 22, height: 22)
        .overlay(Circle().strokeBorder(isSelected ? .clear : Color.white.opacity(0.3), lineWidth: 1))
        .allowsHitTesting(false)
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
        // 底色/描边由 SwipeableCard 的静态外壳承担（不随拖动滑动）
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

            // 右侧：操作按钮（Web: ghost 样式 32pt 高、rounded-lg、无底色；多选中 invisible 保占位）
            HStack(spacing: 4) {                                   // Web: gap-1 = 4pt
                ghostButton(icon: "pencil", tint: .white.opacity(0.40)) {
                    onAction(.edit)
                }
                .accessibilityIdentifier("card.edit")
                .opacity(selectMode ? 0 : 1)
                .allowsHitTesting(!selectMode) // 隐形仍会吞点击，必须整体摘出命中测试
                ghostButton(icon: "trash", tint: .accentGold.opacity(0.70)) {
                    onAction(.delete)
                }
                .accessibilityIdentifier("card.delete")
                .opacity(selectMode ? 0 : 1)
                .allowsHitTesting(!selectMode)
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

            // 右侧：文件夹 + 星标（Web: ml-auto gap-1.5；多选中禁用降透明度）
            HStack(spacing: 6) {
                folderButton
                starButton
            }
            .opacity(selectMode ? 0.3 : 1)
            .allowsHitTesting(!selectMode)
        }
        .font(.system(size: 12))                                    // Web: text-xs = 12pt
        .foregroundStyle(.white.opacity(script.isFilmed ? 0.35 : 0.50))
    }

    private var separator: some View {
        Text("|").foregroundStyle(.white.opacity(0.15))
    }

    // MARK: 文件夹按钮

    /// Web 版对齐：图标恒为轮廓 Folder（形状不随有无文件夹变化），有文件夹=金色+名字
    private var folderButton: some View {
        Button {
            onAction(.showFolderPicker)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.system(size: 14))                        // Web: size={14}
                if let folder = script.folder {
                    Text(folder)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.50))      // Web: text-white/50
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true) // 理想宽=文本宽，空间不足时尾部截断
                }
            }
            .foregroundStyle(script.folder != nil ? .accentGold : .white.opacity(0.35))
            .frame(height: 32)
            .padding(.horizontal, 8)                                // Web: px-2
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("card.folder")
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
        .accessibilityIdentifier("card.star")
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
