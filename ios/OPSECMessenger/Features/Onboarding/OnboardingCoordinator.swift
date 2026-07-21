import SwiftUI

struct OnboardingCoordinator: View {
    enum Step: Hashable { case welcome, register, savedCode, chooseUsername, login }

    @State private var path: [Step] = []
    @State private var generatedCode: String = ""
    @State private var generatedNumericId: UInt64 = 0

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onRegister: {
                    generatedCode = AccountCodeGenerator.generate()
                    generatedNumericId = AccountCodeGenerator.generateNumericId()
                    path.append(.register)
                },
                onLogin: { path.append(.login) }
            )
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .welcome: WelcomeView(onRegister: {}, onLogin: {})
                case .register:
                    RegisterView(code: generatedCode,
                                 numericId: generatedNumericId,
                                 onSaved: { path.append(.chooseUsername) })
                case .savedCode, .chooseUsername:
                    UsernameView(code: generatedCode,
                                 numericId: generatedNumericId)
                case .login:
                    LoginView()
                }
            }
        }
    }
}
