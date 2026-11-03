import SwiftUI

/// Black/gold card with direct footer shortcuts; the native table owns row swipes.
struct ScriptCardView: View {
    enum Action { case open, edit, delete, toggleStar, toggleFilmed, showFolderPicker, longPress, toggleSelect }
    // Render the same immutable revision used to compute row order. Observing a live
    // SwiftData model here lets a moving cell resize before the list applies its move.
    let script: ScriptSnapshot
    let wordsPerMinute: Int
    var summary: ScriptLibraryState.Summary?
    var selectMode = false
    var isSelected = false
    var highlighted = false
    let onAction: (Action) -> Void
    @State private var suppressNextTap = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                Button {
                    guard !suppressNextTap else { suppressNextTap = false; return }
                    onAction(selectMode ? .toggleSelect : .open)
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            if script.isFilmed {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.successGreen).accessibilityHidden(true)
                            }
                            Text(script.title).font(.headline).foregroundStyle(.textPrimary).lineLimit(2)
                        }
                        if !script.content.isEmpty {
                            Text(summary?.excerpt ?? String(script.content.prefix(240)))
                                .font(.subheadline).foregroundStyle(.textSecondary).lineLimit(2).lineSpacing(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 14).padding(.bottom, 4).padding(.leading, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ScriptOpenButtonStyle(suppressTap: $suppressNextTap))
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5, maximumDistance: 10).onEnded { _ in
                    guard !selectMode else { return }
                    suppressNextTap = true
                    onAction(.longPress)
                })
                .accessibilityIdentifier("card")
                .accessibilityValue(script.isFilmed ? "已拍摄" : "待拍摄")
                .accessibilityHint(selectMode ? "轻点切换选择" : "打开提词，长按选择稿件")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityAction(named: "编辑") { onAction(.edit) }
                .accessibilityAction(named: "删除") { onAction(.delete) }

                if selectMode {
                    Button { onAction(.toggleSelect) } label: {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(isSelected ? Color.accentGold : .textMuted)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSelected ? "取消选择\(script.title)" : "选择\(script.title)")
                } else {
                    Button { onAction(.edit) } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 17))
                            .foregroundStyle(.textSecondary).frame(width: 44, height: 44)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("编辑\(script.title)").accessibilityIdentifier("card.edit")
                }
            }
            .padding(.trailing, 6)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    metadata
                    Spacer(minLength: 4)
                    shortcuts
                }
                // Keep every field available at larger text sizes instead of hiding the date.
                VStack(alignment: .leading, spacing: 0) {
                    metadata
                    HStack { Spacer(minLength: 0); shortcuts }
                }
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.bottom, 4)
        }
        .background(script.isFilmed ? Color.successGreen.opacity(0.045) : Color.cardSurface,
                    in: RoundedRectangle(cornerRadius: CTL.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CTL.cardRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: highlighted || isSelected ? 1.5 : 1))
    }

    private var borderColor: Color {
        if isSelected || highlighted { return .accentGold.opacity(0.65) }
        return script.isFilmed ? .successGreen.opacity(0.25) : .accentGold.opacity(0.16)
    }

    private var metadata: some View {
        let count = summary?.characterCount ?? PrompterCore.readableCharCount(script.content)
        let duration = PrompterCore.estimateDurationSeconds(charCount: count, wordsPerMinute: wordsPerMinute)
        return HStack(spacing: 7) {
            Text(script.updatedAt, format: .dateTime.month().day())
            Text("|").accessibilityHidden(true)
            Text("\(count)字")
            Text("|").accessibilityHidden(true)
            Text("约\(PrompterCore.formatTime(duration))")
        }
        .font(.caption).foregroundStyle(.textMuted).lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var shortcuts: some View {
        HStack(spacing: 0) {
            Button { onAction(.showFolderPicker) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 15))
                        .foregroundStyle(script.folder == nil ? Color.textMuted : .accentGold)
                    if let folder = script.folder {
                        Text(folder).font(.caption).foregroundStyle(.textSecondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
                .frame(maxWidth: 108).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("移动到文件夹")
            .accessibilityValue(script.folder ?? "未分组")
            .accessibilityIdentifier("card.folder")

            Button { onAction(.toggleStar) } label: {
                Image(systemName: script.starred ? "star.fill" : "star")
                    .font(.system(size: 17))
                    .foregroundStyle(script.starred ? Color.accentGold : .textMuted)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(script.starred ? "取消星标" : "添加星标")
            .accessibilityValue(script.starred ? "已星标" : "未星标")
            .accessibilityIdentifier("card.star")
        }
        .disabled(selectMode).opacity(selectMode ? 0.4 : 1)
    }
}

private struct ScriptOpenButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Binding var suppressTap: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(PressFeedback(pressed: configuration.isPressed, enabled: enabled, scale: 1))
            .onChange(of: configuration.isPressed) { _, pressed in
                if !pressed { DispatchQueue.main.async { suppressTap = false } }
            }
    }
}
