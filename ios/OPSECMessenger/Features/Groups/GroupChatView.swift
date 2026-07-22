import SwiftUI
import PhotosUI

struct GroupChatView: View {
    let group: GroupInfo
    @EnvironmentObject var appState: AppState
    @StateObject private var db = LocalDatabase.shared
    @State private var draft = ""
    @State private var pickerItem: PhotosPickerItem?
    @StateObject private var recorder = VoiceRecorder()

    /// Live group snapshot (members/roles can change under us).
    private var live: GroupInfo { db.group(group.id) ?? group }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(db.messages[group.id] ?? []) { m in
                                VStack(alignment: m.isOutgoing ? .trailing : .leading, spacing: 1) {
                                    if !m.isOutgoing {
                                        Text(senderName(m.senderId))
                                            .font(.caption2).foregroundStyle(Theme.cyan)
                                            .padding(.leading, 12)
                                    }
                                    MessageBubble(message: m, conversationId: group.id)
                                }
                                .id(m.id)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                    .onChange(of: db.messages[group.id]?.count ?? 0) { _, _ in
                        if let last = db.messages[group.id]?.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                composer
            }
        }
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { GroupMembersView(group: group) } label: {
                    Image(systemName: "person.3.fill").foregroundStyle(Theme.cyan)
                }
            }
        }
    }

    private func senderName(_ numericString: String) -> String {
        if let n = UInt64(numericString),
           let m = live.members.first(where: { $0.numericId == n }) {
            return "@" + m.username
        }
        return "@user"
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if recorder.isRecording {
                HStack(spacing: 14) {
                    Button { recorder.cancel() } label: {
                        Image(systemName: "trash").font(.title3).foregroundStyle(.red)
                    }
                    Circle().fill(.red).frame(width: 10, height: 10)
                    Text(timeString(recorder.elapsed))
                        .font(.body.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button { stopAndSendVoice() } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32)).foregroundStyle(Theme.cyan)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
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
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.divider, lineWidth: 1))
                    if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { recorder.start() } label: {
                            Image(systemName: "mic.fill").font(.system(size: 26)).foregroundStyle(Theme.cyan)
                        }
                    } else {
                        Button { sendText() } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(Theme.cyan)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 6)
            }
        }
        .background(Theme.surface.opacity(0.9))
        .overlay(Rectangle().fill(Theme.divider).frame(height: 0.5), alignment: .top)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func sendText() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let me = AppState.currentUserId else { return }
        draft = ""
        db.append(message: Message(id: UUID().uuidString, conversationId: group.id,
                                   senderId: me, type: .text, text: text, imageData: nil,
                                   sentAt: Date(), isOutgoing: true))
        Task {
            let key = KeyManager.placeholderConversationKey(for: group.id)
            if let ct = try? KeyManager.encrypt(plaintext: Data(text.utf8), sharedSecret: key) {
                try? await APIClient.shared.sendGroupMessage(group.id, ciphertext: ct, type: .text)
            }
        }
    }

    private func sendImage(_ data: Data) {
        guard let me = AppState.currentUserId else { return }
        db.append(message: Message(id: UUID().uuidString, conversationId: group.id,
                                   senderId: me, type: .image, text: nil, imageData: data,
                                   sentAt: Date(), isOutgoing: true))
        uploadAndSend(bytes: data, type: .image)
    }

    private func stopAndSendVoice() {
        guard let (data, duration) = recorder.stop(), let me = AppState.currentUserId else { return }
        db.append(message: Message(id: UUID().uuidString, conversationId: group.id,
                                   senderId: me, type: .voice, text: nil, imageData: nil,
                                   sentAt: Date(), isOutgoing: true,
                                   audioData: data, audioDuration: duration))
        uploadAndSend(bytes: data, type: .voice)
    }

    private func uploadAndSend(bytes: Data, type: MessageType) {
        let gid = group.id
        Task {
            let key = KeyManager.placeholderConversationKey(for: gid)
            guard let ct = try? KeyManager.encrypt(plaintext: bytes, sharedSecret: key),
                  let ticket = try? await APIClient.shared.requestAttachmentUpload(byteCount: ct.count)
            else { return }
            try? await APIClient.shared.uploadAttachment(fileId: ticket.fileId, data: ct)
            try? await APIClient.shared.sendGroupAttachment(gid, fileId: ticket.fileId, type: type)
        }
    }
}
