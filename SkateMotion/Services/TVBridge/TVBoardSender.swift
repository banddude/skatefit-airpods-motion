import Foundation
import Combine
import Network

/// iPhone companion. Discover/Connect are explicit user actions; calibration,
/// raw session capture and upload settings remain owned by MotionStore.
@MainActor final class TVBoardSender: ObservableObject {
    struct Service: Identifiable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }
    @Published private(set) var services: [Service] = []
    @Published private(set) var status = "TV sharing off"
    @Published private(set) var isBrowsing = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedTV: String?
    @Published private(set) var framesSent = 0
    var frameProvider: (() -> TVBoardFrame)?

    private var browser: NWBrowser?
    private var channel: TVBridgeChannel?
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var previousRequestAt = 0.0

    func browse() {
        stop()
        generation = UUID()
        let session = generation
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        let browser = NWBrowser(for: .bonjour(type: TVBridgeSecurity.serviceType,
                                              domain: "local."), using: parameters)
        self.browser = browser
        isBrowsing = true
        status = "Searching your local network for SkateFit on Apple TV"
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                self.services = results.compactMap { result -> Service? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return Service(name: name, endpoint: result.endpoint)
                }.sorted { $0.name < $1.name }
                self.status = self.services.isEmpty
                    ? "No TV found. Open SkateFit on the TV and choose Pair iPhone."
                    : "Select your TV and enter its on-screen pairing code."
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }
                if case .failed = state {
                    self.stop()
                    self.status = "Discovery failed. Allow Local Network in iPhone Settings."
                }
            }
        }
        browser.start(queue: .main)
    }

    func connect(to service: Service, code: String) {
        guard let code = TVBridgeSecurity.normalized(code) else {
            status = "Enter the 10-character code shown on the TV."
            return
        }
        stop()
        generation = UUID()
        let session = generation
        let channel = TVBridgeChannel(NWConnection(to: service.endpoint,
            using: TVBridgeSecurity.parameters(code: code, serviceName: service.name)))
        self.channel = channel
        connectedTV = service.name
        status = "Pairing securely with Apple TV"
        channel.onReady = { [weak self, weak channel] in
            guard let self, self.generation == session, self.channel === channel else { return }
            self.timeout?.cancel()
            self.isConnected = true
            self.status = "Connected. Keep this app open; start/calibrate your board session."
        }
        channel.onMessage = { [weak self, weak channel] message in
            guard let self, self.generation == session, self.channel === channel,
                  self.isConnected else { return }
            guard message.version == TVBridgeMessage.version,
                  message.kind == .request, message.frame == nil else {
                channel?.close(reason: "Incompatible SkateFit TV request."); return
            }
            let now = ProcessInfo.processInfo.systemUptime
            // A paired device still cannot demand unlimited work. Legitimate
            // requests occur at 30 Hz; requests above 60 Hz are refused.
            guard now - self.previousRequestAt >= 1.0 / 60 else { return }
            self.previousRequestAt = now
            let sample = self.frameProvider?() ?? .inactive
            let response = TVBridgeMessage(kind: .response, nonce: message.nonce,
                                            frame: sample.isValid ? sample : .inactive)
            if channel?.send(response) == true { self.framesSent += 1 }
        }
        channel.onClose = { [weak self, weak channel] reason in
            guard let self, self.generation == session, self.channel === channel else { return }
            self.stop()
            self.status = reason
        }
        channel.start()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.generation == session,
                  !self.isConnected else { return }
            self.stop()
            self.status = "Pairing timed out. Check the TV code and same-network connection."
        }
    }

    func stop() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        browser?.cancel(); browser = nil
        let old = channel; channel = nil; old?.close()
        services = []
        isBrowsing = false; isConnected = false
        connectedTV = nil
        previousRequestAt = 0
        framesSent = 0
        status = "TV sharing off"
    }
}
