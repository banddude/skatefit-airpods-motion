import XCTest
import Foundation
import Network
#if canImport(SkateFitCore)
@testable import SkateFitCore
#else
@testable import SkateMotionTV
#endif

final class TVBridgeProtocolTests: XCTestCase {
    private let source = UUID().uuidString
    private func frame(sequence: Int = 1, source: String? = nil,
                       pitch: Double = 0, age: Double = 0.01) -> TVBoardFrame {
        TVBoardFrame(sourceSessionID: source ?? self.source, sequence: sequence,
            ready: true, sensorAgeSeconds: age,
            orientation: BoardOrientation(pitchDegrees: pitch, rollDegrees: 0,
                yawDegrees: 0, headingAvailable: true, relativeQuaternion: .identity,
                upAlignment: 1, fullAttitudeAvailable: true),
            engagementDegrees: 7, goalSeconds: 3, holdSeconds: 0,
            bestManualSeconds: 2, bestNoseSeconds: 1, stability: 90,
            wobbleDegrees: 0.5, sampleRate: 40)
    }

    func testValidFrameAndMalformedValues() {
        XCTAssertTrue(frame().isValid)
        XCTAssertTrue(TVBoardFrame.inactive.isValid)
        XCTAssertFalse(frame(sequence: -1).isValid)
        XCTAssertFalse(frame(source: "not-a-session").isValid)
        XCTAssertFalse(frame(pitch: .nan).isValid)
        XCTAssertFalse(frame(pitch: 181).isValid)
        XCTAssertFalse(frame(age: 0.4).isValid)
        XCTAssertFalse(frame(age: -0.1).isValid)
    }

    func testChallengeNonceDeadlineAndFreshness() throws {
        var gate = TVFrameGate()
        let request = try XCTUnwrap(gate.request(now: 10))
        XCTAssertNil(gate.request(now: 10.01), "Only one outstanding request")
        XCTAssertFalse(gate.consume(TVBridgeMessage(kind: .response, nonce: UUID(), frame: frame()), now: 10.02))
        XCTAssertTrue(gate.consume(TVBridgeMessage(kind: .response, nonce: request.nonce, frame: frame()), now: 10.04))
        XCTAssertNotNil(gate.freshFrame(now: 10.05))
        XCTAssertNil(gate.freshFrame(now: 10.5))
        XCTAssertEqual(gate.roundTripSeconds ?? 0, 0.04, accuracy: 0.001)
        let next = try XCTUnwrap(gate.request(now: 11))
        XCTAssertFalse(gate.consume(TVBridgeMessage(kind: .response, nonce: next.nonce, frame: frame(sequence: 2)), now: 11.3))
        XCTAssertNil(gate.freshFrame(now: 11.3))
    }

    func testDuplicateOrRetiredSessionCannotKeepOldPoseAlive() throws {
        var gate = TVFrameGate()
        func respond(_ frame: TVBoardFrame, at time: Double) throws -> Bool {
            let request = try XCTUnwrap(gate.request(now: time))
            return gate.consume(TVBridgeMessage(kind: .response, nonce: request.nonce, frame: frame), now: time + 0.01)
        }
        XCTAssertTrue(try respond(frame(sequence: 10), at: 1))
        XCTAssertFalse(try respond(frame(sequence: 10), at: 1.2))
        XCTAssertNil(gate.freshFrame(now: 1.5))
        let newSession = UUID().uuidString
        XCTAssertTrue(try respond(frame(sequence: 1, source: newSession), at: 2))
        XCTAssertFalse(try respond(frame(sequence: 20), at: 2.1))
        let request = try XCTUnwrap(gate.request(now: 2.2))
        XCTAssertFalse(gate.consume(TVBridgeMessage(kind: .response, nonce: request.nonce, frame: .inactive), now: 2.21))
        XCTAssertNil(gate.freshFrame(now: 2.22))
    }

    func testFramingAcrossEveryByteBoundaryAndCoalescedMessages() throws {
        let message = TVBridgeMessage(kind: .response, nonce: UUID(), frame: frame())
        let bytes = try TVBridgeFraming.encode(message)
        var parser = TVBridgeFraming()
        var results: [TVBridgeMessage] = []
        for byte in bytes { results += try parser.ingest(Data([byte])) }
        XCTAssertEqual(results, [message])
        var combined = TVBridgeFraming()
        XCTAssertEqual(try combined.ingest(bytes + bytes), [message, message])
        var malformed = TVBridgeFraming()
        XCTAssertThrowsError(try malformed.ingest(Data([255,255,255,255])))
        var empty = TVBridgeFraming()
        XCTAssertThrowsError(try empty.ingest(Data([0,0,0,0])))
    }

    func testPairCodeValidation() {
        let code = TVBridgeSecurity.newCode()
        XCTAssertEqual(code.count, 10)
        XCTAssertEqual(TVBridgeSecurity.normalized(code.lowercased()), code)
        XCTAssertEqual(TVBridgeSecurity.normalized(String(code.prefix(5)) + "-" + String(code.suffix(5))), code)
        XCTAssertNil(TVBridgeSecurity.normalized("123"))
        XCTAssertNil(TVBridgeSecurity.normalized("0000000000"))
        XCTAssertNil(TVBridgeSecurity.normalized("abcdefghij"))
    }

    func testBoardTVRunWaitsForRealTiltAndPausesOnLinkLoss() {
        let game = TVGameSession()
        XCTAssertFalse(game.start(course: 1, source: .motion, frame: nil))
        XCTAssertTrue(game.start(course: 1, source: .motion, frame: frame()))
        for _ in 0..<60 { game.advance(dt: 1.0/60, frame: frame()) }
        XCTAssertEqual(game.engine.distance, 0)
        XCTAssertEqual(game.engine.score, 0)
        XCTAssertEqual(game.phase, .armed)
        game.advance(dt: 1.0/30, frame: frame(sequence: 2, pitch: 12))
        XCTAssertGreaterThan(game.engine.height, 0)
        let distance = game.engine.distance
        game.advance(dt: 1.0/30, frame: nil)
        XCTAssertEqual(game.phase, .paused)
        XCTAssertEqual(game.engine.distance, distance)
        game.resume(frame: frame(sequence: 3))
        XCTAssertEqual(game.phase, .armed)
        game.advance(dt: 0.03, frame: frame(sequence: 4, source: UUID().uuidString, pitch: 12))
        XCTAssertEqual(game.phase, .paused, "A newly started iPhone session cannot take over a live run")
    }

    func testControllerTVRunDoesNotRequirePhone() {
        let game = TVGameSession()
        XCTAssertTrue(game.start(course: 1, source: .touch, frame: nil))
        game.advance(dt: 0.03, frame: nil, controller: RunnerInput(manual: true))
        XCTAssertGreaterThan(game.engine.height, 0)
        XCTAssertGreaterThan(game.engine.distance, 0)
        game.pause()
        XCTAssertEqual(game.phase, .paused)
        game.resume(frame: nil)
        XCTAssertEqual(game.phase, .playing)
    }
}

/// Real encrypted loopback connections, not a mocked networking API. These
/// also run on macOS when no tvOS simulator runtime is installed on the host.
final class TVBridgeTLSIntegrationTests: XCTestCase {
    @MainActor func testCorrectCodeEstablishesEncryptedRequestResponse() async throws {
        let name = "SkateFit-Test-" + UUID().uuidString
        let code = TVBridgeSecurity.newCode()
        let listener = try NWListener(using: TVBridgeSecurity.parameters(code: code, serviceName: name), on: .any)
        let listening = expectation(description: "Listener ready")
        let replied = expectation(description: "Encrypted reply received")
        var server: TVBridgeChannel?
        listener.stateUpdateHandler = { state in
            if case .ready = state { listening.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let channel = TVBridgeChannel(connection)
                server = channel
                channel.onMessage = { message in
                    XCTAssertEqual(message.kind, .request)
                    _ = channel.send(TVBridgeMessage(kind: .response, nonce: message.nonce, frame: .inactive))
                }
                channel.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [listening], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let client = TVBridgeChannel(NWConnection(host: "127.0.0.1", port: port,
            using: TVBridgeSecurity.parameters(code: code, serviceName: name)))
        let nonce = UUID()
        client.onReady = { _ = client.send(TVBridgeMessage(kind: .request, nonce: nonce)) }
        client.onMessage = { message in
            XCTAssertEqual(message.nonce, nonce)
            XCTAssertEqual(message.kind, .response)
            XCTAssertEqual(message.frame, .inactive)
            replied.fulfill()
        }
        client.start()
        await fulfillment(of: [replied], timeout: 5)
        client.close(); server?.close(); listener.cancel()
    }

    @MainActor func testWrongCodeCannotReadOrInjectBoardMotion() async throws {
        let name = "SkateFit-Wrong-" + UUID().uuidString
        let listener = try NWListener(using: TVBridgeSecurity.parameters(code: "ABCDE23456", serviceName: name), on: .any)
        let listening = expectation(description: "Listener ready")
        let refused = expectation(description: "Wrong-code connection refused")
        var server: TVBridgeChannel?
        listener.stateUpdateHandler = { state in if case .ready = state { listening.fulfill() } }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let channel = TVBridgeChannel(connection); server = channel
                channel.onMessage = { _ in XCTFail("Unauthenticated peer must not send app data") }
                channel.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [listening], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let client = TVBridgeChannel(NWConnection(host: "127.0.0.1", port: port,
            using: TVBridgeSecurity.parameters(code: "ABCDE23457", serviceName: name)))
        client.onReady = { XCTFail("Wrong pairing code was accepted") }
        client.onClose = { _ in refused.fulfill() }
        client.start()
        await fulfillment(of: [refused], timeout: 7)
        client.onClose = nil
        client.close(); server?.close(); listener.cancel()
    }
}
