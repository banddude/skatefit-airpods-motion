import SwiftUI

struct TVLinkView: View {
    @ObservedObject var store: MotionStore
    @ObservedObject private var sender: TVBoardSender
    @State private var selectedID = ""
    @State private var code = ""

    init(store: MotionStore) {
        self.store = store
        self.sender = store.tvSender
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("SKATEFIT ON APPLE TV", systemImage: "appletv.fill")
                    .font(.title2.weight(.black))
                Text("Your iPhone receives the board AirPod. Apple TV runs the game and shows your balance. No camera or internet service is involved in this link.")
                    .font(.subheadline)
                Text("1. Open SkateFit on Apple TV and select Pair iPhone.\n2. Keep both devices on the same local network.\n3. Find the TV here and enter its code.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Label(sender.status, systemImage: sender.isConnected ? "checkmark.shield.fill" : "network")
                    .foregroundStyle(sender.isConnected ? Color.green : Color.secondary)
                    .font(.subheadline.weight(.semibold))
                if sender.isConnected {
                    Text(sender.connectedTV ?? "Apple TV")
                        .font(.headline)
                    Label(store.gameMotionReady ? "Board motion is ready to send" : "Start recording and calibrate in Motion Lab",
                          systemImage: store.gameMotionReady ? "airpodspro" : "scope")
                    Text("\(sender.framesSent) responses sent over the encrypted local link")
                        .font(.caption.monospacedDigit())
                    Text("Keep SkateFit open on this iPhone. You may return to calibration or manual practice without disconnecting. Locking the phone or switching apps ends TV sharing and pauses board-controlled play.")
                        .font(.caption)
                    Button("Disconnect Apple TV", role: .destructive) { sender.stop() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("disconnectTV")
                } else {
                    Button {
                        code = ""
                        sender.browse()
                    } label: {
                        Label("Find Apple TV", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .accessibilityIdentifier("findAppleTV")

                    ForEach(sender.services) { service in
                        Button {
                            selectedID = service.id
                        } label: {
                            HStack {
                                Image(systemName: "appletv")
                                Text(service.name)
                                Spacer()
                                if selectedID == service.id { Image(systemName: "checkmark") }
                            }
                            .frame(minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let service = sender.services.first(where: { $0.id == selectedID }) {
                        TextField("10-character code from the TV", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                            .privacySensitive()
                            .accessibilityIdentifier("tvPairCode")
                        Button("Connect & Share Board Motion") {
                            sender.connect(to: service, code: code)
                            code = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .disabled(TVBridgeSecurity.normalized(code) == nil)
                    }
                    if sender.isBrowsing {
                        Button("Stop searching") { sender.stop() }
                            .buttonStyle(.bordered)
                    }
                }
                Divider()
                Text("Only calibrated board pose and current practice statistics are shared with the paired TV. Pairing is encrypted and session-only. No GPS, contacts, microphone, camera, or cloud uploads are added. Existing raw sensor recordings and practice history stay on this iPhone; TV game progress is separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Apple TV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
