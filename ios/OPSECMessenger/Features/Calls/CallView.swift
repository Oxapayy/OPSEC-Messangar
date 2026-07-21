import SwiftUI

struct CallView: View {
    let peer: UserProfile
    enum CallPhase { case ringing, connected, ended }
    @State private var phase: CallPhase = .ringing
    @State private var elapsed: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Circle().fill(Theme.accentGradient)
                    .frame(width: 140, height: 140)
                    .overlay(
                        Text(String(peer.username.prefix(1)).uppercased())
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(Theme.onAccent))
                    .shadow(color: Theme.cyan.opacity(0.5), radius: 24, y: 8)
                Text("@" + peer.username)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle).foregroundStyle(Theme.textSecondary)
                Spacer()

                HStack(spacing: 32) {
                    callButton(system: "phone.down.fill", color: .red) {
                        phase = .ended; dismiss()
                    }
                    if phase == .ringing {
                        callButton(system: "phone.fill", color: .green) {
                            phase = .connected
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onReceive(timer) { _ in if phase == .connected { elapsed += 1 } }
    }

    private func callButton(system: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.title)
                .foregroundStyle(.white)
                .padding(22)
                .background(Circle().fill(color))
                .shadow(color: color.opacity(0.5), radius: 12, y: 4)
        }
    }

    private var subtitle: String {
        switch phase {
        case .ringing:   return "Ringing…"
        case .connected: return format(elapsed)
        case .ended:     return "Call ended"
        }
    }
    private func format(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d", s/60, s%60)
    }
}
