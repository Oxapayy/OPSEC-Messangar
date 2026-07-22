import SwiftUI
import AVKit
import MapKit

/// Map-preview bubble for a location message. Tap to open the full map.
struct LocationBubble: View {
    let message: Message
    @State private var full = false

    var body: some View {
        if let payload = message.text.flatMap(LocationPayload.decode) {
            Button { full = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Map(coordinateRegion: .constant(MKCoordinateRegion(
                        center: payload.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01,
                                               longitudeDelta: 0.01))),
                        annotationItems: [payload]) { p in
                        MapAnnotation(coordinate: p.coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2).foregroundStyle(Theme.cyan)
                        }
                    }
                    .frame(width: 220, height: 130)
                    .disabled(true)
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Theme.cyan)
                        Text(payload.label).lineLimit(1)
                    }
                    .padding(8)
                }
                .background(Theme.surfaceElevated)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $full) {
                LocationFullView(payload: payload)
            }
        } else {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.cyan)
                Text(message.text ?? "Location").foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

extension LocationPayload: Identifiable { public var id: String { encoded } }

/// Full-screen interactive map for a location message; offers "Open in Maps".
struct LocationFullView: View {
    let payload: LocationPayload
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(payload: LocationPayload) {
        self.payload = payload
        _region = State(initialValue: MKCoordinateRegion(
            center: payload.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(coordinateRegion: $region, annotationItems: [payload]) { p in
                MapAnnotation(coordinate: p.coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(Theme.cyan)
                }
            }
            .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title).foregroundStyle(.white.opacity(0.9)).padding()
            }
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text(payload.label).font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        let placemark = MKPlacemark(coordinate: payload.coordinate)
                        let item = MKMapItem(placemark: placemark)
                        item.name = payload.label
                        item.openInMaps(launchOptions: nil)
                    } label: { Text("Open in Maps") }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding()
                .background(Theme.surface.opacity(0.95),
                            in: RoundedRectangle(cornerRadius: 18))
                .padding()
            }
        }
    }
}

/// Small blue-check badge for users the server owner has flagged as Trusted.
/// Tapping opens an info alert.
struct TrustedBadge: View {
    var size: CGFloat = 14
    @State private var showInfo = false

    var body: some View {
        Button { showInfo = true } label: {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.cyan)
                .accessibilityLabel("Trusted user")
        }
        .buttonStyle(.plain)
        .alert("Trusted user", isPresented: $showInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This user has been verified as a legit person and will not be scamming anyone.")
        }
    }
}

/// Full-screen photo viewer with pinch-to-zoom and drag-to-pan.
struct FullImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable().scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(MagnificationGesture()
                    .onChanged { value in scale = max(1, lastScale * value) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { withAnimation { reset() } }
                    })
                .simultaneousGesture(DragGesture()
                    .onChanged { g in
                        if scale > 1 {
                            offset = CGSize(width: lastOffset.width + g.translation.width,
                                            height: lastOffset.height + g.translation.height)
                        }
                    }
                    .onEnded { _ in lastOffset = offset })
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                    }
                }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title).foregroundStyle(.white.opacity(0.85))
                    .padding()
            }
        }
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

/// Full-screen inline video viewer backed by AVKit.
struct FullVideoView: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var tempURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title).foregroundStyle(.white.opacity(0.85)).padding()
            }
        }
        .onAppear(perform: setup)
        .onDisappear {
            player?.pause()
            if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
        }
    }

    private func setup() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("play-\(UUID().uuidString).mp4")
        do {
            try data.write(to: url, options: [.atomic])
            tempURL = url
            player = AVPlayer(url: url)
        } catch { /* keep spinner */ }
    }
}
