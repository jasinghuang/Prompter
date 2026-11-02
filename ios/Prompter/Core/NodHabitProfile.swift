import Foundation

/// Explicitly instructed final-step samples, independent of the production return band.
/// Amplitude and tempo describe consistency; only a bounded endpoint tolerance is applied.
struct NodHabitProfile: Codable, Equatable, Sendable {
    var peakDegrees: Double
    var durationSeconds: Double
    var returnToleranceDegrees: Double
    var valid: Bool {
        peakDegrees.isFinite && (6..<85).contains(peakDegrees)
            && durationSeconds.isFinite && (0.26..<1.85).contains(durationSeconds)
            && returnToleranceDegrees.isFinite && (4...7).contains(returnToleranceDegrees)
    }

    static func learn(_ samples: [DeliberateNodDetector.AcceptedNod]) -> Self? {
        guard samples.count == 3,
              samples.allSatisfy({ $0.peakDegrees.isFinite && (6..<85).contains($0.peakDegrees)
                  && $0.duration.isFinite && (0.26..<1.85).contains($0.duration)
                  && $0.returnOffsetDegrees.isFinite && (0...7).contains($0.returnOffsetDegrees) }) else { return nil }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let peaks = samples.map(\.peakDegrees), durations = samples.map(\.duration)
        let offsets = samples.map(\.returnOffsetDegrees), center = median(offsets)
        let deviation = median(offsets.map { abs($0 - center) })
        guard peaks.max()! / peaks.min()! <= 2.5, durations.max()! / durations.min()! <= 2.5,
              deviation <= 1.5 else { return nil }
        return .init(peakDegrees: median(peaks), durationSeconds: median(durations),
                     returnToleranceDegrees: min(7, max(4, center + max(1, deviation * 2))))
    }
}
