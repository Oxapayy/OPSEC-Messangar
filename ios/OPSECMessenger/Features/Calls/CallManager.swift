import Foundation
import AVFoundation

/// Drives 1:1 voice calls over the Tor WebSocket: ring / accept / reject /
/// end signalling, plus a best-effort streamed-audio channel.
///
/// NOTE ON TOR: Tor only carries TCP and adds latency, so audio here is a
/// PCM-over-WebSocket relay — it works, but with walkie-talkie-style delay,
/// not instant full-duplex. Real-time (UDP/WebRTC) audio can't run over Tor.
@MainActor
final class CallManager: ObservableObject {
    static let shared = CallManager()

    enum State: Equatable {
        case idle
        case outgoing(UserProfile)
        case incoming(UserProfile)
        case connected(UserProfile)

        var peer: UserProfile? {
            switch self {
            case .idle: return nil
            case .outgoing(let p), .incoming(let p), .connected(let p): return p
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var muted = false

    private var peerNumericId: UInt64?
    private let audio = AudioCallEngine()

    private var myId: UInt64 { UInt64(AppState.currentUserId ?? "") ?? 0 }

    private init() {}

    /// Wire up the socket + audio callbacks. Call once after the socket connects.
    func attach() async {
        await WebSocketClient.shared.addCallHandler { [weak self] frame in
            guard let kind = frame["kind"] as? String, kind.hasPrefix("call") else { return }
            Task { @MainActor in self?.handle(frame) }
        }
        audio.onCapturedChunk = { [weak self] data in
            Task { @MainActor in await self?.sendAudio(data) }
        }
    }

    // MARK: - Local actions

    func startCall(_ peer: UserProfile) {
        guard case .idle = state else { return }
        peerNumericId = peer.numericId
        state = .outgoing(peer)
        Task { await frame("callOffer", peer: peer.numericId,
                           extra: ["from_username": AppState.myUsername ?? ""]) }
    }

    func accept() {
        guard case .incoming(let peer) = state else { return }
        state = .connected(peer)
        audio.start()
        Task { await frame("callAccept", peer: peer.numericId) }
    }

    func reject() {
        if case .incoming(let peer) = state {
            Task { await frame("callReject", peer: peer.numericId) }
        }
        teardown()
    }

    func hangUp() {
        if let p = peerNumericId {
            Task { await frame("callEnd", peer: p) }
        }
        teardown()
    }

    func toggleMute() {
        muted.toggle()
        audio.setMuted(muted)
    }

    private func teardown() {
        audio.stop()
        peerNumericId = nil
        muted = false
        state = .idle
    }

    // MARK: - Incoming frames

    private func handle(_ f: [String: Any]) {
        guard let kind = f["kind"] as? String,
              let p = f["payload"] as? [String: Any] else { return }
        let fromStr = (p["from"] as? String) ?? ""
        let from = UInt64(fromStr) ?? 0

        switch kind {
        case "callOffer":
            guard case .idle = state else {
                Task { await frame("callReject", peer: from) }   // busy
                return
            }
            let name = (p["from_username"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "user"
            let peer = UserProfile(id: fromStr, username: name, numericId: from, publicKey: nil)
            peerNumericId = from
            state = .incoming(peer)
        case "callAccept":
            if case .outgoing(let peer) = state {
                state = .connected(peer)
                audio.start()
            }
        case "callReject", "callEnd":
            teardown()
        case "callAudio":
            if let b64 = p["data"] as? String, let d = Data(base64Encoded: b64) {
                audio.playChunk(d)
            }
        default:
            break
        }
    }

    private func sendAudio(_ data: Data) async {
        guard case .connected = state, let p = peerNumericId else { return }
        await frame("callAudio", peer: p, extra: ["data": data.base64EncodedString()])
    }

    private func frame(_ kind: String, peer: UInt64, extra: [String: Any] = [:]) async {
        var payload: [String: Any] = ["peer_id": String(peer), "from": String(myId)]
        payload.merge(extra) { a, _ in a }
        await WebSocketClient.shared.sendRaw(kind: kind, payload: payload)
    }
}

/// AVAudioEngine capture + playback with realtime resampling to 16 kHz mono
/// Int16. Everything is guarded — on any failure the call stays up, silent,
/// rather than crashing.
final class AudioCallEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                           sampleRate: 16_000, channels: 1,
                                           interleaved: true)!
    private var converter: AVAudioConverter?
    private var running = false
    private var muted = false

    var onCapturedChunk: ((Data) -> Void)?

    func setMuted(_ m: Bool) { muted = m }

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true, options: [])

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: wireFormat)

            let input = engine.inputNode
            let inFmt = input.outputFormat(forBus: 0)
            converter = AVAudioConverter(from: inFmt, to: wireFormat)

            input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buffer, _ in
                self?.capture(buffer)
            }
            engine.prepare()
            try engine.start()
            player.play()
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        engine.reset()
        converter = nil
        running = false
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func capture(_ buffer: AVAudioPCMBuffer) {
        guard !muted, let converter, let onCapturedChunk else { return }
        let ratio = wireFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
        guard let out = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return }
        let data = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
        onCapturedChunk(data)
    }

    func playChunk(_ data: Data) {
        guard running, data.count >= 2 else { return }
        let frames = AVAudioFrameCount(data.count / 2)
        guard let buf = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: frames) else { return }
        buf.frameLength = frames
        if let ch = buf.int16ChannelData {
            data.withUnsafeBytes { raw in
                if let base = raw.baseAddress { memcpy(ch[0], base, data.count) }
            }
        }
        player.scheduleBuffer(buf, completionHandler: nil)
    }
}
