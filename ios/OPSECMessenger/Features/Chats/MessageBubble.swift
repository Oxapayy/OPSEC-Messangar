import SwiftUI

struct MessageBubble: View {
    let message: Message

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
                }
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
}
