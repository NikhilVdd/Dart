import MapKit
import SwiftUI

/// Pickup → drop-off on a map, with the walking route and time from Apple Maps.
/// Falls back to a straight line if no route is available; shows a single pin when only one end is known.
struct RouteMapCard: View {
    let item: DartItem

    @State private var route: MKRoute?
    @State private var position: MapCameraPosition = .automatic
    @State private var loading = false

    private var pickup: GeoPoint? { item.pickupLocation }
    private var destination: GeoPoint? { item.destinationLocation }

    var body: some View {
        if pickup != nil || destination != nil {
            VStack(alignment: .leading, spacing: 10) {
                Map(position: $position, interactionModes: [.pan, .zoom]) {
                    if let pickup {
                        Marker(item.pickup, systemImage: item.kind == .campusRequest ? "bag.fill" : "storefront.fill",
                               coordinate: pickup.coordinate)
                            .tint(DartTheme.blue)
                    }
                    if let destination {
                        Marker(item.destination, systemImage: "flag.checkered", coordinate: destination.coordinate)
                            .tint(DartTheme.limeInk)
                    }
                    if let route {
                        MapPolyline(route).stroke(DartTheme.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    } else if let pickup, let destination, !loading {
                        MapPolyline(coordinates: [pickup.coordinate, destination.coordinate])
                            .stroke(DartTheme.blue.opacity(0.6), style: StrokeStyle(lineWidth: 3, dash: [6, 6]))
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)

                Label(summary, systemImage: "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .task(id: item.id) { await loadRoute() }
        }
    }

    private var summary: String {
        if pickup == nil { return "Pickup from any nearby store · delivered to \(item.destination)" }
        if destination == nil { return item.pickup }
        if loading { return "Finding the walking route…" }
        guard let route else {
            return "About \(Self.distance(meters: straightLineMeters)) as the crow flies"
        }
        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        return "\(minutes) min walk · \(Self.distance(meters: route.distance)) from pickup to drop-off"
    }

    private var straightLineMeters: Double {
        guard let pickup, let destination else { return 0 }
        return CLLocation(latitude: pickup.lat, longitude: pickup.lng)
            .distance(from: CLLocation(latitude: destination.lat, longitude: destination.lng))
    }

    private func loadRoute() async {
        guard let pickup, let destination else { return }
        loading = true
        defer { loading = false }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: pickup.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .walking
        route = try? await MKDirections(request: request).calculate().routes.first
        position = .automatic
    }

    private static func distance(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
