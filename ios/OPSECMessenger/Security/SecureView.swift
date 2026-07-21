import SwiftUI
import UIKit

/// Renders arbitrary SwiftUI content inside a `UITextField` marked
/// `isSecureTextEntry`. iOS blanks the secure layer of any secure text field
/// during screenshots, screen recordings, and AirPlay mirroring — so this
/// gives us the closest thing to "block screenshots" that exists on iOS.
///
/// Usage:
///     SecureView { Image(uiImage: viewOncePhoto).resizable().scaledToFit() }
struct SecureView<Content: View>: UIViewRepresentable {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    func makeUIView(context: Context) -> UIView {
        let secureField = UITextField()
        secureField.isSecureTextEntry = true
        secureField.isUserInteractionEnabled = false

        // The "secure canvas" lives inside a private subview of the text field
        // (`_UITextLayoutCanvasView`). Any view we add there participates in
        // the screenshot-blanking behavior. Locating it directly by class name
        // is brittle across iOS versions; instead we host our SwiftUI content
        // in a UIHostingController and stitch it in.
        let hosting = UIHostingController(rootView: AnyView(content()))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        let container = SecureContainerView(secureField: secureField)
        container.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A UIView that installs a hidden secure text field over itself and moves
/// its rendered content into the secure layer, so screenshots capture black.
final class SecureContainerView: UIView {
    private let secureField: UITextField

    init(secureField: UITextField) {
        self.secureField = secureField
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        secureField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(secureField)
        NSLayoutConstraint.activate([
            secureField.leadingAnchor.constraint(equalTo: leadingAnchor),
            secureField.trailingAnchor.constraint(equalTo: trailingAnchor),
            secureField.topAnchor.constraint(equalTo: topAnchor),
            secureField.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        secureField.isSecureTextEntry = true
        // Push the secure canvas layer above everything else so screenshots
        // pick up its blanking. This works because UIKit inserts a private
        // `_UITextLayoutCanvasView` in the secure field's subview tree.
        DispatchQueue.main.async { [weak self] in self?.reparentIntoSecureLayer() }
    }

    private func reparentIntoSecureLayer() {
        guard let canvas = firstSecureCanvas(in: secureField) else { return }
        // Move sibling content subviews (SwiftUI hosting view) into the
        // secure canvas so they inherit the blanking behavior.
        for sub in subviews where sub !== secureField {
            canvas.addSubview(sub)
            sub.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                sub.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
                sub.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
                sub.topAnchor.constraint(equalTo: canvas.topAnchor),
                sub.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
            ])
        }
    }

    private func firstSecureCanvas(in view: UIView) -> UIView? {
        let name = String(describing: type(of: view))
        if name.contains("CanvasView") { return view }
        for sub in view.subviews {
            if let hit = firstSecureCanvas(in: sub) { return hit }
        }
        return nil
    }
}
