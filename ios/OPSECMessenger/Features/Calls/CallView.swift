import SwiftUI

/// App-wide call surface. Shows nothing when idle; otherwise a full-screen
/// ringing / incoming / connected UI driven by CallManager. Rendered at the
/// app root so a call appears over any tab.
struct CallOverlay: View {
    @StateObject private var call = CallManager.shared
    @State private var elapsed = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if case .idle = call.state {
                EmptyView()
            } else {
                activeCall
            }
        }
    }

    @ViewBuilder private var activeCall: some View {
        let peer = call.state.peer
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Circle().fill(Theme.accentGradient)
                    .frame(width: 140, height: 140)
                    .overlay(Text(String((peer?.username ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 48, weight: .bold)).foregroundStyle(Theme.onAccent))
                    .shadow(color: Theme.cyan.opacity(0.5), radius: 24, y: 8)
                Text("@" + (peer?.username ?? ""))
                    .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                Text(subtitle).foregroundStyle(Theme.textSecondary)
                Spacer()
                controls
                    .padding(.bottom, 44)
            }
        }
        .onReceive(timer) { _ in
            if case .connected = call.state { elapsed += 1 } else { elapsed = 0 }
        }
    }

    @ViewBuilder private var controls: some View {
        switch call.state {
        case .incoming:
            HStack(spacing: 48) {
                circleButton("phone.down.fill", .red) { call.reject() }
                circleButton("phone.fill", .green) { call.accept() }
            }
        case .outgoing:
            circleButton("phone.down.fill", .red) { call.hangUp() }
        case .connected:
            HStack(spacing: 40) {
                circleButton(call.muted ? "mic.slash.fill" : "mic.fill",
                             call.muted ? .gray : Theme.cyan) { call.toggleMute() }
                circleButton("phone.down.fill", .red) { call.hangUp() }
            }
        case .idle:
            EmptyView()
        }
    }

    private func circleButton(_ system: String, _ color: Color,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.title)
                .foregroundStyle(.white).padding(22)
                .background(Circle().fill(color))
                .shadow(color: color.opacity(0.5), radius: 12, y: 4)
        }
    }

    private var subtitle: String {
        switch call.state {
        case .incoming:  return "Incoming call…"
        case .outgoing:  return "Calling…"
        case .connected: return format(elapsed)
        case .idle:      return ""
        }
    }

    private func format(_ t: Int) -> String { String(format: "%02d:%02d", t / 60, t % 60) }
}
