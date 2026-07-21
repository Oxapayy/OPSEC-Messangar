import SwiftUI
import UIKit
import Combine

/// Central hub for screen-privacy signals. iOS cannot *prevent* a screenshot,
/// but we can:
///   • detect one (UIApplication.userDidTakeScreenshotNotification),
///   • detect an active screen recording (UIScreen.capturedDidChangeNotification),
///   • blur the UI when the app resigns active (app switcher),
///   • render sensitive media through a secure layer (see SecureView.swift).
@MainActor
final class ScreenProtection: ObservableObject {
    static let shared = ScreenProtection()

    /// A screenshot was just taken.
    @Published private(set) var lastScreenshotAt: Date?
    /// True while the screen is being recorded or mirrored.
    @Published private(set) var isCapturing: Bool = false
    /// True while the app is not the foreground scene (blur trigger).
    @Published private(set) var isObscured: Bool = false

    /// Registered per-conversation callback. `senderId` for the media whose
    /// view is currently on-screen so we can tell the backend who to warn.
    var currentSecureContext: SecureContext?

    struct SecureContext {
        let conversationId: String
        let mediaId: String?
    }

    private var bag = Set<AnyCancellable>()

    private init() {
        let nc = NotificationCenter.default
        nc.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .sink { [weak self] _ in self?.handleScreenshot() }.store(in: &bag)
        nc.publisher(for: UIScreen.capturedDidChangeNotification)
            .sink { [weak self] _ in self?.refreshCaptureState() }.store(in: &bag)
        nc.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.isObscured = true }.store(in: &bag)
        nc.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.isObscured = false }.store(in: &bag)
        refreshCaptureState()
    }

    private func handleScreenshot() {
        lastScreenshotAt = Date()
        guard let ctx = currentSecureContext else { return }
        // Fire-and-forget notification to the other party.
        Task {
            try? await APIClient.shared.reportScreenshot(
                conversationId: ctx.conversationId, mediaId: ctx.mediaId)
            NotificationManager.shared.deliverLocal(
                title: "Screenshot detected",
                body: "The other party has been notified.")
        }
    }

    private func refreshCaptureState() {
        isCapturing = UIScreen.screens.contains { $0.isCaptured }
    }
}
