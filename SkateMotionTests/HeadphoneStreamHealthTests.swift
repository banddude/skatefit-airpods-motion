import XCTest
@testable import SkateMotion

final class HeadphoneStreamHealthTests: XCTestCase {
    func testMotionManagerBeingActiveDoesNotMeanSamplesAreLive() {
        XCTAssertFalse(HeadphoneStreamHealth.hasLiveSamples(lastSampleAt: nil, now: 100))
        XCTAssertTrue(HeadphoneStreamHealth.hasLiveSamples(lastSampleAt: 99.9, now: 100))
        XCTAssertFalse(HeadphoneStreamHealth.hasLiveSamples(lastSampleAt: 98, now: 100))
        XCTAssertFalse(HeadphoneStreamHealth.hasLiveSamples(lastSampleAt: 101, now: 100))
        XCTAssertFalse(HeadphoneStreamHealth.hasLiveSamples(lastSampleAt: .nan, now: 100))
    }

    func testNoImmediateRestartWhileAwaitingFirstRealFrame() {
        XCTAssertTrue(HeadphoneStreamHealth.shouldRestart(
            managerActive: false, lastSampleAt: nil, lastAttemptAt: nil,
            attempts: 0, now: 100))
        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: true, lastSampleAt: nil, lastAttemptAt: 100,
            attempts: 1, now: 103))
        XCTAssertTrue(HeadphoneStreamHealth.shouldRestart(
            managerActive: true, lastSampleAt: nil, lastAttemptAt: 100,
            attempts: 1, now: 108))
    }

    func testRetriesBackOffInsteadOfCyclingHeadphoneConnection() {
        XCTAssertEqual(HeadphoneStreamHealth.retryWaitSeconds(afterAttempt: 1), 8)
        XCTAssertEqual(HeadphoneStreamHealth.retryWaitSeconds(afterAttempt: 2), 16)
        XCTAssertEqual(HeadphoneStreamHealth.retryWaitSeconds(afterAttempt: 3), 32)
        XCTAssertEqual(HeadphoneStreamHealth.retryWaitSeconds(afterAttempt: 8), 32)

        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: false, lastSampleAt: nil, lastAttemptAt: 100,
            attempts: 3, now: 120))
        XCTAssertTrue(HeadphoneStreamHealth.shouldRestart(
            managerActive: false, lastSampleAt: nil, lastAttemptAt: 100,
            attempts: 3, now: 132))
    }

    func testFreshFramesKeepManagerFromReopeningDuringSkating() {
        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: true, lastSampleAt: 199.8, lastAttemptAt: 100,
            attempts: 2, now: 200))
        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: true, lastSampleAt: 193, lastAttemptAt: 100,
            attempts: 2, now: 200))
        XCTAssertTrue(HeadphoneStreamHealth.shouldRestart(
            managerActive: true, lastSampleAt: 190, lastAttemptAt: 100,
            attempts: 2, now: 200))
    }

    func testStoppedManagerWithFreshSampleNeedsRestartAfterDisconnect() {
        // A manager briefly reporting "not active" must not cause repeated
        // start/stop cycles every 400 ms.
        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: false, lastSampleAt: 200, lastAttemptAt: 198,
            attempts: 1, now: 200.1))
        XCTAssertTrue(HeadphoneStreamHealth.shouldRestart(
            managerActive: false, lastSampleAt: 200, lastAttemptAt: 198,
            attempts: 1, now: 206.1))
        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: true, lastSampleAt: 200, lastAttemptAt: 198,
            attempts: 1, now: 200.1))
        XCTAssertFalse(HeadphoneStreamHealth.shouldRestart(
            managerActive: false, lastSampleAt: nil, lastAttemptAt: 215,
            attempts: 1, now: 214))
    }
}
