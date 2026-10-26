import Foundation

/// The Core Motion "active" flag means a request was started. It does not
/// prove that a mounted AirPod actually delivered a usable motion sample.
enum HeadphoneStreamHealth {
    static let firstSampleWaitSeconds = 8.0
    static let staleReadingSeconds = 8.0

    static func hasLiveSamples(lastSampleAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let lastSampleAt, lastSampleAt.isFinite, now.isFinite, now >= lastSampleAt
        else { return false }
        return now - lastSampleAt <= 0.75
    }

    static func retryWaitSeconds(afterAttempt attemptNumber: Int) -> TimeInterval {
        // Avoid churning CoreMotion/Bluetooth every few seconds when the earbud
        // is off-ear or the iPhone has lost the AirPods audio route.
        let exponent = max(0, min(2, attemptNumber - 1))
        return firstSampleWaitSeconds * pow(2.0, Double(exponent))
    }

    static func shouldRestart(managerActive: Bool,
                              lastSampleAt: TimeInterval?,
                              lastAttemptAt: TimeInterval?,
                              attempts: Int,
                              now: TimeInterval) -> Bool {
        guard now.isFinite else { return false }
        if managerActive, let lastSampleAt, now >= lastSampleAt,
           now - lastSampleAt <= staleReadingSeconds {
            return false
        }
        guard let lastAttemptAt else { return true }
        guard lastAttemptAt.isFinite, now >= lastAttemptAt else { return false }
        return now - lastAttemptAt >= retryWaitSeconds(afterAttempt: attempts)
    }
}
