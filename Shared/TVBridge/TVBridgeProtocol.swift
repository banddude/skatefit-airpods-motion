import Foundation

/// Versioned, local-network-only bridge. No GPS, identity, commands that start
/// recording, or cloud endpoints are part of this protocol.
struct TVBridgeMessage: Codable, Equatable {
    static let version = 1
    var version = Self.version
    let kind: Kind
    let nonce: UUID
    var frame: TVBoardFrame?

    enum Kind: String, Codable { case request, response }
}

struct TVBoardFrame: Codable, Equatable {
    let sourceSessionID: String
    let sequence: Int
    let ready: Bool
    let sensorAgeSeconds: Double?
    let orientation: BoardOrientation?
    let engagementDegrees: Double
    let goalSeconds: Double
    let holdSeconds: Double
    let bestManualSeconds: Double
    let bestNoseSeconds: Double
    let stability: Double
    let wobbleDegrees: Double
    let sampleRate: Double

    static let inactive = TVBoardFrame(sourceSessionID: "", sequence: 0,
        ready: false, sensorAgeSeconds: nil, orientation: nil,
        engagementDegrees: 7, goalSeconds: 3, holdSeconds: 0,
        bestManualSeconds: 0, bestNoseSeconds: 0, stability: 0,
        wobbleDegrees: 0, sampleRate: 0)

    var isValid: Bool {
        let values = [engagementDegrees, goalSeconds, holdSeconds,
            bestManualSeconds, bestNoseSeconds, stability, wobbleDegrees, sampleRate]
        guard values.allSatisfy(\.isFinite), sequence >= 0,
              (5...25).contains(engagementDegrees), (1...60).contains(goalSeconds),
              (0...100).contains(stability), (0...1000).contains(sampleRate),
              holdSeconds >= 0, bestManualSeconds >= 0,
              bestNoseSeconds >= 0, wobbleDegrees >= 0 else { return false }
        guard ready else { return orientation == nil }
        guard UUID(uuidString: sourceSessionID) != nil, sequence > 0,
              let age = sensorAgeSeconds, age.isFinite, (0...0.20).contains(age),
              let pose = orientation,
              [pose.pitchDegrees, pose.rollDegrees, pose.yawDegrees, pose.upAlignment]
                .allSatisfy(\.isFinite),
              abs(pose.pitchDegrees) <= 180.01, abs(pose.rollDegrees) <= 180.01,
              abs(pose.yawDegrees) <= 180.01,
              (-1.001...1.001).contains(pose.upAlignment) else { return false }
        if let q = pose.relativeQuaternion {
            let norm = q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z
            guard norm.isFinite, (0.98...1.02).contains(norm) else { return false }
        } else if pose.fullAttitudeAvailable { return false }
        return true
    }
}

/// One outstanding challenge per receiver. The TV times request/response
/// locally instead of comparing unsynchronised iPhone and TV clock values.
/// Late buffered responses and duplicate source frames never refresh freshness.
struct TVFrameGate {
    static let responseDeadline = 0.25
    static let freshnessWindow = 0.35
    private(set) var latest: TVBoardFrame?
    private(set) var roundTripSeconds: Double?
    private(set) var receivedAt: TimeInterval?
    private var pending: (nonce: UUID, sentAt: TimeInterval)?
    private var sourceSession: String?
    private var lastSequence = -1
    private var retiredSessions: Set<String> = []

    mutating func request(now: TimeInterval) -> TVBridgeMessage? {
        guard now.isFinite else { return nil }
        if let pending, now >= pending.sentAt &&
            now - pending.sentAt < Self.responseDeadline { return nil }
        let nonce = UUID()
        pending = (nonce, now)
        return TVBridgeMessage(kind: .request, nonce: nonce)
    }

    @discardableResult
    mutating func consume(_ message: TVBridgeMessage, now: TimeInterval) -> Bool {
        guard now.isFinite, message.version == TVBridgeMessage.version,
              message.kind == .response, let pending,
              message.nonce == pending.nonce else { return false }
        self.pending = nil
        guard now >= pending.sentAt, now - pending.sentAt <= Self.responseDeadline,
              let frame = message.frame, frame.isValid else {
            latest = nil
            return false
        }
        guard frame.ready else { latest = nil; return false }
        guard !retiredSessions.contains(frame.sourceSessionID) else { return false }
        if sourceSession != frame.sourceSessionID {
            if let sourceSession { retiredSessions.insert(sourceSession) }
            sourceSession = frame.sourceSessionID
            lastSequence = -1
            latest = nil
        }
        guard frame.sequence > lastSequence else { return false }
        lastSequence = frame.sequence
        latest = frame
        receivedAt = now
        roundTripSeconds = now - pending.sentAt
        return true
    }

    func freshFrame(now: TimeInterval) -> TVBoardFrame? {
        guard now.isFinite, let receivedAt, now >= receivedAt,
              now - receivedAt <= Self.freshnessWindow else { return nil }
        return latest
    }

    mutating func reset() { self = TVFrameGate() }
}

/// Length-delimited JSON over TLS. Maximum length is a protocol constraint,
/// not truncation: malformed or oversized messages close the connection.
struct TVBridgeFraming {
    static let maximumBodyBytes = 16_384
    private var bytes = Data()
    enum Failure: Error { case invalidLength }

    static func encode(_ message: TVBridgeMessage) throws -> Data {
        let data = try JSONEncoder().encode(message)
        guard data.count > 0 && data.count <= maximumBodyBytes else {
            throw Failure.invalidLength
        }
        var count = UInt32(data.count).bigEndian
        var result = withUnsafeBytes(of: &count) { Data($0) }
        result.append(data)
        return result
    }

    mutating func ingest(_ chunk: Data) throws -> [TVBridgeMessage] {
        // receive() requests at most 16 KB. Retained state is at most one
        // incomplete message, so hostile framing cannot grow memory forever.
        guard bytes.count + chunk.count <= Self.maximumBodyBytes * 2 + 8 else {
            throw Failure.invalidLength
        }
        bytes.append(chunk)
        var messages: [TVBridgeMessage] = []
        while bytes.count >= 4 {
            let count = bytes.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard count > 0 && count <= Self.maximumBodyBytes else {
                throw Failure.invalidLength
            }
            let length = Int(count)
            guard bytes.count >= length + 4 else { break }
            let body = Data(bytes.dropFirst(4).prefix(length))
            messages.append(try JSONDecoder().decode(TVBridgeMessage.self, from: body))
            bytes.removeFirst(length + 4)
        }
        return messages
    }
}
