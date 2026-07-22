import SwiftUI
import PhotosUI

struct ChatView: View {
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @StateObject private var db = LocalDatabase.shared
    @State private var draft = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var viewOnceMode = false
    @State private var confirmClear = false
    @State private var confirmBlock = false
    @State private var confirmRemove = false
    @StateObject private var recorder = VoiceRecorder()

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
                Button { CallManager.shared.startCall(conversation.peer) } label: {
                    Image(systemName: "phone.fill").foregroundStyle(Theme.cyan)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("Clear chat", systemImage: "trash")
                    }
                    Button { confirmRemove = true } label: {
                        Label("Remove friend", systemImage: "person.badge.minus")
                    }
                    Button(role: .destructive) { confirmBlock = true } label: {
                        Label("Block user", systemImage: "hand.raised")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.cyan)
                }
            }
        }
        .onAppear { db.markRead(conversation.id) }
        .alert("Delete this chat?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                db.clearConversation(conversation.id)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this chat from the database? This removes every message in it from this device.")
        }
        .alert("Remove @\(conversation.peer.username)?", isPresented: $confirmRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task {
                    try? await APIClient.shared.removeContact(numericId: conversation.peer.numericId)
                    await db.refreshContacts()
                }
            }
        } message: {
            Text("They'll be removed from your contacts. Your chat history stays until you clear it.")
        }
        .alert("Block @\(conversation.peer.username)?", isPresented: $confirmBlock) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                Task {
                    try? await APIClient.shared.blockUser(numericId: conversation.peer.numericId)
                    await db.refreshContacts()
                    dismiss()
                }
            }
        } message: {
            Text("You won't receive messages from them, and they're removed from your contacts. You can unblock later in Settings.")
        }
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

            if recorder.isRecording {
                recordingBar
            } else {
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

                    if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { recorder.start() } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 26)).foregroundStyle(Theme.cyan)
                        }
                    } else {
                        Button { sendText() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32)).foregroundStyle(Theme.cyan)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 6)
            }
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
                    conversationId: conversation.id,
                    recipientNumericId: conversation.peer.numericId,
                    ciphertext: ct, type: .text)
            }
        }
    }

    private var recordingBar: some View {
        HStack(spacing: 14) {
            Button { recorder.cancel() } label: {
                Image(systemName: "trash").font(.title3).foregroundStyle(.red)
            }
            Circle().fill(.red).frame(width: 10, height: 10)
                .opacity(0.9)
            Text(timeString(recorder.elapsed))
                .font(.body.monospacedDigit()).foregroundStyle(Theme.textPrimary)
            Text("Recording…").foregroundStyle(Theme.textSecondary).font(.footnote)
            Spacer()
            Button { stopAndSendVoice() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(Theme.cyan)
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
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
        uploadAndSend(bytes: data, type: type)
    }

    private func stopAndSendVoice() {
        guard let (data, duration) = recorder.stop(), let me = AppState.currentUserId else { return }
        let m = Message(id: UUID().uuidString,
                        conversationId: conversation.id,
                        senderId: me, type: .voice, text: nil, imageData: nil,
                        sentAt: Date(), isOutgoing: true,
                        audioData: data, audioDuration: duration)
        db.append(message: m)
        uploadAndSend(bytes: data, type: .voice)
    }

    /// Encrypts media bytes with the conversation key, uploads them as an
    /// attachment, then sends a message whose payload is the file id.
    private func uploadAndSend(bytes: Data, type: MessageType) {
        let convoId = conversation.id
        let recipient = conversation.peer.numericId
        Task {
            let key = KeyManager.placeholderConversationKey(for: convoId)
            guard let ct = try? KeyManager.encrypt(plaintext: bytes, sharedSecret: key),
                  let ticket = try? await APIClient.shared.requestAttachmentUpload(byteCount: ct.count)
            else { return }
            try? await APIClient.shared.uploadAttachment(fileId: ticket.fileId, data: ct)
            try? await APIClient.shared.sendAttachmentMessage(
                conversationId: convoId, recipientNumericId: recipient,
                fileId: ticket.fileId, type: type)
        }
    }
}

extension AppState {
    static var currentUserId: String? = nil
    static var myUsername: String? = nil
}
