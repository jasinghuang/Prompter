import SwiftUI
import UIKit

/// 单卡滑动交互（复刻 Web useSwipeAction + SwipeableCard 的两阶段模型）：
/// 右滑揭示绿区（勾=标记已拍 / 已拍时灰底叉=取消），≥40pt 松手提交；
/// 左滑揭示红区（-20 起），越过 -130 出现「松开删除」渐变条+震动，松手删除；
/// 竖向为主的拖动让给列表滚动；提交删除走外部退场+撤销链路。
enum SwipeGeometry {
    static let limitRight: CGFloat = 72
    static let limitLeft: CGFloat = -150
    static let commitFilmed: CGFloat = 40
    static let commitDelete: CGFloat = -130
    static let revealFilmed: CGFloat = 20
    static let revealDelete: CGFloat = -20
    static let zoneWidth: CGFloat = 72
    static let hintMaxWidth: CGFloat = 80
}

struct SwipeableCard<Content: View>: View {
    let isFilmed: Bool
    let onCommitFilmed: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var swipeX: CGFloat = 0
    @State private var shook = false
    @State private var shakeTrigger: CGFloat = 0

    private let commitRed = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255) // #EF4444
    private let filmedGray = Color(red: 82 / 255, green: 82 / 255, blue: 91 / 255) // #52525B

    var body: some View {
        ZStack {
            filmedZone
            deleteHint
            deleteZone
            content()
                .background(swipeX != 0 ? Color.surface : .clear) // 滑动时实底，避免透出底色区
                .offset(x: swipeX)
                .modifier(CardShake(travel: 4, shakes: 2, animatableData: shakeTrigger))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .simultaneousGesture(swipe) // 与滚动/按钮并存，方向闸门决定谁吃掉这次拖动
    }

    // MARK: 手势

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy) else { return } // 纵向为主的拖动让给列表滚动
                swipeX = min(SwipeGeometry.limitRight, max(SwipeGeometry.limitLeft, dx))
                if swipeX <= SwipeGeometry.commitDelete && !shook {
                    shook = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred() // 越过删除阈值：震动+抖动
                    withAnimation(.easeInOut(duration: 0.2)) { shakeTrigger += 1 }
                }
            }
            .onEnded { _ in
                defer { shook = false }
                if swipeX > SwipeGeometry.commitFilmed {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onCommitFilmed()
                } else if swipeX <= SwipeGeometry.commitDelete {
                    onDelete() // 退场动画+撤销由外层卡片网格承担
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { swipeX = 0 }
            }
    }

    // MARK: 揭示区（Web: 72pt 宽、圆角随卡片裁剪）

    /// 右滑（leading）：未拍=绿底白勾；已拍=灰底白叉（取消）
    private var filmedZone: some View {
        HStack {
            ZStack {
                Rectangle().fill(isFilmed ? filmedGray : Color.successGreen)
                Image(systemName: isFilmed ? "xmark" : "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: SwipeGeometry.zoneWidth)
            .opacity(swipeX > SwipeGeometry.revealFilmed ? 1 : 0)
            Spacer(minLength: 0)
        }
    }

    /// 左滑（trailing）：红区 + 越阈值变亮红、图标放大
    private var deleteZone: some View {
        HStack {
            Spacer(minLength: 0)
            ZStack {
                Rectangle().fill(swipeX <= SwipeGeometry.commitDelete ? commitRed : Color.dangerRed)
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .scaleEffect(swipeX <= SwipeGeometry.commitDelete ? 1.15 : 1)
            }
            .frame(width: SwipeGeometry.zoneWidth)
            .opacity(swipeX < SwipeGeometry.revealDelete ? 1 : 0)
        }
    }

    /// 左滑阶段2：红区左侧的确认引导条（渐变），文案随阈值切换
    private var deleteHint: some View {
        HStack {
            Spacer(minLength: 0)
            Text(swipeX <= SwipeGeometry.commitDelete ? "松开删除" : "继续滑动")
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, SwipeGeometry.zoneWidth)
                .background(alignment: .trailing) {
                    LinearGradient(
                        colors: [Color.dangerRed.opacity(0.85), Color.dangerRed.opacity(0.15)],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                    .frame(width: min(SwipeGeometry.hintMaxWidth, max(0, -swipeX - SwipeGeometry.zoneWidth)))
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea()
                }
                .opacity(swipeX < -SwipeGeometry.zoneWidth ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

/// 卡片越阈值抖动（对应 Web swipe-shake：±4pt、0.2s、两次）
struct CardShake: GeometryEffect {
    var travel: CGFloat
    var shakes: CGFloat
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(
            CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0)
        )
    }
}
