import SwiftUI

/// Request tab: your live orders, then the four eateries. Tapping one opens the request form.
struct RequestView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore

    private var liveOrders: [DartItem] {
        store.activities(for: .requesting).filter { DartStatus.active.contains($0.currentStatus) }.map(\.item)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    PageHeader(title: "Where’s your order?", subtitle: "Tap the eatery your Grubhub order is at.")
                    if !liveOrders.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("On its way")
                            ForEach(liveOrders) { item in
                                LiveOrderRow(item: item) { state.openItem = item }
                            }
                        }
                    }
                    PickupSpotGrid { state.creating = .request($0) }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
        }
    }
}

/// Deliver tab: what you're carrying, a way to share a run, then open orders nearest first.
struct DeliverView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    /// nil shows every spot.
    @State private var filter: PickupSpot?
    @State private var showMap = false

    private var openOrders: [DartItem] {
        store.feed(for: .earn).filter { $0.status == .waiting && (filter == nil || $0.pickupSpot == filter) }
    }

    private var yourDeliveries: [DartItem] {
        store.activities(for: .helping).filter { DartStatus.active.contains($0.currentStatus) }.map(\.item)
            + store.myActiveRuns
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        PageHeader(title: "Deliver", subtitle: "Bring an order on your way and earn.")
                        if openOrders.contains(where: { $0.mapLocation != nil }) {
                            Button { showMap = true } label: {
                                Image(systemName: "map")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(DartTheme.text)
                                    .frame(width: 44, height: 44)
                                    .background(DartTheme.surface, in: Circle())
                                    .overlay(Circle().stroke(DartTheme.line))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Show orders on a map")
                        }
                    }

                    if !yourDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Your deliveries")
                            ForEach(yourDeliveries) { item in
                                LiveOrderRow(item: item) { state.openItem = item }
                            }
                        }
                    }

                    Button { state.creating = .run } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.walk").font(.headline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Heading to an eatery?").font(.headline)
                                Text("Share your trip and take orders along").font(.caption).foregroundStyle(DartTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DartTheme.muted)
                        }
                        .foregroundStyle(DartTheme.text)
                        .padding(16)
                        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DartTheme.line))
                    }
                    .buttonStyle(PressableStyle())

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Open orders")
                        filterBar
                        if openOrders.isEmpty {
                            Text(filter == nil ? "No open orders right now. Pull down to refresh."
                                               : "Nothing at \(filter!.name) right now.")
                                .font(.subheadline)
                                .foregroundStyle(DartTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                        }
                        ForEach(openOrders) { item in
                            Button { state.openItem = item } label: { DartItemCard(item: item) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .dartModal(isPresented: $showMap) {
                FeedMapSheet(items: openOrders) { item in
                    showMap = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        state.openItem = item
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", value: nil)
                ForEach(PickupSpot.allCases) { spot in
                    filterChip(spot.shortName, value: spot)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func filterChip(_ title: String, value: PickupSpot?) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = value }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(filter == value ? DartTheme.limeInk : DartTheme.muted)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(filter == value ? DartTheme.lime : DartTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(filter == value ? Color.clear : DartTheme.line))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(filter == value ? .isSelected : [])
    }
}

/// Large page title with a one-line subtitle.
struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
            Text(subtitle).font(.subheadline).foregroundStyle(DartTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Small uppercase label above a group of rows.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.9)
            .foregroundStyle(DartTheme.muted)
    }
}

/// An order in progress: who's doing what, with a progress bar. Tap for details and actions.
struct LiveOrderRow: View {
    let item: DartItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if let spot = item.pickupSpot {
                        SpotBadge(spot: spot, size: 44)
                    } else {
                        DartIconTile(symbol: item.status.icon, size: 44, highlighted: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.kind == .campusRequest ? item.status.rawValue : item.title)
                            .font(.headline).foregroundStyle(DartTheme.text).lineLimit(1)
                        Text("\(item.pickupSpot?.name ?? item.pickup) → \(item.destination)")
                            .font(.subheadline).foregroundStyle(DartTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DartTheme.muted)
                }
                if item.kind == .campusRequest { CompactStatusTrack(status: item.status) }
            }
            .padding(16)
            .background(DartTheme.limeWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DartTheme.limeDeep.opacity(0.22)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens tracking and actions")
    }
}

struct CompactStatusTrack: View {
    let status: DartStatus
    private let stages: [DartStatus] = [.waiting, .accepted, .pickingUp, .onTheWay, .delivered]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(stages, id: \.self) { stage in
                Capsule()
                    .fill(isReached(stage) ? DartTheme.limeInk : DartTheme.line.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
            }
        }
        .accessibilityLabel("Status: \(status.rawValue)")
    }

    private func isReached(_ stage: DartStatus) -> Bool {
        guard let current = stages.firstIndex(of: status), let index = stages.firstIndex(of: stage) else {
            return status == .completed
        }
        return index <= current
    }
}
