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
    static let limitLeft: CGFloat = -72 // 与红区同宽：滑满正好完整揭示，不再露黑边
    static let commitFilmed: CGFloat = 40
    static let commitDelete: CGFloat = -70
    static let revealFilmed: CGFloat = 20
    static let revealDelete: CGFloat = -20
    static let zoneWidth: CGFloat = 72
}

struct SwipeableCard<Content: View>: View {
    let isFilmed: Bool
    var swipeEnabled = true // 多选模式下禁用滑动
    let contentBackground: Color // 内容层常驻底色（不透明=静止观感；遮盖式揭示的关键）
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
            filmedZone // 遮盖式：色区始终实色，静止时被内容层完全盖住
            deleteZone
            content()
                .background(contentBackground) // 常驻不透明底（= 静止观感），滑动即揭开色区
                .offset(x: swipeX)
        }
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
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard swipeEnabled else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if !locked {
                    // 起步判定：横向明显占优（1.35 倍）才接管；起判 16pt 给列表滚动留足启动空间
                    guard abs(dx) > 10, abs(dx) > abs(dy) * 1.35 else { return }
                    locked = true
                } else if abs(dy) > abs(dx) * 1.6, abs(dy) > 28 {
                    // 锁定后手指明显转向竖向 → 交还列表滚动，卡片弹回
                    locked = false
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { swipeX = 0 }
                    return
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

    /// 揭示(-20) → 触发点(-70) 映射 0 → 1：盖子恰好在触发删除时完全盖合
    private var deleteProgress: Double {
        let t = (-swipeX - SwipeGeometry.revealDelete.magnitude)
            / (SwipeGeometry.commitDelete.magnitude - SwipeGeometry.revealDelete.magnitude)
        return min(1, max(0, t))
    }

    /// 右滑揭示（leading）：对勾随滑动逐笔画出，滑到提交点恰好画完（勾画完=拍完）
    private var filmedZone: some View {
        HStack {
            ZStack {
                Rectangle().fill(isFilmed ? filmedGray : Color.successGreen)
                if isFilmed {
                    DrawnX(progress: filmedProgress)
                } else {
                    DrawnCheck(progress: filmedProgress)
                }
            }
            .frame(width: SwipeGeometry.zoneWidth)
            Spacer(minLength: 0)
        }
    }

    /// 8 → 56pt 映射 0 → 1（提交点 40pt 时对勾已画完）
    private var filmedProgress: Double {
        min(1, max(0, Double((swipeX - 8) / 48)))
    }

    /// 左滑揭示（trailing）：垃圾桶盖随滑动连续盖合（到提交点完全盖住=扔定了），
    /// 图标放大、红区加深；越阈值震动+抖动收尾
    private var deleteZone: some View {
        HStack {
            Spacer(minLength: 0)
            ZStack {
                Rectangle().fill(Color.dangerRed)
                Rectangle().fill(commitRed).opacity(deleteProgress) // #DC2626 → #EF4444 渐进加深
                LidTrash(lidClosed: deleteProgress)
                    .scaleEffect(1 + 0.15 * deleteProgress)
            }
            .frame(width: SwipeGeometry.zoneWidth)
        }
    }
}

// MARK: - 自绘图标动效

/// 带盖垃圾桶：lidProgress 0=盖子翻开 ~80°，1=完全盖住（绕后沿铰点盖合）
private struct LidTrash: View {
    var lidClosed: Double
    private let stroke = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack(alignment: .top) {
            // 桶身：梯形 + 两道竖纹 + 顶部横沿（桶沿顶在 y=8）
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 5, y: 10.6))
                    p.addLine(to: CGPoint(x: 21, y: 10.6))
                    p.addLine(to: CGPoint(x: 19, y: 25))
                    p.addLine(to: CGPoint(x: 7, y: 25))
                    p.closeSubpath()
                }
                .stroke(style: stroke)
                Path { p in
                    p.move(to: CGPoint(x: 10.5, y: 14)); p.addLine(to: CGPoint(x: 10, y: 21))
                    p.move(to: CGPoint(x: 15.5, y: 14)); p.addLine(to: CGPoint(x: 16, y: 21))
                }
                .stroke(style: stroke)
                Capsule().fill() // 顶部提沿
                    .frame(width: 14, height: 2.6)
                    .offset(y: 8)
            }
            // 盖子：闭合时下缘贴住桶沿（y=8），绕左端铰点翻起
            ZStack(alignment: .bottom) {
                Capsule().fill() // 盖顶小把手
                    .frame(width: 5, height: 3)
                    .offset(y: -3)
                Rectangle().fill() // 盖板
                    .frame(width: 19, height: 2.6)
            }
            .frame(width: 19, height: 8, alignment: .bottom) // 盖板落在容器底部=桶沿处
            .rotationEffect(.degrees(-80 * (1 - lidClosed)), anchor: UnitPoint(x: 0, y: 0.5))
        }
        .frame(width: 26, height: 30)
        .foregroundStyle(.white)
    }
}

/// 对勾：随 progress 从起笔逐笔画出
private struct DrawnCheck: View {
    var progress: Double
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 3, y: 13))
            p.addLine(to: CGPoint(x: 9.5, y: 20))
            p.addLine(to: CGPoint(x: 21, y: 6))
        }
        .trim(from: 0, to: progress)
        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        .frame(width: 24, height: 26)
        .foregroundStyle(.white)
    }
}

/// 取消叉：同样逐笔画出
private struct DrawnX: View {
    var progress: Double
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 5)); p.addLine(to: CGPoint(x: 19, y: 19))
            p.move(to: CGPoint(x: 19, y: 5)); p.addLine(to: CGPoint(x: 5, y: 19))
        }
        .trim(from: 0, to: progress)
        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .frame(width: 24, height: 24)
        .foregroundStyle(.white)
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
