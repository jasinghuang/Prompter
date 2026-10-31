import SwiftUI
import UIKit

/// 单卡滑动交互（复刻 Web useSwipeAction + SwipeableCard 的两阶段模型）：
/// 右滑揭示绿区（勾=标记已拍 / 已拍时灰底叉=取消），≥40pt 松手提交；
/// 左滑揭示红区（-20 起），越过 -130 出现「松开删除」渐变条+震动，松手删除；
/// 竖向为主的拖动让给列表滚动；提交删除走外部退场+撤销链路。
/// 卡片底色/描边放在不随拖动的静态外壳上（Web: 边框在根节点）——揭示区因此有完整边框收口。
/// 滑动期间置 arbiter.didSwipe，卡片 Button 的 action 据此吞掉松手误触，杜绝滑动误开稿件。
/// 滑动仲裁：SwipeableCard 与卡片 Button 跨闭包共享的抑制标志（引用类型）
final class SwipeArbiter {
    var didSwipe = false
}

enum SwipeGeometry {
    static let limitRight: CGFloat = 72
    static let limitLeft: CGFloat = -150
    static let commitFilmed: CGFloat = 40
    static let commitDelete: CGFloat = -130
    static let revealFilmed: CGFloat = 20
    static let revealDelete: CGFloat = -20
    static let zoneWidth: CGFloat = 72
}

struct SwipeableCard<Content: View>: View {
    let isFilmed: Bool
    var swipeEnabled = true // 多选模式下禁用滑动
    let cardBackground: Color // 静态外壳底色（filmed/选中态由外部决定）
    let cardBorderColor: Color // 静态外壳描边
    let arbiter: SwipeArbiter
    let onCommitFilmed: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var swipeX: CGFloat = 0
    @State private var shook = false
    @State private var shakeTrigger: CGFloat = 0
    @State private var locked = false // 起步判定后锁定横向，不再逐帧比方向（防轨迹抖动中途冻结）

    private let commitRed = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255) // #EF4444
    private let filmedGray = Color(red: 82 / 255, green: 82 / 255, blue: 91 / 255) // #52525B

    var body: some View {
        ZStack {
            filmedZone
            deleteZone
            content()
                .background(swipeX != 0 ? Color.surface : .clear) // 滑动时实底，避免透出底色区
                .offset(x: swipeX)
        }
        .background(cardBackground, in: cardShape)
        .overlay(cardShape.strokeBorder(cardBorderColor, lineWidth: 1))
        .clipShape(cardShape)
        .modifier(CardShake(travel: 4, shakes: 2, animatableData: shakeTrigger))
        .contentShape(cardShape)
        .simultaneousGesture(swipe)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    // MARK: 手势

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard swipeEnabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if !locked {
                    // 起步判定：明显横向（1.2 倍于竖向）才接管；之后锁定，跟手不再受轨迹抖动影响
                    guard abs(dx) > 6, abs(dx) > abs(dy) * 1.2 else { return }
                    locked = true
                }
                if abs(dx) > 8 { arbiter.didSwipe = true } // 松手 tap 由卡片 Button 吞掉
                swipeX = min(SwipeGeometry.limitRight, max(SwipeGeometry.limitLeft, dx))
                if swipeX <= SwipeGeometry.commitDelete && !shook {
                    shook = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred() // 越过删除阈值：震动+抖动
                    withAnimation(.easeInOut(duration: 0.2)) { shakeTrigger += 1 }
                }
            }
            .onEnded { _ in
                defer {
                    shook = false
                    locked = false
                }
                guard swipeEnabled else { return }
                if swipeX > SwipeGeometry.commitFilmed {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onCommitFilmed()
                } else if swipeX <= SwipeGeometry.commitDelete {
                    onDelete() // 退场动画+撤销由外层卡片网格承担
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { swipeX = 0 }
                // 同一轮 runloop 内先让 Button 的 tap 读到 didSwipe，再复位
                DispatchQueue.main.async { arbiter.didSwipe = false }
            }
    }

    // MARK: 揭示区（Web: 72pt 宽、圆角随卡片裁剪）

    // MARK: 连续动效映射（揭示渐显/垃圾桶缩放/红色加深都随距离平滑变化）

    /// -20 → -150 映射 0 → 1
    private var deleteProgress: Double {
        let t = (-swipeX - SwipeGeometry.revealDelete.magnitude)
            / (SwipeGeometry.limitLeft.magnitude - SwipeGeometry.revealDelete.magnitude)
        return min(1, max(0, t))
    }

    /// 右滑揭示（leading）：未拍=绿底白勾；已拍=灰底白叉（取消）
    private var filmedZone: some View {
        HStack {
            ZStack {
                Rectangle().fill(isFilmed ? filmedGray : Color.successGreen)
                Image(systemName: isFilmed ? "xmark" : "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: SwipeGeometry.zoneWidth)
            .opacity(min(1, max(0, (swipeX - 8) / 24))) // 8pt 起连续淡入
            Spacer(minLength: 0)
        }
    }

    /// 左滑揭示（trailing）：垃圾桶随拖动距离连续放大、红区持续加深；越阈值震动+抖动收尾
    private var deleteZone: some View {
        HStack {
            Spacer(minLength: 0)
            ZStack {
                Rectangle().fill(Color.dangerRed)
                Rectangle().fill(commitRed).opacity(deleteProgress) // #DC2626 → #EF4444 渐进加深
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .scaleEffect(1 + 0.25 * deleteProgress) // 1.0 → 1.25 连续放大
            }
            .frame(width: SwipeGeometry.zoneWidth)
            .opacity(min(1, max(0, (-swipeX - 8) / 24)))
        }
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
