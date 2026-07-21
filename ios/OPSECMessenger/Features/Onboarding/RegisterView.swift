import SwiftUI
import UIKit

struct RegisterView: View {
    let code: String
    let numericId: UInt64
    let onSaved: () -> Void

    @State private var acknowledged = false
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            BrandLogo(size: 40)
                            Text("Save your 64-character code")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.top, 4)

                        Text("This code is your account. It's the ONLY way to sign back in — there is no password reset. Store it in a password manager before continuing.")
                            .foregroundStyle(Theme.textSecondary)
                            .font(.footnote)

                        codeCard

                        HStack {
                            Text("Account number")
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(String(numericId))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .font(.footnote)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }

                VStack(spacing: 12) {
                    Toggle(isOn: $acknowledged) {
                        Text("I have saved this code somewhere safe.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.cyan)

                    Button("Continue", action: onSaved)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!acknowledged)
                        .opacity(acknowledged ? 1 : 0.5)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Your recovery code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.cyanSoft)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Theme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())

                ShareLink(item: code) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
