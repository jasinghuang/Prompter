import XCTest
@testable import Prompter

final class NodHabitTests: XCTestCase {
    private var profile: HeadGestureCalibration {
        .init(neutral: .init(x: 0, y: 0, z: -1), pitchAxis: .init(x: 1, y: 0, z: 0),
              rollAxis: .init(x: 0, y: 1, z: 0), yawAxis: .init(x: 0, y: 0, z: 1),
              ranges: [20, 20, 20, 20, 30, 30].map { $0 * .pi / 180 }, sensorLocation: 1)
    }
    private func trace(start: Double = 0, offset: Double = 0, amplitude: Double = 8, sensor: Int = 1) -> [HeadMotionSample] {
        stride(from: 0.0, through: 4.0, by: 0.02).map { t in
            let u = (t - 1.1) / 0.8, active = (0...1).contains(u)
            let p = (active ? amplitude * pow(sin(.pi * u), 2) + offset * u : u > 1 ? offset : 0) * .pi / 180
            let rate = active ? (amplitude * .pi / 0.8 * sin(2 * .pi * u) + offset / 0.8) * .pi / 180 : 0
            return .init(time: start + t, gravity: .init(x: 0, y: sin(p), z: -cos(p)),
                         rate: .init(x: rate, y: 0, z: 0), acceleration: .zero, sensorLocation: sensor)
        }
    }
    private func responses(_ samples: [HeadMotionSample], profile: HeadGestureCalibration? = nil,
                           learning: Bool = false) -> [DeliberateNodDetector.AcceptedNod] {
        var d = DeliberateNodDetector(calibration: profile ?? self.profile, learningEndpoint: learning)
        return samples.compactMap { d.process($0) ? d.lastAccepted : nil }
    }
    func testExplicitLearningIncludesEndpointsTheDefaultProductionBandWouldReject() throws {
        let samples = trace(offset: 5)
        XCTAssertTrue(responses(samples).isEmpty)
        let sample = try XCTUnwrap(responses(samples, learning: true).first)
        XCTAssertEqual(sample.returnOffsetDegrees, 5, accuracy: 0.3)
        var adapted = profile
        adapted.habit = try XCTUnwrap(NodHabitProfile.learn([sample, sample, sample]))
        XCTAssertEqual(responses(trace(start: 10, offset: 5), profile: adapted).count, 1,
                       "新的独立点头可使用有限回正适配，不复用训练中的候选")
        XCTAssertTrue(responses(trace(amplitude: 4), profile: adapted).isEmpty, "仍保留6度下限")
    }
    func testHabitLearnerUsesRobustSummariesAndRejectsInconsistentExamples() throws {
        let sample = try XCTUnwrap(responses(trace(offset: 5), learning: true).first)
        var outlier = sample; outlier.returnOffsetDegrees = 6.9
        let habit = try XCTUnwrap(NodHabitProfile.learn([sample, sample, outlier]))
        XCTAssertEqual(habit.returnToleranceDegrees, 6, accuracy: 0.3)
        XCTAssertNil(NodHabitProfile.learn([sample]))
        outlier.peakDegrees = 80
        XCTAssertNil(NodHabitProfile.learn([sample, sample, outlier]))
        outlier = sample; outlier.duration = .nan
        XCTAssertNil(NodHabitProfile.learn([sample, sample, outlier]))
    }
    func testOldCalibrationDecodesWithoutHabitAndNewCalibrationRoundTrips() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var json = try JSONSerialization.jsonObject(with: encoder.encode(profile)) as! [String: Any]
        json.removeValue(forKey: "habit")
        let old = try decoder.decode(HeadGestureCalibration.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.valid); XCTAssertNil(old.habit)
        var adapted = old
        adapted.habit = .init(peakDegrees: 12, durationSeconds: 0.8, returnToleranceDegrees: 6)
        XCTAssertEqual(try decoder.decode(HeadGestureCalibration.self, from: encoder.encode(adapted)), adapted)
        adapted.habit?.returnToleranceDegrees = 50
        XCTAssertTrue(responses(trace(offset: 5), profile: adapted).isEmpty, "非法适配参数回退默认带宽")
    }
    func testNewEarAndNewSourceReuseTheExistingCalibrationAfterFreshSettling() {
        XCTAssertEqual(responses(trace(sensor: 2)).count, 1)
        XCTAssertEqual(responses(trace(sensor: 0)).count, 1)
        var partial = trace().filter { $0.time < 1.5 }
        partial += trace(start: 1.5, sensor: 2)
        XCTAssertEqual(responses(partial).count, 1, "中途换耳丢弃前半次，只响应新耳停稳后的完整点头")
    }
    func testRapidAlternatingSourcesCannotBorrowStillnessOrFinishANod() {
        let samples = trace().enumerated().map { i, value -> HeadMotionSample in
            var s = value; s.sensorLocation = (i / 8) % 2 == 0 ? 1 : 2; return s
        }
        XCTAssertTrue(responses(samples).isEmpty)
    }
    func testAdaptedProfileKeepsWalkingImpactAndOffAxisVetoes() {
        var adapted = profile
        adapted.habit = .init(peakDegrees: 12, durationSeconds: 0.8, returnToleranceDegrees: 7)
        for veto in 0..<3 {
            let samples = trace(offset: 5).map { value -> HeadMotionSample in
                var s = value
                if (1.4...1.5).contains(s.time) {
                    if veto == 0 { s.locomotionDetected = true }
                    if veto == 1 { s.acceleration.y = 0.5 }
                    if veto == 2 { s.rate.z = 0.9 }
                }
                return s
            }
            XCTAssertTrue(responses(samples, profile: adapted).isEmpty)
        }
    }
}
