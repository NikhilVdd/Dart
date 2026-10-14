import MapKit
import SwiftUI

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

extension GrabItem {
    /// Map pin symbol: requests are packages, runs show who they're for.
    var mapSymbol: String {
        switch kind {
        case .campusRequest: "shippingbox.fill"
        case .friendRun: "person.2.fill"
        case .buildingRun: "building.2.fill"
        case .campusRun: "storefront.fill"
        }
    }

    var mapTint: Color { kind == .campusRequest ? GrabTheme.gold : GrabTheme.blue }
}

/// A compact map of the feed above the list. Tap a pin to open the item; expand for a full map.
struct FeedMapCard: View {
    let items: [GrabItem]
    let onSelect: (GrabItem) -> Void

    @State private var expanded = false

    private var located: [GrabItem] { items.filter { $0.mapLocation != nil } }

    var body: some View {
        if !located.isEmpty {
            ZStack(alignment: .topTrailing) {
                FeedMap(items: located, onSelect: onSelect)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.8))

                Button { expanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .grabGlass(radius: 12)
                }
                .buttonStyle(PressableStyle())
                .padding(10)
                .accessibilityLabel("Expand map")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Map of \(located.count) nearby items. The same items are listed below.")
            .sheet(isPresented: $expanded) {
                NavigationStack {
                    FeedMap(items: located) { item in
                        expanded = false
                        onSelect(item)
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .macSheetSize(minWidth: 560, minHeight: 560)
                    .navigationTitle("Nearby")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Pins for feed items; selecting one calls `onSelect`.
struct FeedMap: View {
    let items: [GrabItem]
    let onSelect: (GrabItem) -> Void

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
