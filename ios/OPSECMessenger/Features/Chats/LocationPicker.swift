import SwiftUI
import MapKit
import CoreLocation

/// Location wire format: "lat,lng|label" — small, human-decodable, no JSON.
struct LocationPayload {
    let lat: Double
    let lng: Double
    let label: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    var encoded: String { "\(lat),\(lng)|\(label)" }

    static func decode(_ s: String) -> LocationPayload? {
        let parts = s.split(separator: "|", maxSplits: 1)
        let coords = parts.first.map(String.init) ?? s
        let label = parts.count > 1 ? String(parts[1]) : "Shared location"
        let ll = coords.split(separator: ",")
        guard ll.count == 2, let la = Double(ll[0]), let lo = Double(ll[1]) else { return nil }
        return LocationPayload(lat: la, lng: lo, label: label)
    }
}

/// Sheet that lets the user pick a spot on an interactive map and send it.
/// Uses MapKit (Apple Maps) — no external SDK, no Google. Tiles come from
/// Apple directly (not via Tor), but no user id is attached.
struct LocationPicker: View {
    let onSend: (LocationPayload) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loc = LocationHelper()
    @State private var center = CLLocationCoordinate2D(latitude: 47.376, longitude: 8.541)
    @State private var pin = CLLocationCoordinate2D(latitude: 47.376, longitude: 8.541)
    @State private var label = "Shared location"
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.376, longitude: 8.541),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))

    var body: some View {
        NavigationStack {
            ZStack {
                Map(coordinateRegion: $region, showsUserLocation: true,
                    annotationItems: [MapPin(id: 0, coord: pin)]) { p in
                    MapAnnotation(coordinate: p.coord) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Theme.cyan)
                            .shadow(radius: 4)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .onChange(of: region.center.latitude) { _, _ in
                    pin = region.center
                    Task { await reverseGeocode() }
                }

                VStack {
                    Text("Move the map to place the pin")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                    Spacer()
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.cyan)
                            Text(label).lineLimit(2)
                                .foregroundStyle(Theme.textPrimary).font(.footnote)
                            Spacer()
                        }
                        Button {
                            onSend(LocationPayload(lat: pin.latitude,
                                                   lng: pin.longitude, label: label))
                            dismiss()
                        } label: { Text("Send location") }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding()
                    .background(Theme.surface.opacity(0.95),
                                in: RoundedRectangle(cornerRadius: 18))
                    .padding()
                }
            }
            .navigationTitle("Share location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.cyan)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        loc.requestOnce { c in
                            guard let c else { return }
                            region = MKCoordinateRegion(
                                center: c,
                                span: MKCoordinateSpan(latitudeDelta: 0.01,
                                                       longitudeDelta: 0.01))
                            pin = c
                        }
                    } label: { Image(systemName: "location.fill") }
                    .foregroundStyle(Theme.cyan)
                }
            }
            .onAppear { loc.requestOnce { c in if let c { region.center = c; pin = c } } }
        }
    }

    private func reverseGeocode() async {
        let l = CLLocation(latitude: pin.latitude, longitude: pin.longitude)
        do {
            let places = try await CLGeocoder().reverseGeocodeLocation(l)
            if let p = places.first {
                let parts = [p.name, p.locality, p.country].compactMap { $0 }
                label = parts.isEmpty ? "Shared location" : parts.joined(separator: ", ")
            }
        } catch { /* keep default */ }
    }

    private struct MapPin: Identifiable {
        let id: Int
        let coord: CLLocationCoordinate2D
    }
}

/// Minimal one-shot CoreLocation helper.
final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pending: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOnce(_ cb: @escaping (CLLocationCoordinate2D?) -> Void) {
        pending = cb
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: cb(nil); pending = nil
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: pending?(nil); pending = nil
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        pending?(locs.first?.coordinate); pending = nil
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        pending?(nil); pending = nil
    }
}
