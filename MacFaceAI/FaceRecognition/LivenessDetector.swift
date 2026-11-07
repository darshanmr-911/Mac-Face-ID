import Foundation

struct PoseSample: Equatable, Sendable {
    var time: TimeInterval
    var facePresent: Bool
    var yaw: Float?
    var pitch: Float?
    var roll: Float?
    var eyeOpenness: Float?
}

enum LivenessPhase: Equatable, Sendable {
    case waitingForFace
    case holdCenter
    case blink
    case turnOneSide
    case turnOtherSide
    case passed
    case failed(String)

    var title: String {
        switch self {
        case .waitingForFace:
            return "Find face"
        case .holdCenter:
            return "Center"
        case .blink:
            return "Blink"
        case .turnOneSide:
            return "Turn"
        case .turnOtherSide:
            return "Other side"
        case .passed:
            return "Passed"
        case .failed:
            return "Failed"
        }
    }

    var instruction: String {
        switch self {
        case .waitingForFace:
            return "Look at the camera with your whole face in frame."
        case .holdCenter:
            return "Hold still and look straight at the camera."
        case .blink:
            return "Blink once, naturally."
        case .turnOneSide:
            return "Slowly turn your head to either side."
        case .turnOtherSide:
            return "Turn your head to the other side."
        case .passed:
            return "Liveness check passed."
        case .failed(let reason):
            return reason
        }
    }

    var stepIndex: Int {
        switch self {
        case .waitingForFace, .holdCenter, .failed:
            return 0
        case .blink:
            return 1
        case .turnOneSide:
            return 2
        case .turnOtherSide:
            return 3
        case .passed:
            return 4
        }
    }

    var captureBudget: Int {
        switch self {
        case .holdCenter:
            return 3
        case .blink:
            return 1
        case .turnOneSide, .turnOtherSide:
            return 2
        case .passed:
            return 3
        default:
            return 0
        }
    }

    var captureKey: String? {
        switch self {
        case .holdCenter:
            return "center"
        case .blink:
            return "blink"
        case .turnOneSide:
            return "side"
        case .turnOtherSide:
            return "other"
        case .passed:
            return "extra"
        default:
            return nil
        }
    }

    var isTerminalFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct LivenessDetector: Sendable {
    var turnThreshold: Float
    var timeout: TimeInterval

    private(set) var phase: LivenessPhase = .waitingForFace
    private var startedAt: TimeInterval?
    private var phaseStartedAt: TimeInterval?
    private var missingSince: TimeInterval?
    private var recentYaw: [(time: TimeInterval, yaw: Float)] = []
    private var centerYaw: Float = 0
    private var firstDirection: Float = 0
    private var samplesInPhase = 0
    private var opennessHistory: [(time: TimeInterval, value: Float)] = []
    private var sawClosedEyes = false

    init(turnThreshold: Float = 0.28, timeout: TimeInterval = 30) {
        self.turnThreshold = turnThreshold
        self.timeout = timeout
    }

    mutating func reset() {
        self = LivenessDetector(turnThreshold: turnThreshold, timeout: timeout)
    }

    mutating func ingest(_ sample: PoseSample) -> LivenessPhase {
        if phase.isTerminalFailure || phase == .passed {
            return phase
        }
        if startedAt == nil {
            startedAt = sample.time
        }
        if let startedAt, sample.time - startedAt > timeout {
            phase = .failed("Liveness check timed out. Look at the camera and try again.")
            return phase
        }

        guard sample.facePresent else {
            if phase == .waitingForFace {
                return phase
            }
            if missingSince == nil {
                missingSince = sample.time
            }
            if let missingSince, sample.time - missingSince > 0.8 {
                phase = .failed("Your face left the frame. Step back into view and try again.")
            }
            return phase
        }
        missingSince = nil

        switch phase {
        case .waitingForFace:
            transition(to: .holdCenter, at: sample.time)
            ingestHold(sample)
        case .holdCenter:
            ingestHold(sample)
        case .blink:
            ingestBlink(sample)
        case .turnOneSide:
            ingestTurn(sample, first: true)
        case .turnOtherSide:
            ingestTurn(sample, first: false)
        case .passed, .failed:
            break
        }
        return phase
    }

    private mutating func ingestHold(_ sample: PoseSample) {
        guard let yaw = sample.yaw, let roll = sample.roll else { return }
        guard abs(roll) < 0.55 else {
            recentYaw.removeAll()
            return
        }
        recentYaw.append((sample.time, yaw))
        recentYaw.removeAll { sample.time - $0.time > 0.7 }
        guard recentYaw.count >= 4, let first = recentYaw.first?.time, sample.time - first >= 0.45 else {
            return
        }
        let values = recentYaw.map(\.yaw)
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.reduce(0) { partial, value in
            let delta = value - mean
            return partial + delta * delta
        } / Float(values.count)
        guard variance < 0.004 else { return }
        centerYaw = mean
        transition(to: .blink, at: sample.time)
    }

    private mutating func ingestBlink(_ sample: PoseSample) {
        if let openness = sample.eyeOpenness {
            opennessHistory.append((sample.time, openness))
            opennessHistory.removeAll { sample.time - $0.time > 1.6 }
        }
        if opennessHistory.isEmpty, let phaseStartedAt, sample.time - phaseStartedAt > 8 {
            phase = .failed("Blink detection needs both eyes visible. Take off sunglasses and face the camera.")
            return
        }
        guard let openness = sample.eyeOpenness, opennessHistory.count >= 4 else { return }
        let baseline = opennessHistory.map(\.value).max() ?? 0
        guard baseline > 0.05 else { return }
        if !sawClosedEyes && openness < baseline * 0.62 {
            sawClosedEyes = true
        }
        if sawClosedEyes && openness > baseline * 0.85 {
            transition(to: .turnOneSide, at: sample.time)
        }
    }

    private mutating func ingestTurn(_ sample: PoseSample, first: Bool) {
        samplesInPhase += 1
        guard let yaw = sample.yaw, samplesInPhase >= 3 else { return }
        let delta = yaw - centerYaw
        if first {
            guard abs(delta) > turnThreshold else { return }
            firstDirection = delta > 0 ? 1 : -1
            transition(to: .turnOtherSide, at: sample.time)
        } else if delta * firstDirection < -turnThreshold {
            transition(to: .passed, at: sample.time)
        }
    }

    private mutating func transition(to newPhase: LivenessPhase, at time: TimeInterval) {
        phase = newPhase
        phaseStartedAt = time
        samplesInPhase = 0
        if case .blink = newPhase {
            opennessHistory.removeAll()
            sawClosedEyes = false
        }
    }
}
