import Foundation
import AVFoundation

/// Records a short voice note to a temp .m4a file and hands back its bytes.
@MainActor
final class VoiceRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var url: URL?
    private var timer: Timer?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        session.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard granted, let self else { return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let dst = FileManager.default.temporaryDirectory
            .appendingPathComponent("vn-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let rec = try? AVAudioRecorder(url: dst, settings: settings) else { return }
        url = dst
        recorder = rec
        rec.record()
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
        }
    }

    /// Stops recording and returns (audioData, duration) if anything was captured.
    func stop() -> (Data, Double)? {
        timer?.invalidate(); timer = nil
        guard let rec = recorder, let url else { isRecording = false; return nil }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        try? FileManager.default.removeItem(at: url)
        return (data, duration)
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let url { try? FileManager.default.removeItem(at: url) }
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

/// Plays a voice note from in-memory bytes.
@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ data: Data) {
        if playing { stop(); return }
        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = try? AVAudioPlayer(data: data) else { return }
        p.delegate = self
        player = p
        p.play()
        playing = true
    }

    func stop() {
        player?.stop()
        player = nil
        playing = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}
