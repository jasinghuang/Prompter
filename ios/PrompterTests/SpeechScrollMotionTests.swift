import XCTest
import UIKit
@testable import Prompter

final class SpeechScrollMotionTests: XCTestCase {
    func testSpeedChangeStartsImmediatelyAndTransitionsOverAboutTwoSeconds() {
        for fps in [60, 120] {
            var speed = SpeechScrollSpeed()
            let dt = 1 / Double(fps)
            let floor = 26.88
            var previous = floor
            for frame in 0..<(fps * 6) {
                let time = Double(frame) * dt
                _ = speed.advance(requested: 240, floor: floor, at: time, deltaTime: dt,
                                  lineHeight: 96, pause: nil, remainingDistance: 10000, allowed: true)
                if time < 0.1 {
                    XCTAssertGreaterThan(speed.velocity, floor, "There must be no 2s waiting gate")
                    XCTAssertLessThan(speed.velocity, floor + 8)
                }
                XCTAssertLessThanOrEqual(abs(speed.velocity - previous), 96 * 3 * 0.95 * dt + 0.0001)
                XCTAssertLessThanOrEqual(speed.velocity, 240.0001)
                if time >= 2 { XCTAssertGreaterThan(speed.velocity, 220) }
                previous = speed.velocity
            }
            XCTAssertGreaterThan(speed.velocity, 150, "A sustained change eventually adapts rather than waiting forever")
        }
    }

    func testShortSpeedPulseIsSmoothedRatherThanReproducedAsASuddenBurst() {
        var speed = SpeechScrollSpeed()
        for frame in 0..<600 {
            let time = Double(frame) / 120
            _ = speed.advance(requested: time < 0.2 ? 240 : 26.88, floor: 26.88, at: time, deltaTime: 1 / 120,
                              lineHeight: 96, pause: nil, remainingDistance: 10000, allowed: true)
            XCTAssertLessThan(speed.velocity, 85, "A 240pt/s recognition pulse must not become a 240pt/s scroll pulse")
            if time >= 4 { XCTAssertEqual(speed.velocity, 26.88, accuracy: 0.3) }
        }
    }

    func testPauseDeceleratesFromActualSpeedOverSeveralSecondsAndTouchStopsImmediately() {
        var speed = SpeechScrollSpeed()
        let dt = 1.0 / 120
        for frame in 0..<720 {
            _ = speed.advance(requested: 180, floor: 26.88, at: Double(frame) * dt, deltaTime: dt,
                              lineHeight: 96, pause: nil, remainingDistance: 10000, allowed: true)
        }
        let before = speed.velocity
        let pause = SpeechPauseContinuation(startedAt: 6)
        var previous = before
        for frame in 0...720 {
            let age = Double(frame) * dt
            _ = speed.advance(requested: 0, floor: 26.88, at: 6 + age, deltaTime: dt,
                              lineHeight: 96, pause: pause, remainingDistance: 10000, allowed: true)
            XCTAssertLessThanOrEqual(speed.velocity, previous + 0.0001)
            if age <= 0.3 { XCTAssertGreaterThan(speed.velocity, before * 0.9, "Pause must not immediately drop to the cruising floor") }
            if age >= 3 && age <= 5 { XCTAssertGreaterThan(speed.velocity, 0) }
            previous = speed.velocity
        }
        XCTAssertEqual(speed.velocity, 0)
        XCTAssertEqual(speed.advance(requested: 200, floor: 26.88, at: 13, deltaTime: dt, lineHeight: 96,
                                     pause: nil, remainingDistance: 10000, allowed: false), 0)
        XCTAssertEqual(speed.velocity, 0)
    }

    func testSpeedGovernorFrameRatesAgreeAndFiniteBoundaryCannotOvershoot() {
        var totals: [Double] = []
        for fps in [60, 120] {
            var speed = SpeechScrollSpeed()
            var position = 0.0
            for frame in 0..<(fps * 8) {
                position += speed.advance(requested: 200, floor: 26.88, at: Double(frame) / Double(fps), deltaTime: 1 / Double(fps),
                                          lineHeight: 96, pause: nil, remainingDistance: 10000, allowed: true)
            }
            totals.append(position)
            var bounded = SpeechScrollSpeed()
            position = 0
            for frame in 0..<(fps * 12) {
                position += bounded.advance(requested: 200, floor: 26.88, at: Double(frame) / Double(fps), deltaTime: 1 / Double(fps),
                                            lineHeight: 96, pause: nil, remainingDistance: 100 - position, allowed: true)
                XCTAssertLessThanOrEqual(position, 100)
            }
            XCTAssertEqual(position, 100, accuracy: 0.1)
            XCTAssertEqual(bounded.velocity, 0, accuracy: 0.1)
        }
        XCTAssertEqual(totals[0], totals[1], accuracy: 3)
    }

    func testLongPauseBrakingIncludesAlreadyUsedCruisingLookahead() {
        let boundary = SpeechScrollSpeed.pauseBoundary(position: 121, confirmedDestination: 54,
                                                        velocity: 15.12, lineHeight: 54)
        XCTAssertGreaterThanOrEqual(boundary, 121 + 4 * 15.12, "Already passing the old target must not shorten the new braking phase")
        XCTAssertLessThanOrEqual(boundary, 54 + 4 * 54)
    }

    func testBriefBreathsDoNotRepeatedlyDiscardSpeedObservation() {
        var speed = SpeechScrollSpeed()
        let dt = 1.0 / 120
        var pause: SpeechPauseContinuation?
        for frame in 0..<1200 {
            let time = Double(frame) * dt
            let quiet = time.truncatingRemainder(dividingBy: 1) >= 0.7
            if quiet && pause == nil { pause = .init(startedAt: time) }
            if !quiet { pause = nil }
            _ = speed.advance(requested: 180, floor: 26.88, at: time, deltaTime: dt, lineHeight: 96,
                              initialSpeed: 72, pause: pause, remainingDistance: 10000, allowed: true)
        }
        XCTAssertGreaterThan(speed.velocity, 100, "Natural phrase gaps must not repeatedly restart the speed transition")
    }

    func testInitialPaceIsUsedOnceAndLaterChangesAreSmoothed() {
        var speed = SpeechScrollSpeed()
        for frame in 0..<240 {
            _ = speed.advance(requested: frame < 12 ? 96 : 240, floor: 26.88, at: Double(frame) / 120, deltaTime: 1 / 120,
                              lineHeight: 96, initialSpeed: frame == 0 ? 96 : 200, pause: nil,
                              remainingDistance: 10000, allowed: true)
            if frame < 12 { XCTAssertEqual(speed.velocity, 96, accuracy: 0.0001) }
            else if frame < 24 { XCTAssertLessThan(speed.velocity, 100, "Changing initialSpeed cannot reseed an existing session") }
        }
        XCTAssertGreaterThan(speed.velocity, 220)
    }
    func testBriefPauseContinuationIsTinyFrameIndependentAndStopsOnItsOwn() {
        let window = SpeechPauseContinuation(startedAt: 10)
        var totals: [Double] = []
        for fps in [60, 120] {
            var motion = SpeechScrollMotion()
            for frame in 0..<(fps * 8) {
                let start = 10 + Double(frame) / Double(fps)
                let previous = motion.position
                _ = motion.applyMinimumMotion(from: previous,
                                              distance: window.distance(from: start, to: start + 1 / Double(fps), lineHeight: 96),
                                              speed: window.speed(at: start + 1 / Double(fps), lineHeight: 96), maximumPosition: 200)
                XCTAssertGreaterThanOrEqual(motion.position, previous)
                XCTAssertLessThanOrEqual(motion.position - previous, 32 / Double(fps) + 0.0001)
                if start >= 16 { XCTAssertEqual(motion.position, previous) }
            }
            XCTAssertGreaterThan(motion.position, 90, "A longer four-second fade preserves visible continuation")
            XCTAssertLessThan(motion.position, 96 * 1.6)
            totals.append(motion.position)
        }
        XCTAssertEqual(totals[0], totals[1], accuracy: 0.0001)
        XCTAssertEqual(window.speed(at: 10, lineHeight: 96), SpeechPauseContinuation.cruisingSpeed(lineHeight: 96), "Entering a pause preserves the listening floor without restarting from zero")
        XCTAssertEqual(window.speed(at: 14, lineHeight: 96), SpeechPauseContinuation.cruisingSpeed(lineHeight: 96) / 2, accuracy: 0.0001)
        XCTAssertEqual(window.speed(at: 16, lineHeight: 96), 0)
    }

    func testPauseContinuationRequiresRecentConfirmedSpeechAndCannotRenewInSilence() {
        var settlement = SpeechFollowSettlement()
        settlement.voiceStopped(at: 10)
        XCTAssertNil(settlement.pauseContinuation(at: 10.2, lastVoice: 9.9))
        settlement.matched(offset: 40, final: false, reachedEnd: false, at: 11)
        settlement.voiceStopped(at: 11.2)
        XCTAssertEqual(settlement.pauseContinuation(at: 11.4, lastVoice: 11.1)?.until, 17.2)
        settlement.matched(offset: 42, final: false, reachedEnd: false, at: 12.8)
        XCTAssertEqual(settlement.pauseContinuation(at: 16.9, lastVoice: 11.1)?.until, 17.2, "Late partials do not restart the pause timer")
        XCTAssertNil(settlement.pauseContinuation(at: 17.21, lastVoice: 11.1))
        settlement.voiceResumed()
        XCTAssertNil(settlement.pauseContinuation(at: 18, lastVoice: 18))
        settlement.voiceStopped(at: 18.1)
        settlement.matched(offset: 44, final: true, reachedEnd: true, at: 18.2)
        XCTAssertNil(settlement.pauseContinuation(at: 18.3, lastVoice: 18), "The end of the script cannot creep forward")
        settlement = .init()
        settlement.matched(offset: 40, final: false, reachedEnd: false, at: 10)
        settlement.voiceStopped(at: 20)
        XCTAssertNil(settlement.pauseContinuation(at: 20.1, lastVoice: 19.9), "Old matches and new noise cannot start scrolling")
    }

    func testRepeatedPauseWindowsCannotExceedVisualBudgetOrRewind() {
        var motion = SpeechScrollMotion()
        for pause in 0..<4 {
            let window = SpeechPauseContinuation(startedAt: Double(pause) * 7)
            for frame in 0..<720 {
                let start = window.startedAt + Double(frame) / 120
                _ = motion.applyMinimumMotion(from: motion.position,
                                              distance: window.distance(from: start, to: start + 1 / 120, lineHeight: 96),
                                              speed: window.speed(at: start + 1 / 120, lineHeight: 96), maximumPosition: 153.6)
            }
        }
        XCTAssertEqual(motion.position, 153.6, accuracy: 0.0001)
        let before = motion.position
        _ = motion.applyMinimumMotion(from: motion.position, distance: 20, speed: 20, maximumPosition: 0)
        XCTAssertEqual(motion.position, before)
    }

    func testListeningCruiseRequiresVoiceAndAlignmentButBridgesDelayedASRBatches() {
        var timing = SpeechFollowTiming()
        timing.observeVoice(at: 10)
        XCTAssertNil(timing.cruiseDeadline(at: 10, hasVoice: true))
        timing.observeMatch(token: 40, at: 10)
        timing.observeVoice(at: 12)
        XCTAssertFalse(timing.canAdvance(at: 12), "A stale target cannot authorize fast pursuit")
        XCTAssertEqual(timing.cruiseDeadline(at: 12, hasVoice: true), 12.65, "Speech maintains the floor while waiting for the next ASR batch")
        XCTAssertNil(timing.cruiseDeadline(at: 12, hasVoice: false))
        XCTAssertNil(timing.cruiseDeadline(at: 12.66, hasVoice: true), "Stale UI flags cannot keep the microphone floor alive")
        timing.observeVoice(at: 16.1)
        XCTAssertNil(timing.cruiseDeadline(at: 16.1, hasVoice: true), "A long alignment failure eventually stops speculative travel")
    }

    func testMinimumMotionDoesNotAddSpeedToFasterASRPursuit() {
        var motion = SpeechScrollMotion()
        for _ in 0..<60 {
            let before = motion.position
            let pursuit = motion.advance(toward: 700, deltaTime: 1 / 120, lineHeight: 96, allowed: true)
            let after = motion.applyMinimumMotion(from: before, distance: 26.88 / 120, speed: 26.88, maximumPosition: 854)
            XCTAssertEqual(after, max(pursuit, before + 26.88 / 120), accuracy: 0.0001)
        }
    }

    func testLargeRecognitionBatchesRespectSpeedAndAccelerationLimits() {
        var motion = SpeechScrollMotion()
        let dt = 1.0 / 120
        var previous = 0.0
        var velocity = 0.0
        for frame in 0..<240 {
            let y = motion.advance(toward: frame < 48 ? 300 : 1400, deltaTime: dt, lineHeight: 60, allowed: true)
            XCTAssertGreaterThanOrEqual(y, previous)
            XCTAssertLessThanOrEqual(y - previous, 960 * dt + 0.0001)
            XCTAssertLessThanOrEqual(abs(motion.velocity - velocity), 15360 * dt + 0.0001)
            previous = y
            velocity = motion.velocity
        }
        XCTAssertLessThanOrEqual(previous, 1400, "A delayed multi-line batch must never overshoot")
    }

    func testSixtyAndOneHundredTwentyHzFollowTheSameTrajectory() {
        func positions(fps: Int) -> [Double] {
            var motion = SpeechScrollMotion()
            var result: [Double] = []
            for frame in 0..<(fps * 6) {
                let time = Double(frame) / Double(fps)
                let y = motion.advance(toward: time < 1.2 ? 120 : 350, deltaTime: 1 / Double(fps), lineHeight: 60, allowed: true)
                if (frame + 1) % (fps / 4) == 0 { result.append(y) }
            }
            return result
        }
        for (sixty, oneTwenty) in zip(positions(fps: 60), positions(fps: 120)) {
            XCTAssertEqual(sixty, oneTwenty, accuracy: 3)
        }
    }

    func testSilenceFreezesExactlyAndResumeDoesNotCarryMomentum() {
        var motion = SpeechScrollMotion()
        for _ in 0..<60 { _ = motion.advance(toward: 700, deltaTime: 1 / 60, lineHeight: 60, allowed: true) }
        let held = motion.position
        for _ in 0..<120 {
            XCTAssertEqual(motion.advance(toward: 900, deltaTime: 1 / 60, lineHeight: 60, allowed: false), held)
        }
        XCTAssertEqual(motion.velocity, 0)
        let resumed = motion.advance(toward: 900, deltaTime: 1 / 60, lineHeight: 60, allowed: true)
        XCTAssertLessThan(resumed - held, 3, "Resume starts with a bounded acceleration ramp")
        motion.reset(to: 550)
        XCTAssertEqual(motion.position, 550)
        XCTAssertEqual(motion.velocity, 0)
    }

    func testFollowerSettlesWithoutOvershootAndLimitsLongFrames() {
        var motion = SpeechScrollMotion()
        for _ in 0..<1200 {
            let y = motion.advance(toward: 75, deltaTime: 1 / 120, lineHeight: 60, allowed: true)
            XCTAssertLessThanOrEqual(y, 75)
            XCTAssertGreaterThanOrEqual(y, 0)
        }
        XCTAssertEqual(motion.position, 75)
        let before = motion.position
        XCTAssertLessThan(motion.advance(toward: 1000, deltaTime: 10, lineHeight: 60, allowed: true) - before, 25)
    }

    func testFastStepwiseRecognitionDoesNotAccumulateMultipleLinesOfLag() {
        var motion = SpeechScrollMotion()
        let dt = 1.0 / 120
        var target = 0.0
        for frame in 0..<1200 {
            // 2.5 visual lines per second, with batched ASR updates every 400ms.
            target = Double(frame / 48) * 60
            _ = motion.advance(toward: target, deltaTime: dt, lineHeight: 60, linesPerSecond: 2.5, allowed: true)
            if frame > 240 { XCTAssertLessThan(target - motion.position, 100, "Lag must remain bounded during a fast read") }
        }
        XCTAssertGreaterThan(motion.position, target - 60)
    }

    func testConfirmedLineReachesReadingZoneDuringShortSettlement() {
        for fps in [60, 120] {
            var motion = SpeechScrollMotion()
            // Actual phone failure: a confirmed target ~4.5 lines away, with
            // only a short voiced/settlement interval left before freezing.
            let destination = 460.0
            for _ in 0..<Int(Double(fps) * 0.3) {
                _ = motion.advance(toward: destination, deltaTime: 1 / Double(fps), lineHeight: 96, allowed: true)
            }
            XCTAssertLessThanOrEqual(destination - motion.position, 80, "The confirmed line must reach the reading zone, not move only a few points")
            let held = motion.position
            XCTAssertEqual(motion.advance(toward: destination, deltaTime: 1 / Double(fps), lineHeight: 96, allowed: false), held)
        }
    }

    func testOrdinaryLineUsesReadingLeadInsteadOfRushingEveryBatch() {
        for fps in [60, 120] {
            var motion = SpeechScrollMotion()
            // The line is already at the anchor. The extra line is a buffer,
            // so consuming all of it in 220ms creates a visible start/stop pulse.
            for _ in 0..<Int(Double(fps) * 0.22) {
                _ = motion.advance(toward: 96, deltaTime: 1 / Double(fps), lineHeight: 96,
                                   minimumPosition: 0, allowed: true)
            }
            XCTAssertGreaterThan(motion.position, 10)
            XCTAssertLessThan(motion.position, 48)
            XCTAssertLessThan(motion.velocity, 200)
            for _ in 0..<fps {
                _ = motion.advance(toward: 96, deltaTime: 1 / Double(fps), lineHeight: 96,
                                   minimumPosition: 0, allowed: true)
            }
            XCTAssertEqual(motion.position, 96, accuracy: 0.1)
        }
    }

    func testSilenceBrakesWithinZoneWithoutRushingToOptionalLead() {
        for fps in [60, 120] {
            var motion = SpeechScrollMotion()
            let dt = 1 / Double(fps)
            for _ in 0..<Int(Double(fps) * 0.2) {
                _ = motion.advance(toward: 96, deltaTime: dt, lineHeight: 96,
                                   minimumPosition: 0, allowed: true)
            }
            let before = motion.position
            let initialVelocity = motion.velocity
            for frame in 0..<Int(Double(fps) * 0.3) {
                _ = motion.advance(toward: 96, deltaTime: dt, lineHeight: 96, minimumPosition: 0,
                                   settlementRemaining: 0.3 - Double(frame) * dt, allowed: true)
                XCTAssertLessThanOrEqual(motion.velocity, initialVelocity + 0.1)
            }
            XCTAssertGreaterThan(motion.position, before)
            XCTAssertLessThan(motion.position, 70, "A line already above the anchor does not need a fast full-line catch-up")
            XCTAssertEqual(motion.velocity, 0, accuracy: 0.1)
        }
    }

    func testLateSilentResultStillReachesAnchorWithinSettlement() {
        for fps in [60, 120] {
            var motion = SpeechScrollMotion()
            for frame in 0..<Int(Double(fps) * 0.3) {
                _ = motion.advance(toward: 460, deltaTime: 1 / Double(fps), lineHeight: 96,
                                   minimumPosition: 380, settlementRemaining: 0.3 - Double(frame) / Double(fps), allowed: true)
            }
            XCTAssertGreaterThanOrEqual(motion.position, 379.9)
            XCTAssertLessThanOrEqual(motion.position, 460)
            XCTAssertEqual(motion.velocity, 0, accuracy: 0.1, "Settle before the deadline instead of freezing at catch-up speed")
        }
    }

    func testSettlementIsBoundedAndCannotStartWithoutASRConfirmation() {
        var settlement = SpeechFollowSettlement()
        settlement.voiceStopped(at: 10)
        XCTAssertFalse(settlement.canSettle(at: 10.1, lastVoice: 10))
        settlement.matched(offset: 40, final: false, reachedEnd: false, at: 11)
        XCTAssertTrue(settlement.canSettle(at: 11.2, lastVoice: 10.9))
        XCTAssertFalse(settlement.canSettle(at: 11.31, lastVoice: 10.9))
        settlement.voiceStopped(at: 12)
        XCTAssertTrue(settlement.canSettle(at: 12.2, lastVoice: 12))
        XCTAssertFalse(settlement.canSettle(at: 12.31, lastVoice: 12))
        XCTAssertFalse(settlement.canSettle(at: 12.1, lastVoice: 8), "Old results cannot revive a silent room")
    }

    func testFinalCompletionWaitsForVisiblePositionOrTheSettlementDeadline() {
        var settlement = SpeechFollowSettlement()
        settlement.matched(offset: 40, final: false, reachedEnd: false, at: 10)
        XCTAssertFalse(settlement.completionReady(delta: -1, voice: false, at: 10.1))
        settlement.matched(offset: 40, final: true, reachedEnd: true, at: 12)
        XCTAssertFalse(settlement.completionReady(delta: 120, voice: false, at: 12.1))
        XCTAssertTrue(settlement.completionReady(delta: -1, voice: false, at: 12.1))
        XCTAssertTrue(settlement.completionReady(delta: 120, voice: false, at: 12.31))
        XCTAssertFalse(settlement.completionReady(delta: 120, voice: true, at: 12.31))
        settlement = SpeechFollowSettlement()
        XCTAssertFalse(settlement.canSettle(at: 12.2, lastVoice: 12), "Manual intervention cancels automatic settlement")
    }

    func testHandoffWaitsForFingerAndInertiaWithoutRestartingTheDelay() {
        var handoff = SpeechTouchHandoff()
        handoff.touchBegan()
        XCTAssertNil(handoff.delayUntilResume(at: 100))
        handoff.scrollingBegan()
        handoff.touchEnded(at: 10)
        XCTAssertNil(handoff.delayUntilResume(at: 12), "Inertia still owns the screen")
        handoff.scrollingEnded()
        XCTAssertEqual(handoff.delayUntilResume(at: 12), 0)
        handoff.reset()
        handoff.touchBegan()
        handoff.scrollingBegan()
        handoff.touchEnded(at: 20)
        handoff.scrollingEnded()
        XCTAssertEqual(handoff.delayUntilResume(at: 20.5), 1)
        handoff.touchBegan()
        XCTAssertNil(handoff.delayUntilResume(at: 30), "Another touch cancels the old deadline")
        handoff.touchEnded(at: 30)
        XCTAssertEqual(handoff.delayUntilResume(at: 30.5), 1)
        handoff.reset()
        XCTAssertFalse(handoff.isSuspended)
        XCTAssertNil(handoff.delayUntilResume(at: 100), "Explicit pause cannot auto-resume")
    }

    @MainActor
    private func reader(voice: Bool = true, size: CGSize = CGSize(width: 700, height: 420)) async throws -> (PrompterScrollView.Coordinator, PrompterTextView) {
        let parent = PrompterScrollView(
            typography: .init(content: String(repeating: "这是用来验证平滑跟随和阅读位置的长稿件。\n", count: 50),
                              fontSize: 36, letterSpacing: 0, lineHeight: 1.5, horizontalPadding: 8, textAlign: "left"),
            isPlaying: true, wordsPerMinute: 160, controller: ScrollEngineController(), voiceMode: voice)
        let coordinator = parent.makeCoordinator()
        let view = PrompterTextView(frame: CGRect(origin: .zero, size: size))
        coordinator.attach(view)
        coordinator.render(parent.typography)
        try await Task.sleep(for: .milliseconds(100))
        return (coordinator, view)
    }

    @MainActor
    func testVoiceAnchorFollowsOrientationAndConstantAnchorRemainsCentered() async throws {
        for size in [CGSize(width: 700, height: 420), CGSize(width: 402, height: 874)] {
          for voice in [true, false] {
            let (coordinator, view) = try await reader(voice: voice, size: size)
            defer { coordinator.teardown() }
            coordinator.scrollToIndex(200)
            let rect = try XCTUnwrap(coordinator.lineRect(forCharIndex: 200))
            let visibleMidY = rect.midY + view.textContainerInset.top - view.contentOffset.y
            XCTAssertEqual(visibleMidY, view.bounds.height * (voice && size.height >= size.width ? 1.0 / 3 : 0.5), accuracy: 0.1)
            if voice {
                coordinator.scrollToIndex(view.text.utf16.count - 1)
                let last = try XCTUnwrap(coordinator.lineRect(forCharIndex: view.text.utf16.count - 1))
                XCTAssertEqual(last.midY + view.textContainerInset.top - view.contentOffset.y, view.bounds.height * (size.height >= size.width ? 1.0 / 3 : 0.5), accuracy: 0.1)
            }
          }
        }
    }

    @MainActor
    func testRecognitionOnlyChangesDestinationAndWordsInOneLineDoNotMoveAnchor() async throws {
        let (coordinator, view) = try await reader()
        defer { coordinator.teardown() }
        coordinator.scrollToIndex(200)
        let baseline = view.contentOffset.y
        var viewportDeltas: [Double] = []
        coordinator.parent.onVoiceViewport = { _, delta in viewportDeltas.append(delta) }
        coordinator.parent.voiceTarget = .init(utf16End: 800, tokensPerSecond: 10)
        coordinator.updateVoiceTarget()
        XCTAssertEqual(view.contentOffset.y, baseline, "ASR must never write contentOffset")
        coordinator.parent.voiceTarget = .init(utf16End: 201, tokensPerSecond: 4)
        coordinator.updateVoiceTarget()
        coordinator.parent.voiceAdvancing = true
        coordinator.setPlaying(true)
        try await Task.sleep(for: .seconds(4))
        let advanced = view.contentOffset.y
        XCTAssertEqual(advanced, baseline + 54, accuracy: 0.1, "Confirmed text gets a one-line lead above the reading anchor")
        XCTAssertLessThan(try XCTUnwrap(viewportDeltas.last), 0, "Report the actual recognized line above the anchor, not only a changed target")
        coordinator.parent.voiceTarget = .init(utf16End: 202, tokensPerSecond: 8)
        coordinator.updateVoiceTarget()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(view.contentOffset.y, advanced, accuracy: 0.1, "Characters within a line must share one target Y")
    }

    @MainActor
    func testNativeClockHonorsSettlementDeadlineEvenWithAStaleAdvanceFlag() async throws {
        let (coordinator, view) = try await reader()
        defer { coordinator.teardown() }
        coordinator.parent.voiceTarget = .init(utf16End: 800, tokensPerSecond: 4)
        coordinator.parent.voiceAdvancing = true
        coordinator.parent.voiceAdvanceUntil = ProcessInfo.processInfo.systemUptime + 0.15
        coordinator.setPlaying(true)
        try await Task.sleep(for: .milliseconds(250))
        let held = view.contentOffset.y
        XCTAssertGreaterThan(held, 0)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.1, "A late SwiftUI/control tick cannot extend the settlement window")
    }

    @MainActor
    func testBriefPauseDriftsPastOldTargetThenStopsWithoutRewinding() async throws {
        let (coordinator, view) = try await reader()
        defer { coordinator.teardown() }
        coordinator.scrollToIndex(200)
        coordinator.parent.voiceTarget = .init(utf16End: 201, tokensPerSecond: 4)
        coordinator.parent.voiceAdvancing = true
        coordinator.setPlaying(true)
        try await Task.sleep(for: .seconds(1.5))
        let before = view.contentOffset.y
        let window = SpeechPauseContinuation(startedAt: ProcessInfo.processInfo.systemUptime)
        coordinator.parent.voiceAdvanceUntil = window.startedAt - 0.1
        coordinator.parent.voicePauseContinuation = window
        try await Task.sleep(for: .seconds(6.2))
        let held = view.contentOffset.y
        XCTAssertGreaterThan(held, before + 50)
        XCTAssertLessThan(held, before + 54 * 1.6 + 0.1)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.01, "Native clock stops even with stale SwiftUI state")
        coordinator.parent.voiceAdvanceUntil = nil
        coordinator.parent.voicePauseContinuation = nil
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.01, "Resuming does not rewind to the previous ASR target")
        coordinator.parent.voicePauseContinuation = .init(startedAt: ProcessInfo.processInfo.systemUptime)
        coordinator.parent.voiceAdvanceUntil = ProcessInfo.processInfo.systemUptime - 0.1
        coordinator.pointerDown()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.01, "Touch immediately blocks continuation too")
    }

    @MainActor
    func testListeningContinuesAtFloorAfterCatchingTargetAndStopsAtDeadlineOrTouch() async throws {
        let (coordinator, view) = try await reader()
        defer { coordinator.teardown() }
        coordinator.scrollToIndex(200)
        coordinator.parent.voiceTarget = .init(utf16End: 201, tokensPerSecond: 4)
        coordinator.parent.voiceAdvancing = true
        coordinator.setPlaying(true)
        try await Task.sleep(for: .seconds(1.5))
        let baseline = view.contentOffset.y
        let now = ProcessInfo.processInfo.systemUptime
        coordinator.parent.voiceAdvanceUntil = now - 1 // No fresh target to pursue.
        coordinator.parent.voiceCruiseUntil = now + 1.2
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertGreaterThan(view.contentOffset.y, baseline + 7, "An unchanged recognized line must not stop voiced cruising")
        try await Task.sleep(for: .milliseconds(750))
        let held = view.contentOffset.y
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.01, "The native deadline also bounds a stale listening flag")
        coordinator.parent.voiceCruiseUntil = ProcessInfo.processInfo.systemUptime + 1
        coordinator.pointerDown()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.01, "Touch suppresses listening cruise immediately")
    }

    @MainActor
    func testTouchFreezesImmediatelyAndRebasesAfterReleaseAndInertia() async throws {
        let (coordinator, view) = try await reader()
        defer { coordinator.teardown() }
        var pauses = 0
        var rebased: [Int] = []
        coordinator.parent.onVoiceInteractionBegan = { pauses += 1 }
        coordinator.parent.onVoiceResumeAt = { rebased.append($0) }
        coordinator.parent.voiceTarget = .init(utf16End: 800, tokensPerSecond: 8)
        coordinator.parent.voiceAdvancing = true
        coordinator.setPlaying(true)
        try await Task.sleep(for: .milliseconds(250))
        coordinator.pointerDown()
        let held = view.contentOffset.y
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(view.contentOffset.y, held, accuracy: 0.1, "Native hold must block even a stale SwiftUI advancing=true")
        coordinator.scrollViewWillBeginDragging(view)
        view.contentOffset.y = 1000
        coordinator.scrollViewDidScroll(view)
        coordinator.pointerUp()
        coordinator.scrollViewDidEndDragging(view, willDecelerate: true)
        try await Task.sleep(for: .milliseconds(1600))
        XCTAssertTrue(rebased.isEmpty)
        coordinator.scrollViewDidEndDecelerating(view)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(pauses, 1)
        XCTAssertEqual(rebased.count, 1)
        XCTAssertGreaterThan(rebased.first ?? 0, 0)
        XCTAssertLessThan(rebased.first ?? 1000, 800, "Rebase must use the visible area, not the old ASR target")
        coordinator.pointerDown()
        coordinator.pointerUp()
        coordinator.setPlaying(false)
        try await Task.sleep(for: .milliseconds(1600))
        XCTAssertEqual(rebased.count, 1, "Permanent pause cancels pending handoff")
    }
}
