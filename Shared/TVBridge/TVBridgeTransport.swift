import Foundation
import Combine
import Network
import CryptoKit
import Security

/// Bonjour discovery + TLS with a per-host, per-session pre-shared key.
/// Pairing code is shown on the TV, never advertised, uploaded or logged.
/// Based on Apple's Network.framework peer-to-peer TLS-PSK pattern.
enum TVBridgeSecurity {
    static let serviceType = "_skatefit._tcp"
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func newCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<10).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func normalized(_ code: String) -> String? {
        let clean = code.uppercased().filter { $0 != " " && $0 != "-" }
        guard clean.count == 10, clean.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return clean
    }

    static func parameters(code: String, serviceName: String) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let context = Data("SkateFitTV-v1/\(serviceName)".utf8)
        let auth = HMAC<SHA256>.authenticationCode(
            for: context, using: SymmetricKey(data: Data(code.utf8)))
        let keyData = Data(auth)
        let identityData = Data("SkateFitTV-v1".utf8)
        keyData.withUnsafeBytes { key in
            identityData.withUnsafeBytes { identity in
                sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions,
                    DispatchData(bytes: key) as __DispatchData,
                    DispatchData(bytes: identity) as __DispatchData)
            }
        }
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!)
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 2
        tcp.keepaliveInterval = 1
        tcp.keepaliveCount = 3
        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        return parameters
    }
}

/// A single encrypted channel. No unbounded send queue, reconnection loop,
/// plaintext fallback or trust-all certificate verifier.
@MainActor final class TVBridgeChannel {
    let connection: NWConnection
    var onReady: (() -> Void)?
    var onMessage: ((TVBridgeMessage) -> Void)?
    var onClose: ((String) -> Void)?
    private var parser = TVBridgeFraming()
    private var isClosed = false
    private var isReady = false
    private var sendPending = false

    init(_ connection: NWConnection) { self.connection = connection }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                switch state {
                case .ready:
                    self.isReady = true
                    self.onReady?()
                    self.receiveNext()
                case .failed, .cancelled:
                    self.close(reason: "Connection ended. Check the TV code and local network.")
                case .waiting:
                    self.close(reason: "Local network unavailable or permission denied.")
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    @discardableResult func send(_ message: TVBridgeMessage) -> Bool {
        guard isReady, !isClosed, !sendPending else { return false }
        do {
            let data = try TVBridgeFraming.encode(message)
            sendPending = true
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, !self.isClosed else { return }
                    self.sendPending = false
                    if error != nil { self.close(reason: "Local link send failed.") }
                }
            })
            return true
        } catch {
            close(reason: "Invalid bridge message.")
            return false
        }
    }

    private func receiveNext() {
        guard !isClosed else { return }
        connection.receive(minimumIncompleteLength: 1,
                           maximumLength: TVBridgeFraming.maximumBodyBytes) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self, !self.isClosed else { return }
                if let data, !data.isEmpty {
                    do {
                        for message in try self.parser.ingest(data) {
                            guard !self.isClosed else { return }
                            self.onMessage?(message)
                        }
                    } catch { self.close(reason: "Invalid or incompatible bridge data."); return }
                }
                if complete || error != nil { self.close(reason: "iPhone/TV link disconnected.") }
                else { self.receiveNext() }
            }
        }
    }

    func close(reason: String = "Disconnected") {
        guard !isClosed else { return }
        isClosed = true
        isReady = false
        connection.stateUpdateHandler = nil
        connection.cancel()
        let callback = onClose
        onReady = nil; onMessage = nil; onClose = nil
        callback?(reason)
    }
}

/// Listener is created only after the TV's Pair iPhone button is selected.
/// Only one authenticated phone per session; code expires after two minutes
/// without a pair. Five failed attempts require a new on-screen code.
@MainActor final class TVBoardReceiver: ObservableObject {
    @Published private(set) var status = "Choose Pair iPhone to begin"
    @Published private(set) var pairingCode = ""
    @Published private(set) var serviceName = ""
    @Published private(set) var isHosting = false
    @Published private(set) var isPaired = false
    @Published private(set) var frame: TVBoardFrame?
    @Published private(set) var roundTripMilliseconds: Double?

    private var listener: NWListener?
    private var channel: TVBridgeChannel?
    private var timer: Timer?
    private var gate = TVFrameGate()
    private var generation = UUID()
    private var openedAt = 0.0
    private var candidateAt: Double?
    private var failedAttempts = 0

    func startHosting() {
        stop()
        generation = UUID()
        let session = generation
        serviceName = "SkateFit TV " + String(session.uuidString.prefix(6))
        pairingCode = TVBridgeSecurity.newCode()
        openedAt = ProcessInfo.processInfo.systemUptime
        failedAttempts = 0
        do {
            let listener = try NWListener(using: TVBridgeSecurity.parameters(
                code: pairingCode, serviceName: serviceName))
            self.listener = listener
            listener.service = NWListener.Service(name: serviceName,
                type: TVBridgeSecurity.serviceType, domain: "local.")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session else { return }
                    if case .failed = state {
                        self.stop()
                        self.status = "Local network unavailable. Check local-network permission."
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == session, self.isHosting,
                          self.channel == nil, !self.isPaired else { connection.cancel(); return }
                    let channel = TVBridgeChannel(connection)
                    self.channel = channel
                    self.candidateAt = ProcessInfo.processInfo.systemUptime
                    channel.onReady = { [weak self, weak channel] in
                        guard let self, self.generation == session,
                              self.channel === channel else { return }
                        self.isPaired = true
                        self.gate.reset()
                        self.status = "iPhone paired. Start and calibrate its board sensor."
                    }
                    channel.onMessage = { [weak self, weak channel] message in
                        guard let self, self.generation == session,
                              self.channel === channel, self.isPaired else { return }
                        guard message.kind == .response,
                              message.version == TVBridgeMessage.version else {
                            channel?.close(reason: "Incompatible SkateFit bridge version."); return
                        }
                        _ = self.gate.consume(message, now: ProcessInfo.processInfo.systemUptime)
                    }
                    channel.onClose = { [weak self, weak channel] reason in
                        guard let self, self.generation == session,
                              self.channel === channel else { return }
                        let wasPaired = self.isPaired
                        self.channel = nil
                        self.frame = nil
                        self.isPaired = false
                        self.gate.reset()
                        self.failedAttempts += 1
                        if wasPaired {
                            self.stop()
                            self.status = "iPhone disconnected. Pair again to resume safely."
                        } else { self.status = reason }
                    }
                    channel.start()
                }
            }
            isHosting = true
            status = "On your iPhone: Connect Apple TV, select this TV, enter this code."
            listener.start(queue: .main)
            let clock = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.tick() }
            }
            timer = clock
            RunLoop.main.add(clock, forMode: .common)
        } catch {
            stop()
            status = "Could not start local TV pairing."
        }
    }

    private func tick() {
        guard isHosting else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if !isPaired && (now - openedAt > 120 || failedAttempts >= 5) {
            stop()
            status = "Pairing expired. Select Pair iPhone for a new code."
            return
        }
        if let candidateAt, !isPaired, now - candidateAt > 8 {
            channel?.close(reason: "Pairing timed out. Check the code.")
        }
        guard isPaired else { return }
        let next = gate.freshFrame(now: now)
        if frame != next { frame = next }
        roundTripMilliseconds = gate.roundTripSeconds.map { $0 * 1000 }
        status = next == nil ? "Paired, but no fresh calibrated board motion" : "Live board via iPhone"
        if let request = gate.request(now: now) { _ = channel?.send(request) }
    }

    func stop() {
        generation = UUID() // invalidate callbacks from old listener/session
        timer?.invalidate(); timer = nil
        listener?.cancel(); listener = nil
        let old = channel; channel = nil; old?.close()
        gate.reset()
        frame = nil
        roundTripMilliseconds = nil
        candidateAt = nil
        isPaired = false; isHosting = false
        pairingCode = ""; serviceName = ""
        status = "Disconnected"
    }
}
