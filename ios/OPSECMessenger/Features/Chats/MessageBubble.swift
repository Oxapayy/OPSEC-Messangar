import SwiftUI

struct MessageBubble: View {
    let message: Message
    let conversationId: String
    @State private var showViewOnce = false
    @StateObject private var db = LocalDatabase.shared
    @StateObject private var player = VoicePlayer()

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 40) }
            bubble
            if !message.isOutgoing { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch message.type {
            case .text:
                Text(message.text ?? "")
            case .image:
                if let data = message.imageData, let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable().scaledToFit()
                        .frame(maxWidth: 220)
                        .cornerRadius(10)
                } else {
                    mediaPlaceholder("Photo")
                }
            case .voice:
                voiceRow
            case .viewOnceImage:
                viewOnceRow
            case .callInvite:
                Label("Call", systemImage: "phone.fill")
            case .systemNotice:
                Text(message.text ?? "").font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(message.sentAt, style: .time)
                .font(.caption2)
                .foregroundStyle(message.isOutgoing
                                 ? Theme.onAccent.opacity(0.75)
                                 : Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background {
            if message.isOutgoing {
                RoundedRectangle(cornerRadius: 16).fill(Theme.bubbleOutgoing)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Theme.surfaceElevated)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.divider, lineWidth: 1))
            }
        }
        .foregroundStyle(message.isOutgoing ? Theme.onAccent : Theme.textPrimary)
    }

    @ViewBuilder private var voiceRow: some View {
        if let audio = message.audioData {
            Button { player.toggle(audio) } label: {
                HStack(spacing: 10) {
                    Image(systemName: player.playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                    Image(systemName: "waveform")
                    Text(durationText(message.audioDuration))
                        .font(.caption.monospacedDigit())
                }
            }
        } else {
            mediaPlaceholder("Voice message")
        }
    }

    private func mediaPlaceholder(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading \(label.lowercased())…").font(.footnote)
        }
        .foregroundStyle(message.isOutgoing ? Theme.onAccent.opacity(0.85) : Theme.textSecondary)
    }

    private func durationText(_ t: Double) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }

    @ViewBuilder private var viewOnceRow: some View {
        if message.consumed {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash.fill")
                Text("Opened").italic()
            }
            .foregroundStyle(message.isOutgoing
                             ? Theme.onAccent.opacity(0.85)
                             : Theme.textSecondary)
        } else {
            Button {
                showViewOnce = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eye.circle.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View once photo").font(.subheadline.weight(.semibold))
                        Text(message.isOutgoing ? "Waiting to be viewed"
                                                : "Tap to view — disappears after")
                            .font(.caption2).opacity(0.85)
                    }
                }
            }
            .disabled(message.isOutgoing)
            .fullScreenCover(isPresented: $showViewOnce, onDismiss: markConsumed) {
                if let data = message.imageData, let ui = UIImage(data: data) {
                    ViewOnceImageView(image: ui,
                                      conversationId: conversationId,
                                      mediaId: message.id)
                }
            }
        }
    }

    private func markConsumed() {
        Task { @MainActor in
            db.markConsumed(messageId: message.id, in: conversationId)
        }
    }
}
