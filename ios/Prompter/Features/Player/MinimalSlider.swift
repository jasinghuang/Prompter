import SwiftUI

/// 极简滑杆（复刻 Web 版 appearance-none 滑杆）：
/// 白 15% 细轨（8pt）+ 24pt 白色圆滑块、无填充色、按压缩放 0.9。
/// 替代系统 Slider——系统款的金色填充轨观感与 Web 差异过大。
struct MinimalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    @State private var dragX: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let trackHeight: CGFloat = 8
            let thumbSize: CGFloat = 24
            let span = geo.size.width - thumbSize
            let fraction = max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let x = dragX ?? span * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15)) // Web: track bg-white/15
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1) // Web: shadow-md
                    .offset(x: x)
                    .frame(maxHeight: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let localX = drag.location.x - thumbSize / 2
                        dragX = max(0, min(span, localX))
                        apply(fraction: span > 0 ? dragX! / span : 0)
                    }
                    .onEnded { _ in
                        dragX = nil // 回到绑定值驱动的位置
                    }
            )
        }
        .frame(height: 44) // Web: h-11 触控热区
    }

    private func apply(fraction: Double) {
        let raw = range.lowerBound + fraction * (range.upperBound - range.lowerBound)
        let snapped = (raw / step).rounded() * step
        value = min(range.upperBound, max(range.lowerBound, snapped))
    }
}
