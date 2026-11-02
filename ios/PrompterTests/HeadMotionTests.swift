import XCTest
@testable import Prompter

final class HeadMotionTests: XCTestCase {
    private let neutral = MotionVector(x: 0, y: 0, z: -1)
    private var profile: HeadGestureCalibration {
        .init(neutral: neutral, pitchAxis: .init(x: 1, y: 0, z: 0),
              rollAxis: .init(x: 0, y: 1, z: 0), yawAxis: .init(x: 0, y: 0, z: 1),
              ranges: [20, 20, 20, 20, 30, 30].map { $0 * .pi / 180 }, sensorLocation: 1)
    }
    private func sample(time: Double, pitch: Double = 0, roll: Double = 0,
                        pitchRate: Double = 0, yawRate: Double = 0, rollRate: Double = 0,
                        acceleration: Double = 0, sensor: Int = 1) -> HeadMotionSample {
        let p = pitch * .pi / 180, r = roll * .pi / 180
        return .init(time: time, gravity: .init(x: -sin(r), y: sin(p) * cos(r), z: -cos(p) * cos(r)),
                     rate: .init(x: pitchRate * .pi / 180, y: rollRate * .pi / 180, z: yawRate * .pi / 180),
                     acceleration: .init(x: 0, y: acceleration, z: 0), sensorLocation: sensor)
    }
    /// A smooth out-and-back rhythm; synthetic gyro is the derivative, not an unrelated trigger.
    private func trace(start: Double = 0, amplitude: Double = 16, duration: Double = 0.65,
                       roll: Bool = false, yaw: Bool = false, walking: Bool = false,
                       interval: Double = 0.02) -> [HeadMotionSample] {
        stride(from: 0.0, through: 3.0 + duration, by: interval).map { t in
            let u = (t - 1.1) / duration
            let active = u >= 0 && u <= 1
            let angle = active ? amplitude * pow(sin(.pi * u), 2) : 0
            let rate = active ? amplitude * .pi / duration * sin(2 * .pi * u) : 0
            return sample(time: start + t, pitch: roll || yaw ? 0 : angle, roll: roll ? angle : 0,
                          pitchRate: roll || yaw ? 0 : rate, yawRate: yaw ? rate : 0,
                          rollRate: roll ? rate : 0, acceleration: walking ? 0.16 * abs(sin(t * 12)) : 0)
        }
    }
    private func count(_ samples: [HeadMotionSample], calibration: HeadGestureCalibration? = nil) -> Int {
        var detector = DeliberateNodDetector(calibration: calibration ?? profile)
        return samples.reduce(0) { $0 + (detector.process($1) ? 1 : 0) }
    }

    /// Settle, move to a new resting pose, stay there, then nod relative to that pose.
    private func restShiftedTrace(offset: Double = -5, amplitude: Double = 8,
                                  duration: Double = 0.8, interval: Double = 0.02) -> [HeadMotionSample] {
        stride(from: 0.0, through: 6.0, by: interval).map { t in
            let u = (t - 1.2) / 0.6
            let resting = t < 1.2 ? 0 : u >= 1 ? offset : offset * (1 - cos(.pi * u)) / 2
            let restingRate = (0...1).contains(u) ? offset * .pi / 1.2 * sin(.pi * u) : 0
            let v = (t - 3.6) / duration, active = (0...1).contains(v)
            let angle = active ? amplitude * pow(sin(.pi * v), 2) : 0
            let rate = active ? amplitude * .pi / duration * sin(2 * .pi * v) : 0
            return sample(time: t, pitch: resting + angle, pitchRate: restingRate + rate)
        }
    }

    func testSmallNodAfterStableHigherRestingPoseAcrossSampleRates() {
        for interval in [0.01, 0.02, 0.04] {
            for offset in [-5.0, -8] {
                XCTAssertEqual(count(restShiftedTrace(offset: offset, interval: interval)), 1,
                               "抬头换坐姿后，相对新坐姿的8度点头仍应响应；offset=\(offset), dt=\(interval)")
            }
        }
        XCTAssertEqual(count(restShiftedTrace(amplitude: 0)), 0, "换坐姿本身不能切换播放")
    }

    func testRestCorrectionHasCumulativeBoundInsteadOfFollowingSlowDriftForever() {
        var detector = DeliberateNodDetector(calibration: profile)
        var events = 0
        for t in stride(from: 0.0, through: 24.0, by: 0.02) {
            let elapsed = min(20, max(0, t - 1))
            if detector.process(sample(time: t, pitch: -0.8 * elapsed,
                                       pitchRate: (1..<21).contains(t) ? -0.8 : 0)) { events += 1 }
            XCTAssertLessThanOrEqual(detector.restAdjustmentDegrees, 12.00001)
        }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(detector.phase, .armed)
        XCTAssertGreaterThan(detector.restAdjustmentDegrees, 8, "允许有限坐姿变化，但不能无限跟随")
    }

    func testRestReferenceIsFrozenThroughoutAnActiveNod() {
        var detector = DeliberateNodDetector(calibration: profile)
        var frozen: Double?, events = 0
        for s in restShiftedTrace(amplitude: 16) {
            if detector.process(s) { events += 1 }
            if detector.phase == .descending || detector.phase == .returning {
                if frozen == nil { frozen = detector.restAdjustmentDegrees }
                XCTAssertEqual(detector.restAdjustmentDegrees, frozen!, accuracy: 0.000001)
            }
        }
        XCTAssertNotNil(frozen)
        XCTAssertEqual(events, 1)
    }

    func testGentleRestingJitterIsToleratedWithoutTriggering() {
        var detector = DeliberateNodDetector(calibration: profile)
        var events = 0
        for original in restShiftedTrace(amplitude: 0) {
            let s = original.time >= 1.8
                ? sample(time: original.time, pitch: -5 + 0.6 * sin(original.time * 10),
                         pitchRate: 6 * cos(original.time * 10)) : original
            if detector.process(s) { events += 1 }
        }
        XCTAssertEqual(events, 0)
        XCTAssertGreaterThan(detector.restAdjustmentDegrees, 4)
        XCTAssertLessThan(detector.restAdjustmentDegrees, 6, "轻微姿态抖动仍可建立有限范围的新基准")
    }

    func testUnstableGravityCannotEstablishANewRestReference() {
        var detector = DeliberateNodDetector(calibration: profile)
        var events = 0
        for original in restShiftedTrace(amplitude: 0) {
            // Exercise inconsistent fusion estimates independently of the quiet gyro gate.
            let jitter = Int(original.time / 0.2) % 2 == 0 ? 2.0 : -2.0
            let s = original.time >= 1.8 ? sample(time: original.time, pitch: -5 + jitter) : original
            if detector.process(s) { events += 1 }
        }
        XCTAssertEqual(events, 0)
        XCTAssertLessThan(detector.restAdjustmentDegrees, 1, "重力方向不断跳动，不能认为已停稳")
    }

    func testResetDiscardsRestCorrectionAndRequiresFreshSettling() {
        var detector = DeliberateNodDetector(calibration: profile)
        for s in restShiftedTrace(amplitude: 0) { _ = detector.process(s) }
        XCTAssertGreaterThan(detector.restAdjustmentDegrees, 4)
        detector.reset()
        XCTAssertEqual(detector.restAdjustmentDegrees, 0)
        for t in stride(from: 10.0, through: 10.2, by: 0.02) { _ = detector.process(sample(time: t, pitch: -5)) }
        XCTAssertEqual(detector.phase, .settling)
        for t in stride(from: 10.22, through: 10.8, by: 0.02) { _ = detector.process(sample(time: t, pitch: -5)) }
        XCTAssertEqual(detector.phase, .armed)
        XCTAssertEqual(detector.restAdjustmentDegrees, 0, accuracy: 0.001)
    }

    func testRestReanchoringUsesLearnedAxesInsteadOfFixedHeadphoneAxes() {
        let axis = MotionVector(x: 1, y: 2, z: 3).unit
        func rotate(_ v: MotionVector) -> MotionVector {
            v * cos(0.9) + axis.cross(v) * sin(0.9) + axis * (axis.dot(v) * (1 - cos(0.9)))
        }
        var learned = profile
        learned.neutral = rotate(profile.neutral); learned.pitchAxis = rotate(profile.pitchAxis)
        learned.rollAxis = rotate(profile.rollAxis); learned.yawAxis = rotate(profile.yawAxis)
        let samples = restShiftedTrace().map { original -> HeadMotionSample in
            var s = original; s.gravity = rotate(s.gravity); s.rate = rotate(s.rate); return s
        }
        XCTAssertTrue(learned.valid)
        XCTAssertEqual(count(samples, calibration: learned), 1)
    }

    func testDeliberateNodTriggersExactlyOnceAcrossSampleRates() {
        for interval in [0.01, 0.02, 0.04] { XCTAssertEqual(count(trace(interval: interval)), 1, "dt=\(interval)") }
    }

    private func accepted(_ samples: [HeadMotionSample]) -> [DeliberateNodDetector.AcceptedNod] {
        var detector = DeliberateNodDetector(calibration: profile)
        return samples.compactMap { detector.process($0) ? detector.lastAccepted : nil }
    }

    func testBriefReturnSpikeDoesNotRestartTheEntireQuietPeriod() {
        for interval in [0.01, 0.02, 0.04] {
            let clean = trace(interval: interval)
            let cleanResult = accepted(clean)
            XCTAssertEqual(cleanResult.count, 1)
            guard let reference = cleanResult.first else { continue }
            let spikeTime = reference.returnStartedAt + 0.06
            let index = clean.indices.min { abs(clean[$0].time - spikeTime) < abs(clean[$1].time - spikeTime) }!
            var noisy = clean
            noisy[index].rate.x = 0.48 // Moderate gyro noise, below all hard vetoes.
            let result = accepted(noisy)
            XCTAssertEqual(result.count, 1)
            guard let response = result.first else { continue }
            XCTAssertLessThanOrEqual(response.time - reference.time, interval * 2 + 0.000001,
                                     "一次轻微尖峰不能强迫重新等待完整100ms，dt=\(interval)")
            XCTAssertGreaterThan(response.time, noisy[index].time + 0.039,
                                 "不能在扰动当帧或尚未重新停稳时触发")
            XCTAssertEqual(response.toleratedReturnDisturbanceSeconds, interval, accuracy: 0.000001)
        }
    }

    func testBriefMildAccelerationDuringReturnStillNeedsRealQuietIntervals() throws {
        for interval in [0.01, 0.02, 0.04] {
            var samples = trace(interval: interval)
            let reference = try XCTUnwrap(accepted(samples).first)
            let index = samples.indices.min { abs(samples[$0].time - reference.returnStartedAt - 0.06)
                < abs(samples[$1].time - reference.returnStartedAt - 0.06) }!
            samples[index].acceleration.y = 0.085
            let result = try XCTUnwrap(accepted(samples).first)
            XCTAssertEqual(result.toleratedReturnDisturbanceSeconds, interval, accuracy: 0.000001)
            XCTAssertGreaterThanOrEqual(result.time - result.returnStartedAt,
                                        0.10 + 2 * interval - 0.000001,
                                        "扰动和首次恢复的区间都不能贡献静稳时长")
        }
    }

    func testPersistentOrRepeatedReturnNoiseCannotAccumulateAQuietEndpoint() throws {
        for interval in [0.01, 0.02, 0.04] {
            let samples = trace(interval: interval)
            let reference = try XCTUnwrap(accepted(samples).first)
            for repeated in [false, true] {
                let noisy = samples.map { original -> HeadMotionSample in
                    var s = original
                    if s.time >= reference.returnStartedAt + interval,
                       !repeated || Int((s.time - reference.returnStartedAt) / 0.06) % 2 == 0 {
                        s.rate.x = 0.48
                    }
                    return s
                }
                XCTAssertEqual(accepted(noisy).count, 0, "持续/反复晃动不能拼成静稳回正，dt=\(interval)")
            }
        }
    }

    func testReturnToleranceDoesNotExcuseLargerNoise() throws {
        for interval in [0.01, 0.02, 0.04] {
            let clean = trace(interval: interval)
            let reference = try XCTUnwrap(accepted(clean).first)
            let index = clean.indices.min { abs(clean[$0].time - reference.returnStartedAt - 0.06)
                < abs(clean[$1].time - reference.returnStartedAt - 0.06) }!
            for gyro in [false, true] {
                var noisy = clean
                if gyro { noisy[index].rate.x = 0.60 }
                else { noisy[index].acceleration.y = 0.11 }
                let response = try XCTUnwrap(accepted(noisy).first)
                XCTAssertEqual(response.toleratedReturnDisturbanceSeconds, 0)
                XCTAssertGreaterThanOrEqual(response.returnStartedAt, noisy[index].time + interval - 0.000001)
            }
        }
    }

    func testReturnWindowLimitsBurstDurationAndDoesNotJoinSeparateBursts() throws {
        let clean = trace(interval: 0.02)
        let reference = try XCTUnwrap(accepted(clean).first)
        let index = clean.indices.min { abs(clean[$0].time - reference.returnStartedAt - 0.04)
            < abs(clean[$1].time - reference.returnStartedAt - 0.04) }!
        var shortBurst = clean
        for i in index...(index + 1) { shortBurst[i].rate.x = 0.48 }
        let shortResult = try XCTUnwrap(accepted(shortBurst).first)
        XCTAssertEqual(shortResult.toleratedReturnDisturbanceSeconds, 0.04, accuracy: 0.000001)
        for positions in [[index, index + 1, index + 2], [index, index + 2]] {
            var noisy = clean
            for i in positions { noisy[i].rate.x = 0.48 }
            let response = try XCTUnwrap(accepted(noisy).first)
            XCTAssertEqual(response.toleratedReturnDisturbanceSeconds, 0)
            XCTAssertGreaterThan(response.returnStartedAt, noisy[positions.last!].time,
                                 "超过40ms或出现第二次扰动，都必须重新准备静稳窗口")
        }
    }

    func testAllHardVetoesStillDiscardTheNodDuringItsReturnWindow() throws {
        let clean = trace()
        let reference = try XCTUnwrap(accepted(clean).first)
        let index = clean.indices.min { abs(clean[$0].time - reference.returnStartedAt - 0.04)
            < abs(clean[$1].time - reference.returnStartedAt - 0.04) }!
        for veto in 0..<7 {
            var samples = clean
            switch veto {
            case 0: samples[index].acceleration.y = 0.5
            case 1: samples[index].rate.z = 0.9
            case 2: samples[index].gravity = .init(x: -sin(0.8), y: 0, z: -cos(0.8))
            case 3: samples[index].locomotionDetected = true
            case 4: samples[index].sensorLocation = 2
            case 5: samples[index].gravity.x = .nan
            default: samples.removeAll { $0.time >= clean[index].time && $0.time < clean[index].time + 0.2 }
            }
            XCTAssertEqual(accepted(samples).count, 0, "回正已开始也不能忽略硬性否决，veto=\(veto)")
        }
    }

    func testReturnNoiseWithoutACompleteNodDoesNotCreatePlaybackEvents() {
        let samples = trace(amplitude: 0).enumerated().map { index, original -> HeadMotionSample in
            var s = original
            if index % 5 == 0 { s.rate.x = 0.48; s.acceleration.y = 0.085 }
            return s
        }
        XCTAssertEqual(count(samples), 0)
        XCTAssertEqual(count(trace(amplitude: 4)), 0)
    }
    func testPlaybackAcceptsDeliberateNodWithinLearnedFortySixDegreeRange() {
        var learned = profile
        learned.ranges[0] = 46 * .pi / 180
        XCTAssertTrue(learned.valid)
        XCTAssertEqual(count(trace(amplitude: 40, duration: 0.8), calibration: learned), 1,
                       "已校准的舒适幅度不应被播放页固定36度上限否决")
        XCTAssertEqual(count(trace(amplitude: 46, duration: 0.9), calibration: learned), 1)
        XCTAssertEqual(count(trace(amplitude: 40, duration: 0.8, walking: true), calibration: learned), 0)
        XCTAssertEqual(count(trace(amplitude: 40, duration: 2.4), calibration: learned), 0)
    }
    func testControlNodAmplitudeDoesNotDependOnCalibrationRange() {
        var learned = profile
        learned.ranges[0] = 46 * .pi / 180
        for interval in [0.01, 0.02, 0.04] {
            for amplitude in [8.0, 10, 16] {
                XCTAssertEqual(count(trace(amplitude: amplitude, duration: 0.8, interval: interval), calibration: learned), 1)
            }
        }
    }
    func testNaturalReturnOffsetAndSmallPosturalNoiseAreAccepted() {
        let samples = trace(duration: 0.8).map { original -> HeadMotionSample in
            let t = original.time, u = (t - 1.1) / 0.8
            let angle = (0...1).contains(u) ? 16 * pow(sin(.pi * u), 2) + 4 * u : u > 1 ? 4 : 0
            let rate = (0...1).contains(u) ? 16 * .pi / 0.8 * sin(2 * .pi * u) + 5 : 0
            return sample(time: t, pitch: angle + 0.3 * sin(t * 10),
                          pitchRate: rate + 3 * cos(t * 10), acceleration: 0.025)
        }
        XCTAssertEqual(count(samples), 1)
    }
    func testRotationalAccelerationDoesNotInvalidateAnOtherwiseCompleteNod() {
        var learned = profile
        learned.ranges[0] = 46 * .pi / 180
        let samples = trace(amplitude: 40, duration: 0.8).map { original -> HeadMotionSample in
            var s = original
            let u = (s.time - 1.1) / 0.8
            // Approximate tangential acceleration: 10 cm lever arm, alpha * r / g.
            if (0...1).contains(u) {
                s.acceleration.y = 0.1 / 9.80665 * 40 * .pi / 180 * 2 * .pi * .pi / (0.8 * 0.8) * cos(2 * .pi * u)
            }
            return s
        }
        XCTAssertGreaterThan(samples.map { $0.acceleration.length }.max()!, 0.12)
        XCTAssertEqual(count(samples, calibration: learned), 1)
        let walking = samples.map { original -> HeadMotionSample in
            var s = original; s.locomotionDetected = true; return s
        }
        XCTAssertEqual(count(walking, calibration: learned), 0)
    }
    func testComfortableRhythmButNotProlongedBowIsAccepted() {
        for duration in [0.5, 0.8, 1.2, 1.6] { XCTAssertEqual(count(trace(duration: duration)), 1, "duration=\(duration)") }
        XCTAssertEqual(count(trace(duration: 2.2)), 0)
    }
    func testSmallChinLiftBeforeDownwardNodDoesNotDiscardIt() {
        let lead = stride(from: 0.0, to: 1.1, by: 0.02).map { t -> HeadMotionSample in
            let u = (t - 0.6) / 0.5
            return sample(time: t, pitch: (0...1).contains(u) ? -6 * pow(sin(.pi * u), 2) : 0,
                          pitchRate: (0...1).contains(u) ? -6 * .pi / 0.5 * sin(2 * .pi * u) : 0)
        }
        XCTAssertEqual(count(lead + trace().filter { $0.time >= 1.1 }), 1)
        XCTAssertEqual(count(trace(amplitude: -16)), 0)
    }
    func testRejectedAttemptReportsActualConditionWithoutRawSampleStorage() {
        var detector = DeliberateNodDetector(calibration: profile)
        for s in trace(amplitude: 4) { _ = detector.process(s) }
        XCTAssertEqual(detector.lastRejection?.reason, .small)
        XCTAssertLessThan(detector.lastRejection?.peakDegrees ?? 100, 6)
        for s in trace(start: 5) { _ = detector.process(s) }
        XCTAssertNil(detector.lastRejection)
    }
    func testImpactAndIncompleteReturnStillReject() {
        let impact = trace().map { original -> HeadMotionSample in
            var s = original; if (1.35...1.4).contains(s.time) { s.acceleration.y = 0.5 }; return s
        }
        XCTAssertEqual(count(impact), 0)
        let held = trace().map { original -> HeadMotionSample in
            if original.time < 1.45 { return original }
            return sample(time: original.time, pitch: 14)
        }
        XCTAssertEqual(count(held), 0)
    }
    func testTenSeparateNaturalNodsEachProduceOneEvent() {
        var learned = profile
        learned.ranges[0] = 46 * .pi / 180
        let samples = (0..<10).flatMap { index in
            trace(start: Double(index) * 4, amplitude: [8.0, 12, 20][index % 3], duration: [0.65, 1.2, 1.6][index % 3])
                .filter { $0.time < Double(index + 1) * 4 }
        }
        XCTAssertEqual(count(samples, calibration: learned), 10)
    }
    func testEachNodRequiresItsOwnStableReturnAfterCooldown() {
        var detector = DeliberateNodDetector(calibration: profile)
        var events: [Double] = []
        for s in trace() + trace(start: 4) {
            if detector.process(s) { events.append(s.time) }
        }
        XCTAssertEqual(events.count, 2)
        XCTAssertGreaterThanOrEqual(events.last ?? 0, 5.84, "不能沿用上一次点头的回正计时器")
    }
    func testStartingPostureGuardStillRejectsLeaningFarAwayBeforeNodding() {
        var detector = DeliberateNodDetector(calibration: profile)
        var events = 0
        for t in stride(from: 0.0, through: 3.0, by: 0.02) {
            if detector.process(sample(time: t, pitch: 45)) { events += 1 }
        }
        XCTAssertEqual(events, 0)
        XCTAssertTrue(detector.startingPostureOff)
        XCTAssertEqual(detector.phase, .settling)
    }
    func testUpwardLeanSlowLeanSmallNodAndIncompleteNodDoNotTrigger() {
        XCTAssertEqual(count(trace(amplitude: -16)), 0)
        XCTAssertEqual(count(trace(duration: 2.2)), 0)
        XCTAssertEqual(count(trace(amplitude: 4)), 0)
        XCTAssertEqual(count(trace().filter { $0.time < 1.5 }), 0)
    }
    func testTurningTiltingAndSyntheticWalkingDoNotTrigger() {
        XCTAssertEqual(count(trace(roll: true)), 0)
        XCTAssertEqual(count(trace(yaw: true)), 0)
        XCTAssertEqual(count(trace(walking: true)), 0)
        let mixed = trace().map { s -> HeadMotionSample in
            var s = s
            if (1.1...1.75).contains(s.time) { s.rate.z = 0.9 }
            return s
        }
        XCTAssertEqual(count(mixed), 0)
    }
    func testNativeWalkingClassificationVetoesEvenLowAccelerationNod() {
        let walking = trace().map { s -> HeadMotionSample in
            var s = s; s.locomotionDetected = true; return s
        }
        XCTAssertEqual(count(walking), 0)
        XCTAssertEqual(count(walking + trace(start: 4)), 1, "走动结束后仍须重新静止，再接受一次完整点头")
    }
    func testMissingSamplesAndSensorSwitchFailClosed() {
        XCTAssertEqual(count(trace().filter { !(1.38...1.65).contains($0.time) }), 0)
        let switched = trace().map { s -> HeadMotionSample in
            var s = s; if s.time > 1.35 { s.sensorLocation = 2 }; return s
        }
        XCTAssertEqual(count(switched), 0)
        var broken = trace()
        broken[66].gravity.x = .nan
        XCTAssertEqual(count(broken), 0)
    }
    func testCooldownAndStillnessPermitDistinctNods() {
        let first = trace().filter { $0.time < 2.0 }
        let secondTooSoon = trace(start: 0.9).filter { $0.time >= 2.0 }
        XCTAssertEqual(count(first + secondTooSoon), 1)
        XCTAssertEqual(count(trace() + trace(start: 4)), 2)
    }
    func testNoSettlingMeansNoNodAndManualResetDropsCandidate() {
        XCTAssertEqual(count(trace().filter { $0.time >= 1.0 }), 0)
        var detector = DeliberateNodDetector(calibration: profile)
        var events = 0
        for s in trace() {
            if abs(s.time - 1.5) < 0.005 { detector.reset() }
            if detector.process(s) { events += 1 }
        }
        XCTAssertEqual(events, 0)
    }
    func testGravitySignedAngleDoesNotFoldBeyondNinetyDegrees() {
        let tilted = sample(time: 0, pitch: 120).gravity
        XCTAssertEqual(neutral.signedAngle(to: tilted, around: profile.pitchAxis) * 180 / .pi, 120, accuracy: 0.001)
    }
    func testNodIsIndependentOfHeadphoneCoordinateAxes() {
        let axis = MotionVector(x: 1, y: 2, z: 3).unit
        func rotate(_ v: MotionVector) -> MotionVector {
            let angle = 1.1
            return v * cos(angle) + axis.cross(v) * sin(angle) + axis * (axis.dot(v) * (1 - cos(angle)))
        }
        var transformed = profile
        transformed.neutral = rotate(profile.neutral)
        transformed.pitchAxis = rotate(profile.pitchAxis)
        transformed.rollAxis = rotate(profile.rollAxis)
        transformed.yawAxis = rotate(profile.yawAxis)
        let samples = trace().map { s -> HeadMotionSample in
            var s = s; s.gravity = rotate(s.gravity); s.rate = rotate(s.rate); return s
        }
        XCTAssertTrue(transformed.valid)
        XCTAssertEqual(count(samples, calibration: transformed), 1)
    }
    func testCalibrationBuildValidatesOppositeDirectionsAndOrthogonality() {
        var captures = zip([profile.pitchAxis, profile.pitchAxis * -1, profile.rollAxis, profile.rollAxis * -1,
                            profile.yawAxis, profile.yawAxis * -1], profile.ranges).map {
            HeadCalibrationCapture(gravity: neutral, axis: $0.0, angle: $0.1, sensorLocation: 1)
        }
        XCTAssertNotNil(HeadGestureCalibration.build(captures))
        captures[1].axis = captures[0].axis
        XCTAssertNil(HeadGestureCalibration.build(captures))
        captures[1].axis = captures[0].axis * -1
        captures[2].axis = captures[0].axis
        XCTAssertNil(HeadGestureCalibration.build(captures))
    }
    func testCalibrationRecorderRequiresExcursionAndStableReturn() {
        var recorder = HeadCalibrationRecorder(action: .down)
        var captures = 0
        for s in trace() {
            if case .captured(let capture) = recorder.process(s) {
                XCTAssertEqual(capture.angle * 180 / .pi, 16, accuracy: 0.2)
                XCTAssertGreaterThan(capture.axis.dot(profile.pitchAxis), 0.99)
                captures += 1; break
            }
        }
        XCTAssertEqual(captures, 1)
        recorder = HeadCalibrationRecorder(action: .down)
        for s in trace(amplitude: 3) {
            if case .captured = recorder.process(s) { XCTFail("Subthreshold motion must not calibrate") }
        }
    }
    func testTurnCalibrationUsesRelativeQuaternionAndGyroNotGravityYaw() {
        var recorder = HeadCalibrationRecorder(action: .turnRight)
        var captured: HeadCalibrationCapture?
        for t in stride(from: 0.0, through: 3.0, by: 0.02) {
            let u = (t - 1.1) / 0.8
            let angle = (0...1).contains(u) ? 30 * pow(sin(.pi * u), 2) * .pi / 180 : 0
            let rate = (0...1).contains(u) ? 30 * .pi / 0.8 * sin(2 * .pi * u) : 0
            var s = sample(time: t, yawRate: rate)
            s.attitude = .init(z: sin(angle / 2), w: cos(angle / 2))
            if case .captured(let value) = recorder.process(s) { captured = value; break }
        }
        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.angle ?? 0, 30 * .pi / 180, accuracy: 0.01)
        XCTAssertGreaterThan(captured?.axis.dot(profile.yawAxis) ?? 0, 0.99)
        XCTAssertEqual(captured?.gravity, neutral, "转头时重力保持不变，不能拿它计算偏航角")
    }
    func testCalibrationShowsPrepareMoveAndReturnStages() {
        var recorder = HeadCalibrationRecorder(action: .down)
        var stages: Set<String> = []
        for s in trace() {
            switch recorder.process(s) {
            case .progress(let p):
                stages.insert(String(describing: p.stage))
                if p.stage == .performing { XCTAssertGreaterThanOrEqual(s.time, 0.65) }
            case .failed(let message): XCTFail(message)
            default: break
            }
        }
        XCTAssertTrue(stages.isSuperset(of: ["preparing", "performing", "returning"]))
    }
    func testCalibrationAcceptsComfortableImperfectReturnWithoutChangingNodDetection() {
        var recorder = HeadCalibrationRecorder(action: .down)
        var captured = false
        for s in trace() {
            let s = s.time >= 1.72 ? sample(time: s.time, pitch: 4.5) : s
            switch recorder.process(s) {
            case .captured: captured = true
            case .failed(let message): XCTFail(message)
            default: break
            }
        }
        XCTAssertTrue(captured, "校准的回正容差应容纳轻微姿态差异")
        XCTAssertEqual(count(trace(walking: true)), 0, "播放时防走动门槛仍需保留")
    }
    func testBriefCalibrationBumpAutomaticallyRepreparesInsteadOfFailingWholeStep() {
        var recorder = HeadCalibrationRecorder(action: .down)
        var captured = false
        for var s in trace() {
            if abs(s.time - 0.08) < 0.001 { s.acceleration.y = 0.3 }
            switch recorder.process(s) {
            case .captured: captured = true
            case .failed(let message): XCTFail(message)
            default: break
            }
        }
        XCTAssertTrue(captured)
    }
    func testSingleAngleSpikeCannotCalibrateAnAxis() {
        var recorder = HeadCalibrationRecorder(action: .down)
        for t in stride(from: 0.0, through: 3.0, by: 0.02) {
            if case .captured = recorder.process(sample(time: t, pitch: abs(t - 1.2) < 0.001 ? 16 : 0)) {
                XCTFail("一次尖峰没有形成持续的有效动作")
            }
        }
    }
    func testCalibrationFitsSmallPostureDifferencesIntoCommonPlane() {
        let p = MotionVector(x: 1, y: 0, z: 0.14).unit
        var captures = zip([p, p * -1, profile.rollAxis, profile.rollAxis * -1,
                            profile.yawAxis, profile.yawAxis * -1], profile.ranges).map {
            HeadCalibrationCapture(gravity: neutral, axis: $0.0, angle: $0.1, sensorLocation: 1)
        }
        captures[3].gravity = sample(time: 0, pitch: 12).gravity
        let result = HeadGestureCalibration.build(captures)
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.valid == true)
        XCTAssertEqual(result?.pitchAxis.dot(neutral) ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(result?.pitchAxis.dot(result?.rollAxis ?? .zero) ?? 1, 0, accuracy: 0.0001)
    }
    func testDirectionProblemIsReportedAfterItsPairWithSpecificRetry() {
        let down = HeadCalibrationCapture(gravity: neutral, axis: profile.pitchAxis, angle: 0.3, sensorLocation: 1)
        XCTAssertNil(HeadGestureCalibration.problem(in: [down]))
        let problem = HeadGestureCalibration.problem(in: [down, down])
        XCTAssertEqual(problem?.action, .up)
        XCTAssertEqual(problem?.related, [.down, .up])
        XCTAssertFalse(problem?.requiresRestart ?? true)
    }
    func testSensorChangeIsNotMisreportedAsWrongHeadMovement() {
        let down = HeadCalibrationCapture(gravity: neutral, axis: profile.pitchAxis, angle: 0.3, sensorLocation: 1)
        let up = HeadCalibrationCapture(gravity: neutral, axis: profile.pitchAxis * -1, angle: 0.3, sensorLocation: 2)
        let issue = HeadGestureCalibration.problem(in: [down, up])
        XCTAssertTrue(issue?.requiresRestart == true)
        XCTAssertTrue(issue?.message.contains("数据源") == true)
    }
    func testLegacySettingsKeepPreferencesAndDefaultNodOff() throws {
        let old = Data(#"{"fontSize":80,"scrollSpeed":240,"mirror":true,"pauseKeyword":"停"}"#.utf8)
        let settings = try JSONDecoder().decode(SettingsData.self, from: old).normalized
        XCTAssertEqual(settings.fontSize, 80); XCTAssertEqual(settings.scrollSpeed, 240)
        XCTAssertTrue(settings.mirror); XCTAssertEqual(settings.automaticPause, .keyword)
        XCTAssertFalse(settings.airPodsNodEnabled); XCTAssertNil(settings.headGestureCalibration)
        let corrupt = Data(#"{"fontSize":82,"airPodsNodEnabled":true,"headGestureCalibration":{"version":999}}"#.utf8)
        let recovered = try JSONDecoder().decode(SettingsData.self, from: corrupt).normalized
        XCTAssertEqual(recovered.fontSize, 82); XCTAssertFalse(recovered.airPodsNodEnabled)
        var valid = SettingsData.defaults
        valid.headGestureCalibration = profile; valid.airPodsNodEnabled = true
        XCTAssertEqual(try JSONDecoder().decode(SettingsData.self, from: JSONEncoder().encode(valid)).normalized, valid)
        valid.headGestureCalibration?.pitchAxis = .zero
        XCTAssertFalse(valid.normalized.airPodsNodEnabled)
    }
}
