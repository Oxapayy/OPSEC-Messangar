import SwiftUI

/// UI shell for an outgoing call. Real media/signalling is a TODO — this
/// screen currently just walks through the states so the flow is testable.
struct CallView: View {
    let peer: UserProfile

    enum State { case ringing, connected, ended }
    @State private var state: State = .ringing
    @State private var elapsed: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle().fill(Color.accentColor.opacity(0.25))
                .frame(width: 120, height: 120)
                .overlay(Text(String(peer.username.prefix(1)).uppercased()).font(.system(size: 44, weight: .bold)))
            Text("@" + peer.username).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
            Spacer()

            HStack(spacing: 32) {
                Button(role: .destructive) {
                    state = .ended
                    dismiss()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.title)
                        .padding()
                        .background(Circle().fill(Color.red))
                        .foregroundStyle(.white)
                }
                if state == .ringing {
                    Button {
                        state = .connected
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .padding()
                            .background(Circle().fill(Color.green))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
        .navigationBarBackButtonHidden(true)
        .onReceive(timer) { _ in if state == .connected { elapsed += 1 } }
        .task {
            // TODO(backend): request TURN creds, start WebRTC peer connection,
            // send SDP offer via APIClient.startCall + WebSocketClient.
        }
    }

    private var subtitle: String {
        switch state {
        case .ringing:   return "Ringing…"
        case .connected: return format(elapsed)
        case .ended:     return "Call ended"
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d", s/60, s%60)
    }
}
