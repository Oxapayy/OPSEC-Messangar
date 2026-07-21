import SwiftUI

/// Full-screen privacy overlays: blurs on backgrounding, blacks out during
/// screen recording, flashes a banner when a screenshot is detected.
struct ScreenGuardModifier: ViewModifier {
    @StateObject private var guardState = ScreenProtection.shared
    @State private var showScreenshotBanner = false

    func body(content: Content) -> some View {
        ZStack {
            content

            // Blur behind the app-switcher screenshot.
            if guardState.isObscured {
                privacyCurtain
                    .transition(.opacity)
            }

            // Black out during screen recording / mirroring.
            if guardState.isCapturing {
                recordingCurtain
                    .transition(.opacity)
            }

            // Fleeting banner when a screenshot has just been taken.
            if showScreenshotBanner {
                VStack {
                    ScreenshotBanner()
                        .padding(.top, 44)
                    Spacer()
                }.transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: guardState.isObscured)
        .animation(.easeInOut(duration: 0.2), value: guardState.isCapturing)
        .animation(.spring(response: 0.35), value: showScreenshotBanner)
        .onChange(of: guardState.lastScreenshotAt) { _, _ in
            showScreenshotBanner = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                showScreenshotBanner = false
            }
        }
    }

    private var privacyCurtain: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 12) {
                BrandLogo(size: 96)
                Text("OPSEC")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .tracking(6)
            }
        }
    }

    private var recordingCurtain: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "record.circle").font(.system(size: 48))
                    .foregroundStyle(.red)
                Text("Screen recording detected")
                    .font(.headline).foregroundStyle(.white)
                Text("Content is hidden while your screen is being recorded.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

struct ScreenshotBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.viewfinder").foregroundStyle(Theme.onAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot detected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                Text("The sender has been notified.")
                    .font(.caption).foregroundStyle(Theme.onAccent.opacity(0.85))
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: Theme.cyan.opacity(0.4), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

extension View {
    /// Apply once at the app root.
    func screenGuard() -> some View { modifier(ScreenGuardModifier()) }
}
