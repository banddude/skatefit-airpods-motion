#if os(macOS)
import XCTest
import Foundation
import Network
@testable import SkateFitCore

final class TVBridgeSenderTests: XCTestCase {
    @MainActor func testActualCompanionAnswersOnlyAuthenticatedPolls() async throws {
        let code = TVBridgeSecurity.newCode()
        let name = "SkateFit-Companion-" + UUID().uuidString
        let nonce = UUID()
        let sourceSession = UUID().uuidString
        let listening = expectation(description: "Server listening")
        let response = expectation(description: "iPhone companion response")
        let listener = try NWListener(using: TVBridgeSecurity.parameters(code: code, serviceName: name), on: .any)
        var server: TVBridgeChannel?
        listener.stateUpdateHandler = { state in
            if case .ready = state { listening.fulfill() }
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                let channel = TVBridgeChannel(connection); server = channel
                channel.onReady = { _ = channel.send(TVBridgeMessage(kind: .request, nonce: nonce)) }
                channel.onMessage = { message in
                    XCTAssertEqual(message.nonce, nonce)
                    XCTAssertEqual(message.frame?.sourceSessionID, sourceSession)
                    XCTAssertEqual(message.frame?.sequence, 41)
                    XCTAssertTrue(message.frame?.isValid == true)
                    response.fulfill()
                }
                channel.start()
            }
        }
        listener.start(queue: .main)
        await fulfillment(of: [listening], timeout: 5)
        let port = try XCTUnwrap(listener.port)
        let sender = TVBoardSender()
        XCTAssertFalse(sender.isConnected)
        XCTAssertFalse(sender.isBrowsing)
        var providerCalls = 0
        sender.frameProvider = {
            providerCalls += 1
            return TVBoardFrame(sourceSessionID: sourceSession, sequence: 41,
                ready: true, sensorAgeSeconds: 0.01, orientation: .zero,
                engagementDegrees: 7, goalSeconds: 3, holdSeconds: 1,
                bestManualSeconds: 2, bestNoseSeconds: 1, stability: 88,
                wobbleDegrees: 0.2, sampleRate: 40)
        }
        sender.connect(to: TVBoardSender.Service(name: name,
            endpoint: .hostPort(host: "127.0.0.1", port: port)), code: code)
        await fulfillment(of: [response], timeout: 5)
        XCTAssertTrue(sender.isConnected)
        XCTAssertEqual(providerCalls, 1)
        XCTAssertEqual(sender.framesSent, 1)
        sender.stop()
        XCTAssertFalse(sender.isConnected)
        XCTAssertNil(sender.connectedTV)
        server?.close(); listener.cancel()
    }
}
#endif
