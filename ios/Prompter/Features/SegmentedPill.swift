import SwiftUI

/// 自绘滑动药丸分段控件——白色药丸在选项间平滑滑动（复刻 Web 版 SegmentedPill 动画）
struct SegmentedPill<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var fontSize: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width / CGFloat(options.count)
            let selectedIndex = options.firstIndex(where: { $0.value == selection }) ?? 0
            let pillOffset = CGFloat(selectedIndex) * segmentWidth

            ZStack(alignment: .topLeading) {
                // 底槽
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.08))

                // 滑动药丸
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: segmentWidth - 4, height: geo.size.height - 4)
                    .offset(x: pillOffset + 2, y: 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedIndex)

                // 选项按钮
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                        Button {
                            selection = option.value
                        } label: {
                            Text(option.label)
                                .font(.system(size: fontSize, weight: selection == option.value ? .medium : .regular))
                                .foregroundStyle(selection == option.value ? .white : .white.opacity(0.45))
                                .frame(width: segmentWidth, height: geo.size.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
