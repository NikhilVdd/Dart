import MapKit
import SwiftUI

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

extension DartItem {
    /// Map pin symbol: requests are packages, runs show who they're for.
    var mapSymbol: String {
        switch kind {
        case .campusRequest: "shippingbox.fill"
        case .friendRun: "person.2.fill"
        case .buildingRun: "building.2.fill"
        case .campusRun: "storefront.fill"
        }
    }

    var mapTint: Color { kind == .campusRequest ? DartTheme.limeDeep : DartTheme.limeInk }
}

/// A full-height map of feed items. Tap a pin to open the item.
struct FeedMapSheet: View {
    let items: [DartItem]
    let onSelect: (DartItem) -> Void
    @Environment(\.dartDismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FeedMap(items: items.filter { $0.mapLocation != nil }, onSelect: onSelect)
                .ignoresSafeArea(edges: .bottom)
                .macSheetSize(minWidth: 560, minHeight: 560)
                .navigationTitle("Open orders")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}

/// Pins for feed items; selecting one calls `onSelect`.
struct FeedMap: View {
    let items: [DartItem]
    let onSelect: (DartItem) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var selection: UUID?

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(items) { item in
                if let location = item.mapLocation {
                    Marker(item.title, systemImage: item.mapSymbol, coordinate: location.coordinate)
                        .tint(item.mapTint)
                        .tag(item.id)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: selection) { _, id in
            guard let id, let item = items.first(where: { $0.id == id }) else { return }
            selection = nil
            onSelect(item)
        }
        .onChange(of: items.map(\.id)) { _, _ in position = .automatic }
    }
}
