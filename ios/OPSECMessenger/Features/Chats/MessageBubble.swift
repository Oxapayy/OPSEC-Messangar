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
                Text(message.text ?? "").font(.footnote).foregroundStyle(.secondary)
            }
            Text(message.sentAt, style: .time)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(message.isOutgoing
                    ? Color.accentColor.opacity(0.85)
                    : Color.secondary.opacity(0.2))
        .foregroundStyle(message.isOutgoing ? .white : .primary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
