import SwiftUI

/// Blue theme extracted from the OPSEC app icon: deep navy background,
/// cyan accent, steel-blue mid tones. Every view should pull colors from
/// here so a re-skin only touches one file.
enum Theme {
    // Base palette
    static let navyDeep   = Color(red: 0.031, green: 0.078, blue: 0.153) // #08142A
    static let navy       = Color(red: 0.051, green: 0.106, blue: 0.192) // #0D1B31
    static let navyRaised = Color(red: 0.075, green: 0.153, blue: 0.259) // #132742
    static let steel      = Color(red: 0.231, green: 0.482, blue: 0.749) // #3B7BBF
    static let cyan       = Color(red: 0.133, green: 0.831, blue: 1.000) // #22D4FF
    static let cyanSoft   = Color(red: 0.400, green: 0.898, blue: 1.000) // #66E5FF

    // Semantic
    static let background       = navyDeep
    static let surface          = navy
    static let surfaceElevated  = navyRaised
    static let accent           = cyan
    static let onAccent         = navyDeep
    static let textPrimary      = Color.white
    static let textSecondary    = Color.white.opacity(0.65)
    static let divider          = Color.white.opacity(0.08)

    // Gradients
    static let backgroundGradient = LinearGradient(
        colors: [navyDeep, navy, Color(red: 0.02, green: 0.14, blue: 0.28)],
        startPoint: .top, endPoint: .bottom)

    static let accentGradient = LinearGradient(
        colors: [cyan, steel],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let bubbleOutgoing = LinearGradient(
        colors: [cyan.opacity(0.95), steel.opacity(0.95)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Reusable styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.accentGradient, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: Theme.cyan.opacity(0.35), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.cyan.opacity(0.5), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// View modifier: paints the animated navy background behind a screen.
struct ThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func themedBackground() -> some View { modifier(ThemedBackground()) }
}

/// Small brand mark used across screens.
struct BrandLogo: View {
    var size: CGFloat = 96
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: Theme.cyan.opacity(0.4), radius: 16, y: 6)
    }
}
