import SwiftUI
import PhotosUI

struct ChatView: View {
    let conversation: Conversation
    @StateObject private var db = LocalDatabase.shared
    @State private var draft = ""
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(db.messages[conversation.id] ?? []) { m in
                                MessageBubble(message: m).id(m.id)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .onChange(of: db.messages[conversation.id]?.count ?? 0) { _, _ in
                        if let last = db.messages[conversation.id]?.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                composer
            }
        }
        .navigationTitle("@" + conversation.peer.username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { CallView(peer: conversation.peer) } label: {
                    Image(systemName: "phone.fill").foregroundStyle(Theme.cyan)
                }
            }
        }
        .onAppear { db.markRead(conversation.id) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo").font(.title2).foregroundStyle(Theme.cyan)
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        sendImage(data)
                    }
                }
            }

            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.divider, lineWidth: 1))

            Button {
                sendText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.cyan)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface.opacity(0.9))
        .overlay(Rectangle().fill(Theme.divider).frame(height: 0.5), alignment: .top)
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let me = AppState.currentUserId else { return }
        draft = ""
        let m = Message(id: UUID().uuidString,
                        conversationId: conversation.id,
                        senderId: me, type: .text, text: text, imageData: nil,
                        sentAt: Date(), isOutgoing: true)
        db.append(message: m)
        Task {
            let key = KeyManager.placeholderConversationKey(for: conversation.id)
            if let ct = try? KeyManager.encrypt(plaintext: Data(text.utf8), sharedSecret: key) {
                try? await APIClient.shared.sendMessage(
                    conversationId: conversation.id, ciphertext: ct, type: .text)
            }
        }
    }

    private func sendImage(_ data: Data) {
        guard let me = AppState.currentUserId else { return }
        let m = Message(id: UUID().uuidString,
                        conversationId: conversation.id,
                        senderId: me, type: .image, text: nil, imageData: data,
                        sentAt: Date(), isOutgoing: true)
        db.append(message: m)
        Task {
            _ = try? await APIClient.shared.requestAttachmentUpload(byteCount: data.count)
            // TODO(backend): upload to returned uploadUrl then broadcast.
        }
    }
}

extension AppState { static var currentUserId: String? = nil }
