import Foundation

/// Opt-in, page-lifetime event summaries. Never stores the underlying motion stream.
struct NodDiagnostics {
    enum Condition: String, Codable, CaseIterable, Sendable {
        case waitingData, settling, ready, recognizing, cooldown, manualSuppression
        case walking, posture, impact, interrupted, unavailable, suspended, disabled, calibrating
        var label: String {
            switch self {
            case .waitingData: return "等待耳机数据"
            case .settling: return "等待停稳"
            case .ready: return "已就绪"
            case .recognizing: return "正在识别动作"
            case .cooldown: return "冷却中"
            case .manualSuppression: return "手动操作后重新准备"
            case .walking: return "检测到走动"
            case .posture: return "起始姿态偏离"
            case .impact: return "晃动较大"
            case .interrupted: return "耳机数据中断"
            case .unavailable: return "耳机服务不可用"
            case .suspended: return "暂不检测"
            case .disabled: return "点头控制关闭"
            case .calibrating: return "正在校准"
            }
        }
        var isPlaybackObservation: Bool { self != .suspended && self != .calibrating }
        static func observing(moving: Bool, phase: DeliberateNodDetector.Phase?, postureOff: Bool,
                              unsteady: Bool, suppressed: Bool) -> Self {
            if moving { return .walking }
            if postureOff { return .posture }
            if unsteady { return .impact }
            if suppressed { return .manualSuppression }
            switch phase {
            case .armed: return .ready
            case .descending, .returning: return .recognizing
            case .cooldown: return .cooldown
            default: return .settling
            }
        }
    }
    enum Kind: String, Codable, Sendable {
        case state, detected, applied, rejected, serviceIssue, notApplied, manualMiss, manualFalsePositive, sensorChanged
    }
    enum ServiceIssue: String, Codable, Sendable {
        case unavailable, permissionDenied, sensorChanged, invalidData, interrupted, noInitialData
    }
    struct Counts: Codable, Equatable {
        var detected = 0, applied = 0, rejected = 0, serviceIssues = 0, notApplied = 0
        var manualMisses = 0, manualFalsePositives = 0
        var sensorChanges = 0
    }
    struct Entry: Codable, Identifiable {
        var id = UUID()
        var time: Double
        var kind: Kind
        var label: String
        var reason: String?
        var condition: Condition?
        var contextObservedAt: Double?
        var linkedEntryID: UUID?
        var peakDegrees: Double?
        var gestureDuration: Double?
        var returnStartedAt: Double?
        var applicationDelayMs: Double?
        var returnToAppliedMs: Double?
        var toleratedReturnDisturbanceMs: Double?
    }
    struct Observation: Codable {
        let condition: Condition
        let time: Double
    }
    private(set) var recording = false
    private(set) var beganAt: Double?
    private(set) var startedAtUTC: Date?
    private(set) var counts = Counts()
    private(set) var entries: [Entry] = []
    private(set) var rejectionCounts: [String: Int] = [:]
    private(set) var lastPlaybackObservation: Observation?
    private var condition: Condition?
    private var conditionSince: Double?
    private var seconds: [Condition: Double] = [:]
    private var lastAppliedID: UUID?
    private var lastAppliedEntry: Entry?
    private var lastAppliedMarkedFalse = false
    private var lastRejectedAttempt: DeliberateNodDetector.RejectedAttempt?
    private var manualUndo: [Entry] = []
    static let historyLimit = 128

    var canMark: Bool { beganAt != nil }
    var canMarkFalsePositive: Bool { lastAppliedID != nil && !lastAppliedMarkedFalse }
    var canUndoMark: Bool { !manualUndo.isEmpty }

    mutating func begin(at time: Double, date: Date = Date()) {
        guard time.isFinite, !recording else { return }
        if beganAt == nil { beganAt = time; startedAtUTC = date }
        recording = true; condition = nil; conditionSince = time
    }
    mutating func end(at time: Double) {
        guard recording, time.isFinite else { return }
        closeCondition(at: time)
        recording = false; condition = nil; conditionSince = nil
    }
    mutating func clear(at time: Double, date: Date = Date()) {
        let resume = recording
        self = Self()
        if resume { begin(at: time, date: date) }
    }
    private mutating func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > Self.historyLimit { entries.removeFirst(entries.count - Self.historyLimit) }
    }
    private mutating func closeCondition(at time: Double) {
        if let condition, let since = conditionSince, time >= since {
            seconds[condition, default: 0] += time - since
        }
        conditionSince = time
    }
    mutating func observe(_ next: Condition, at time: Double) {
        guard recording, time.isFinite, time >= (beganAt ?? time), time >= (conditionSince ?? time) else { return }
        if next.isPlaybackObservation { lastPlaybackObservation = .init(condition: next, time: time) }
        guard next != condition else { return }
        closeCondition(at: time); condition = next
        append(.init(time: time, kind: .state, label: next.label, condition: next))
    }
    mutating func detected(_ accepted: DeliberateNodDetector.AcceptedNod, id: UUID) {
        guard recording, accepted.time >= (beganAt ?? accepted.time), !entries.contains(where: { $0.id == id }) else { return }
        counts.detected += 1
        append(.init(id: id, time: accepted.time, kind: .detected, label: "点头识别通过",
                     peakDegrees: accepted.peakDegrees, gestureDuration: accepted.duration,
                     returnStartedAt: accepted.returnStartedAt,
                     toleratedReturnDisturbanceMs: accepted.toleratedReturnDisturbanceSeconds * 1000))
    }
    mutating func applied(id: UUID, playing: Bool, at time: Double) {
        guard recording, time.isFinite,
              let index = entries.firstIndex(where: { $0.id == id && $0.kind == .detected }) else { return }
        entries[index].kind = .applied
        entries[index].label = playing ? "已开始提词" : "已暂停提词"
        if time >= entries[index].time { entries[index].applicationDelayMs = (time - entries[index].time) * 1000 }
        if let returned = entries[index].returnStartedAt, time >= returned {
            entries[index].returnToAppliedMs = (time - returned) * 1000
        }
        counts.applied += 1; lastAppliedID = id; lastAppliedMarkedFalse = false
        lastAppliedEntry = entries[index]
    }
    mutating func notApplied(id: UUID) {
        guard recording, let index = entries.firstIndex(where: { $0.id == id && $0.kind == .detected }) else { return }
        entries[index].kind = .notApplied; entries[index].label = "页面未接收这次点头"
        counts.notApplied += 1
    }
    mutating func rejected(_ attempt: DeliberateNodDetector.RejectedAttempt) {
        guard recording, attempt.time >= (beganAt ?? attempt.time), attempt != lastRejectedAttempt else { return }
        lastRejectedAttempt = attempt
        counts.rejected += 1; rejectionCounts[attempt.reason.rawValue, default: 0] += 1
        append(.init(time: attempt.time, kind: .rejected, label: attempt.reason.hint,
                     reason: attempt.reason.rawValue, peakDegrees: attempt.peakDegrees, gestureDuration: attempt.duration))
    }
    mutating func serviceIssue(_ issue: ServiceIssue, message: String, at time: Double) {
        guard recording, time.isFinite else { return }
        counts.serviceIssues += 1
        append(.init(time: time, kind: .serviceIssue, label: message, reason: issue.rawValue))
    }
    mutating func sensorChanged(to location: Int, at time: Double) {
        guard recording, time.isFinite, time >= (beganAt ?? time) else { return }
        counts.sensorChanges += 1
        append(.init(time: time, kind: .sensorChanged, label: "耳机来源已切换，重新准备", reason: String(location)))
        observe(.settling, at: time)
    }
    mutating func markMiss(at time: Double) {
        guard canMark, time.isFinite else { return }
        let mark = Entry(time: time, kind: .manualMiss, label: "手动标记：一次未响应",
                         condition: lastPlaybackObservation?.condition,
                         contextObservedAt: lastPlaybackObservation?.time)
        counts.manualMisses += 1; addManual(mark)
    }
    mutating func markLastResponseFalse(at time: Double) {
        guard canMarkFalsePositive, time.isFinite, let lastAppliedID else { return }
        let mark = Entry(time: time, kind: .manualFalsePositive, label: "手动标记：上次响应是误触",
                         linkedEntryID: lastAppliedID)
        lastAppliedMarkedFalse = true; counts.manualFalsePositives += 1; addManual(mark)
    }
    private mutating func addManual(_ entry: Entry) {
        append(entry); manualUndo.append(entry)
        if manualUndo.count > 32 { manualUndo.removeFirst() }
    }
    mutating func undoMark() {
        guard let mark = manualUndo.popLast() else { return }
        entries.removeAll { $0.id == mark.id }
        if mark.kind == .manualMiss { counts.manualMisses -= 1 }
        else {
            counts.manualFalsePositives -= 1
            if mark.linkedEntryID == lastAppliedID { lastAppliedMarkedFalse = false }
        }
    }
    func observedSeconds(at time: Double) -> [Condition: Double] {
        var snapshot = seconds
        if recording, let condition, let since = conditionSince, time.isFinite, time >= since {
            snapshot[condition, default: 0] += time - since
        }
        return snapshot
    }
    func exportJSON(at time: Double) throws -> String {
        struct StateDuration: Codable { let condition: Condition; let seconds: Double }
        struct Report: Codable {
            let schemaVersion: Int
            let startedAtUTC: Date?
            let recording: Bool
            let counts: Counts
            let rejectionCounts: [String: Int]
            let statusHeartbeatSeconds: Double
            let observationMethod: String
            let stateDurations: [StateDuration]
            let historyLimit: Int
            let recentEvents: [Entry]
            let latestAppliedResponse: Entry?
            let note: String
        }
        let durations = observedSeconds(at: time)
        let report = Report(schemaVersion: 1, startedAtUTC: startedAtUTC, recording: recording, counts: counts,
                            rejectionCounts: rejectionCounts, statusHeartbeatSeconds: 0.5,
                            observationMethod: "记录开启时逐帧检查状态，仅在状态变化时生成事件；界面状态心跳0.5秒",
                            stateDurations: Condition.allCases.compactMap { key in durations[key].map { .init(condition: key, seconds: $0) } },
                            historyLimit: Self.historyLimit, recentEvents: entries, latestAppliedResponse: lastAppliedEntry,
                            note: "自动观察不是用户意图；手动未响应的参考状态不是已确认原因。未计算成功率。累计计数覆盖整段记录，事件明细仅保留最近128条。状态时长按观察到的状态变化估计；延迟从静稳回正/识别通过算至页面确认，不是完整动作起始延迟。无原始运动采样或稿件内容。")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }
}

struct NodPlaybackTrigger: Sendable {
    let id: UUID
}
