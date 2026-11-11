import CoreGraphics
import Foundation
import Darwin

struct IslandIndicatorCalibration: Codable, Equatable {
    var edgeOffset = 0.0
    var verticalOffset = 0.0
    var lengthAdjustment = 0.0
    var thicknessAdjustment = 0.0

    var normalized: Self {
        func limit(_ x: Double, _ range: ClosedRange<Double>) -> Double {
            x.isFinite ? min(range.upperBound, max(range.lowerBound, x)) : 0
        }
        return .init(edgeOffset: limit(edgeOffset, -16...16), verticalOffset: limit(verticalOffset, -24...24),
                     lengthAdjustment: limit(lengthAdjustment, -24...24), thicknessAdjustment: limit(thicknessAdjustment, -12...12))
    }
}

/// A profile is an initial alignment, never a claim to read private system UI
/// geometry. Calibration is stored per device by the settings owner.
enum IslandIndicatorGeometry {
    static let currentModel: String = {
        if let simulator = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulator }
        var info = utsname(); uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
        }
    }()
    static func frame(size: CGSize, cameraOnLeft: Bool, model: String,
                      calibration: IslandIndicatorCalibration = .init()) -> CGRect? {
        guard size.width > size.height, size.height > 0 else { return nil }
        let c = calibration.normalized
        let length: CGFloat
        let thickness: CGFloat
        let inset: CGFloat
        if model == "iPhone17,1" {
            // iPhone 16 Pro: Apple dimensional drawing (2024-09-19), display
            // 66.57 x 144.79mm, capsule 20.73 x 6.07mm, center 7.71mm from
            // product top minus 2.44mm display margin. Verify on hardware.
            let pointsPerMM = size.height / 66.57
            length = 20.73 * pointsPerMM
            thickness = 6.07 * pointsPerMM
            inset = (7.71 - 2.44) * pointsPerMM
        } else {
            // Explicitly calibratable fallback for other island models.
            let zoom = size.height / (size.height > 420 ? 430 : 393)
            length = 126 * zoom; thickness = 37.33 * zoom; inset = 29.67 * zoom
        }
        let width = max(20, thickness + c.thicknessAdjustment) + 4
        let height = max(60, length + c.lengthAdjustment) + 4
        let distance = inset + c.edgeOffset
        let x = cameraOnLeft ? distance : size.width - distance
        return CGRect(x: x - width / 2, y: size.height / 2 + c.verticalOffset - height / 2,
                      width: width, height: height)
    }

    /// Top-center start, clockwise on screen. All three visual layers share it.
    static func path(in rect: CGRect, progress: Double = 1) -> CGPath {
        let r = min(rect.width, rect.height) / 2
        let path = CGMutablePath()
        let fraction = PromptIndicatorState.bounded(progress)
        var remaining = (2 * (rect.width + rect.height - 4 * r) + 2 * .pi * r) * fraction
        var point = CGPoint(x: rect.midX, y: rect.minY)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        func line(to end: CGPoint) {
            let distance = hypot(end.x - point.x, end.y - point.y)
            guard distance > 0, remaining > 0 else { return }
            let amount = min(1, remaining / distance)
            path.addLine(to: CGPoint(x: point.x + (end.x - point.x) * amount,
                                    y: point.y + (end.y - point.y) * amount))
            point = end; remaining -= distance
        }
        func arc(center: CGPoint, start: CGFloat) {
            guard remaining > 0, r > 0 else { return }
            let distance = r * .pi / 2
            let end = start + .pi / 2 * min(1, remaining / distance)
            path.addArc(center: center, radius: r, startAngle: start, endAngle: end, clockwise: false)
            point = CGPoint(x: center.x + r * cos(end), y: center.y + r * sin(end))
            remaining -= distance
        }
        line(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        arc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), start: -.pi / 2)
        line(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        arc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), start: 0)
        line(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        arc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), start: .pi / 2)
        line(to: CGPoint(x: rect.minX, y: rect.minY + r))
        arc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), start: .pi)
        line(to: CGPoint(x: rect.midX, y: rect.minY))
        if fraction == 1 { path.closeSubpath() }
        return path
    }
}
