import SwiftUI

/// Holds the freshly-generated recovery code + numeric id for the register
/// flow. Passing this down as an ObservableObject keeps the state alive
/// across navigation transitions so RegisterView / UsernameView always see
/// the same (non-empty) values, even on first paint.
@MainActor
final class RegistrationDraft: ObservableObject {
    @Published var code: String = ""
    @Published var numericId: UInt64 = 0

    func regenerate() {
        code = AccountCodeGenerator.generate()
        numericId = AccountCodeGenerator.generateNumericId()
    }
}

struct OnboardingCoordinator: View {
    enum Step: Hashable { case register, chooseUsername, login }

    @State private var path: [Step] = []
    @StateObject private var draft = RegistrationDraft()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onRegister: {
                    draft.regenerate()
                    path.append(.register)
                },
                onLogin: { path.append(.login) }
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .register:
                    RegisterView(code: draft.code,
                                 numericId: draft.numericId,
                                 onSaved: { path.append(.chooseUsername) })
                case .chooseUsername:
                    UsernameView(code: draft.code,
                                 numericId: draft.numericId)
                case .login:
                    LoginView()
                }
            }
        }
    }
}
