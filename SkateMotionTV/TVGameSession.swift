import Foundation
import Observation

/// Native TV game state. The physical board is optional, but its input source
/// is explicit and cannot silently become a remote-controlled demo on dropout.
@Observable final class TVGameSession {
    enum Phase: Equatable { case idle, armed, playing, paused, finished }
    let engine = RunnerEngine()
    let progress = RunnerProgressStore()
    private(set) var phase: Phase = .idle
    private(set) var source: RunnerControlSource = .motion
    private(set) var message = "Pair your iPhone or choose a remote/controller run"
    private(set) var currentInput = RunnerInput()
    private var adapter = RunnerMotionAdapter()
    private var phoneSession: String?

    @discardableResult func start(course: Int, source: RunnerControlSource,
                                  frame: TVBoardFrame?) -> Bool {
        guard source != .motion || (frame?.ready == true && frame?.isValid == true) else {
            message = "Start and calibrate the board AirPod on your paired iPhone."
            return false
        }
        self.source = source
        engine.reset(course: course)
        adapter.reset()
        currentInput = RunnerInput()
        phoneSession = frame?.sourceSessionID
        phase = source == .motion ? .armed : .playing
        message = source == .motion ? "Tilt your board to start" : "Remote/controller run"
        return true
    }

    func advance(dt: Double, frame: TVBoardFrame?, controller: RunnerInput = RunnerInput()) {
        guard phase == .armed || phase == .playing else { return }
        if source == .motion {
            guard let frame, frame.ready, frame.isValid,
                  frame.sourceSessionID == phoneSession else {
                pause()
                message = "Board link lost or sensor session changed. Reconnect, then Resume."
                return
            }
            let pose = frame.orientation
            currentInput = adapter.accept(pitch: pose?.pitchDegrees,
                engagementDegrees: frame.engagementDegrees,
                allowed: (pose?.upAlignment ?? 0) > 0.45 && pose?.isInverted == false)
        } else { currentInput = controller }
        if phase == .armed {
            guard RunnerStartGate.canBegin(source: source, input: currentInput) else { return }
            phase = .playing
        }
        engine.advance(dt: dt, input: currentInput)
        if engine.gameOver {
            phase = .finished
            message = engine.won ? "Course complete" : "Try again"
            if engine.won { progress.recordCompletion(engine, mode: source.savedRunMode) }
        }
    }

    func pause() {
        guard phase == .playing || phase == .armed else { return }
        phase = .paused
        currentInput = RunnerInput()
        adapter.reset()
        message = "Paused"
    }

    func resume(frame: TVBoardFrame?) {
        guard phase == .paused else { return }
        if source == .motion {
            guard let frame, frame.ready, frame.isValid else {
                message = "No fresh board data. Check the iPhone and local network."
                return
            }
            phoneSession = frame.sourceSessionID
            phase = .armed
            message = "Tilt the board to resume"
        } else { phase = .playing }
        adapter.reset()
    }

    func leave() {
        phase = .idle
        currentInput = RunnerInput()
        adapter.reset()
    }
}
