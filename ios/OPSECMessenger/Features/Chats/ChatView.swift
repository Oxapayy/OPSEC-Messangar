import SwiftUI
import PhotosUI

struct ChatView: View {
    let conversation: Conversation
    @StateObject private var db = LocalDatabase.shared
    @State private var draft = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var viewOnceMode = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(db.messages[conversation.id] ?? []) { m in
                                MessageBubble(message: m, conversationId: conversation.id)
                                    .id(m.id)
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
        VStack(spacing: 6) {
            if viewOnceMode {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                    Text("View once — the next photo you send disappears after viewing.")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(Theme.cyan)
                .padding(.horizontal, 12)
            }

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

                Button {
                    viewOnceMode.toggle()
                } label: {
                    Image(systemName: viewOnceMode ? "eye.fill" : "eye.slash")
                        .font(.title3)
                        .foregroundStyle(viewOnceMode ? Theme.cyan : Theme.textSecondary)
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
            .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 6)
        }
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
            if let ct = try? KeyManager.encrypt(plaintext: Data(text.utf8),
                                                sharedSecret: key) {
                try? await APIClient.shared.sendMessage(
                    conversationId: conversation.id, ciphertext: ct, type: .text)
            }
        }
    }

    private func sendImage(_ data: Data) {
        guard let me = AppState.currentUserId else { return }
        let type: MessageType = viewOnceMode ? .viewOnceImage : .image
        let m = Message(id: UUID().uuidString,
                        conversationId: conversation.id,
                        senderId: me, type: type, text: nil, imageData: data,
                        sentAt: Date(), isOutgoing: true)
        db.append(message: m)
        viewOnceMode = false
        Task {
            _ = try? await APIClient.shared.requestAttachmentUpload(byteCount: data.count)
            // TODO(backend): upload + send envelope with the fileId.
        }
    }
}

extension AppState { static var currentUserId: String? = nil }
