import MapKit
import SwiftUI

/// Which places a picker offers.
enum PlaceFilter {
    case stores        // where a run starts
    case destinations  // where things get delivered
    case any           // request pickups: anywhere something can be collected

    func allows(_ place: PlaceRow) -> Bool {
        switch self {
        case .stores: place.isStore
        case .destinations: !place.isStore
        case .any: true
        }
    }

    /// Kinds offered when adding a place from Apple Maps, as (`place_kind`, label).
    var kinds: [(String, String)] {
        let stores = [("store", "Store"), ("restaurant", "Restaurant or café")]
        let others = [("residence", "Residence or apartment"), ("campus", "Campus building"),
                      ("library", "Library"), ("transit", "Transit stop"), ("other", "Something else")]
        switch self {
        case .stores: return stores
        case .destinations: return others
        case .any: return stores + others
        }
    }
}

/// A form row that shows the chosen place and opens the search sheet.
struct PlaceField: View {
    @EnvironmentObject private var store: DartStore
    let title: String
    @Binding var selection: UUID?
    var filter: PlaceFilter = .any
    /// Offer "Any store" (stored as a nil selection) for requests where Dart picks the store.
    var allowsAnyStore = false

    @State private var searching = false

    private var label: String {
        if let place = store.places.first(where: { $0.id == selection }) { return place.label }
        return allowsAnyStore ? "Any store — let Dart decide" : "Choose a place"
    }

    var body: some View {
        Button { searching = true } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(label)
                    .foregroundStyle(selection == nil && !allowsAnyStore ? .secondary : .primary)
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .dartModal(isPresented: $searching) {
            PlaceSearchView(title: title, selection: $selection, filter: filter, allowsAnyStore: allowsAnyStore)
        }
    }
}

/// Search existing places and Apple Maps; adding a map result creates the place on Dart.
struct PlaceSearchView: View {
    @EnvironmentObject private var store: DartStore
    @Environment(\.dartDismiss) private var dismiss

    let title: String
    @Binding var selection: UUID?
    let filter: PlaceFilter
    let allowsAnyStore: Bool

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searchingMaps = false
    @State private var adding = false
    @State private var pendingMapItem: MKMapItem?

    private var existing: [PlaceRow] {
        let matches = store.places.filter(filter.allows)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return matches }
        return matches.filter { $0.label.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Map results that aren't already on Dart. Mirrors create_place's de-duplication: within 150 m
    /// and one name contains the other ("CVS" / "CVS Pharmacy").
    private var newResults: [MKMapItem] {
        results.filter { item in
            let coordinate = item.placemark.coordinate
            let name = (item.name ?? "").lowercased()
            return !store.places.contains { place in
                let existing = place.name.lowercased()
                return (name.contains(existing) || existing.contains(name))
                    && Self.meters(place.lat, place.lng, coordinate.latitude, coordinate.longitude) < 150
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    DartSearchField(
                        prompt: filter == .stores ? "Search stores" : "Search places",
                        text: $query
                    )

                if allowsAnyStore && query.isEmpty {
                    Button { choose(nil) } label: {
                        placeCard(icon: "sparkles", title: "Any store",
                                  subtitle: "Someone already shopping nearby picks it up",
                                  selected: selection == nil)
                    }
                    .buttonStyle(PressableStyle())
                }

                if !existing.isEmpty {
                    SectionHeading(title: "On Dart", subtitle: "Saved places near your campus")
                    VStack(spacing: 0) {
                        ForEach(existing) { place in
                            Button { choose(place.id) } label: {
                                row(icon: Self.symbol(for: place.kind), title: place.name, subtitle: place.detail,
                                    selected: selection == place.id)
                            }
                            .buttonStyle(PressableStyle())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            if place.id != existing.last?.id {
                                Divider().overlay(DartTheme.line).padding(.leading, 54)
                            }
                        }
                    }
                    .dartSurface(radius: DartTheme.controlRadius)
                }

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    SectionHeading(title: "Add from Apple Maps", subtitle: "Not on Dart yet? Add it for your campus")
                    VStack(spacing: 12) {
                        if searchingMaps && results.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView().tint(DartTheme.lime)
                                Text("Searching nearby…").foregroundStyle(DartTheme.muted)
                                Spacer()
                            }
                            .padding(18)
                            .dartSurface(radius: DartTheme.controlRadius)
                        } else if newResults.isEmpty {
                            EmptyStateCard(title: "No new matches", message: "Try a broader place or street name.")
                        }
                        ForEach(newResults, id: \.self) { item in
                            Button { pendingMapItem = item } label: {
                                placeCard(icon: "plus", title: item.name ?? "Unnamed place",
                                          subtitle: Self.address(for: item.placemark), selected: false)
                            }
                            .buttonStyle(PressableStyle())
                            .disabled(adding)
                        }

                        if adding {
                            Label("Adding place…", systemImage: "arrow.triangle.2.circlepath")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(DartTheme.muted)
                        } else if let error = store.lastError {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(DartTheme.danger)
                        } else {
                            Text("Places you add are shared with everyone on your campus.")
                                .font(.footnote)
                                .foregroundStyle(DartTheme.muted)
                        }
                    }
                }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.vertical, 18)
            }
            .background(DartBackdrop())
            .task(id: query) { await searchMaps() }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .macSheetSize(minHeight: 540)
        }
        .dartDialog(isPresented: Binding(
            get: { pendingMapItem != nil },
            set: { if !$0 { pendingMapItem = nil } }
        )) {
            if let item = pendingMapItem {
                PlaceKindChooser(
                    placeName: item.name ?? "this place",
                    kinds: kinds(for: item),
                    choose: { kind in
                        pendingMapItem = nil
                        Task { await add(item, kind: kind) }
                    },
                    cancel: { pendingMapItem = nil }
                )
            }
        }
    }

    /// The inferred kind first, then the rest of the kinds this picker allows.
    private func kinds(for item: MKMapItem) -> [(String, String)] {
        let guess = Self.inferredKind(item)
        return filter.kinds.filter { $0.0 == guess } + filter.kinds.filter { $0.0 != guess }
    }

    private func row(icon: String, title: String, subtitle: String?, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(DartTheme.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(DartTheme.blue) }
        }
        .contentShape(Rectangle())
    }

    private func placeCard(icon: String, title: String, subtitle: String?, selected: Bool) -> some View {
        row(icon: icon, title: title, subtitle: subtitle, selected: selected)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dartSurface(radius: DartTheme.controlRadius)
    }

    private func choose(_ id: UUID?) {
        selection = id
        dismiss()
    }

    private func searchMaps() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; return }
        try? await Task.sleep(nanoseconds: 300_000_000)   // debounce typing
        guard !Task.isCancelled else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        let center = store.campusCenter
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lng),
            latitudinalMeters: 8000, longitudinalMeters: 8000
        )
        request.resultTypes = filter == .stores ? .pointOfInterest : [.pointOfInterest, .address]

        searchingMaps = true
        defer { searchingMaps = false }
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            // Keep to the area the backend accepts (15 km from campus).
            results = response.mapItems.filter {
                Self.meters(center.lat, center.lng, $0.placemark.coordinate.latitude, $0.placemark.coordinate.longitude) < 15000
            }
        } catch {
            if !Task.isCancelled { results = [] }
        }
    }

    private func add(_ item: MKMapItem, kind: String) async {
        adding = true
        defer { adding = false }
        let placemark = item.placemark
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let place = NewPlace(
            name: item.name ?? street,
            kind: kind,
            lat: placemark.coordinate.latitude,
            lng: placemark.coordinate.longitude,
            detail: placemark.thoroughfare ?? placemark.locality,
            address: street.isEmpty ? nil : street
        )
        if let row = await store.createPlace(place) { choose(row.id) }
    }

    // MARK: Helpers

    private static func inferredKind(_ item: MKMapItem) -> String {
        switch item.pointOfInterestCategory {
        case .store?, .foodMarket?, .pharmacy?, .bakery?, .gasStation?: "store"
        case .restaurant?, .cafe?, .brewery?, .winery?, .nightlife?: "restaurant"
        case .library?: "library"
        case .university?, .school?: "campus"
        case .publicTransport?: "transit"
        case nil: "residence"   // plain addresses are usually homes or apartment buildings
        default: "other"
        }
    }

    private static func symbol(for kind: String) -> String {
        switch kind {
        case "store": "cart.fill"
        case "restaurant": "fork.knife"
        case "library": "books.vertical.fill"
        case "residence": "house.fill"
        case "campus": "building.columns.fill"
        case "transit": "tram.fill"
        default: "mappin"
        }
    }

    private static func address(for placemark: MKPlacemark) -> String {
        [[placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " "), placemark.locality]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func meters(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        CLLocation(latitude: lat1, longitude: lng1).distance(from: CLLocation(latitude: lat2, longitude: lng2))
    }
}

private struct PlaceKindChooser: View {
    let placeName: String
    let kinds: [(String, String)]
    let choose: (String) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DartIconTile(symbol: "mappin.and.ellipse", size: 58, highlighted: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("What kind of place is this?")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(DartTheme.text)
                Text(placeName)
                    .font(.subheadline)
                    .foregroundStyle(DartTheme.muted)
            }

            ScrollView {
                VStack(spacing: 9) {
                    ForEach(kinds, id: \.0) { kind, label in
                        Button { choose(kind) } label: {
                            HStack {
                                Text(label).font(.headline)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .foregroundStyle(DartTheme.text)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            .background(DartTheme.surfaceRaised,
                                        in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                            .overlay(RoundedRectangle(cornerRadius: DartTheme.controlRadius).stroke(DartTheme.line))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .frame(maxHeight: 270)

            Button("Not now", action: cancel)
                .font(.headline)
                .foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .buttonStyle(PressableStyle())
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
    }
}
