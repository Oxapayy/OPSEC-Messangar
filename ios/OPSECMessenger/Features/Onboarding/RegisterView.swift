import SwiftUI
import UIKit

struct RegisterView: View {
    let code: String
    let numericId: UInt64
    let onSaved: () -> Void

    @State private var acknowledged = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Please save this 64-character code")
                    .font(.title2.weight(.bold))

                Text("This code is your account. It is the ONLY way to sign back in — there is no password reset. Write it down or store it in a password manager before continuing.")
                    .foregroundStyle(.secondary)

                codeCard

                HStack {
                    Text("Account number").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(numericId)).monospacedDigit()
                }
                .font(.footnote)
                .padding(.horizontal, 4)

                Toggle(isOn: $acknowledged) {
                    Text("I have saved this code somewhere safe.")
                        .font(.footnote)
                }
                .padding(.top, 8)

                Button {
                    onSaved()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!acknowledged)
            }
            .padding()
        }
        .navigationTitle("Your recovery code")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var codeCard: some View {
        VStack(spacing: 12) {
            Text(code)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15)))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                ShareLink(item: code) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
