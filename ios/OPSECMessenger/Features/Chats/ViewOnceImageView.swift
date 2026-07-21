import SwiftUI

/// WhatsApp-style "view once" media viewer:
///   • the image is rendered through SecureView (blank in screenshots),
///   • screen recording blanks it via ScreenGuard,
///   • dismissing the sheet deletes the local copy,
///   • if a screenshot IS taken, ScreenProtection notifies the sender.
struct ViewOnceImageView: View {
    let image: UIImage
    let conversationId: String
    let mediaId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if revealed {
                SecureView {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 48)).foregroundStyle(Theme.cyan)
                    Text("View once")
                        .font(.title2.bold()).foregroundStyle(.white)
                    Text("This photo will disappear after you view it. If you take a screenshot, the sender will be notified.")
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .font(.footnote)
                    Button("Tap and hold to view") { revealed = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 32)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundStyle(.white.opacity(0.8))
                            .padding()
                    }
                }
                Spacer()
                if revealed {
                    Text("Screenshotting notifies the sender.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 32)
                }
            }
        }
        .onAppear {
            ScreenProtection.shared.currentSecureContext =
                .init(conversationId: conversationId, mediaId: mediaId)
        }
        .onDisappear {
            ScreenProtection.shared.currentSecureContext = nil
        }
    }
}
