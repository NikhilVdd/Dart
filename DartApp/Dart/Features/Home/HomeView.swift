import SwiftUI

/// Requester home: where we're delivering, any order in progress, then the four eateries.
/// Tapping an eatery opens checkout with it already chosen.
struct RequestView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @State private var choosingHome = false
    @State private var homeID: UUID?

    private var liveOrders: [ActivityRecord] {
        store.activities(for: .requesting).filter { DartStatus.active.contains($0.currentStatus) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 14) {
                        DeliverToButton(place: store.buildingName ?? (store.isLive ? nil : state.building)) {
                            homeID = store.profile?.homePlaceID
                            choosingHome = true
                        }
                        .disabled(!store.isLive)
                        Text(liveOrders.isEmpty ? "Where’s your Grubhub order?" : "Your order")
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(DartTheme.text)
                    }

                    if !liveOrders.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(liveOrders) { record in
                                ActiveOrderCard(item: record.item, update: record.lastUpdate) { state.openItem = record.item }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Pick up from")
                        PickupSpotGrid { state.creating = .request($0) }
                        Label("Place your order on Grubhub first, then tap where it’s waiting.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(DartTheme.muted)
                    }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 14)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .dartModal(isPresented: $choosingHome) {
                PlaceSearchView(title: "Deliver to", selection: $homeID, filter: .destinations, allowsAnyStore: false)
            }
            .onChange(of: homeID) { _, id in
                guard let id, id != store.profile?.homePlaceID else { return }
                Task { _ = await store.setHome(id) }
            }
        }
    }
}

/// The "Deliver to ⌄" line at the top of the requester's home, like a delivery app's address bar.
private struct DeliverToButton: View {
    let place: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill").font(.caption.weight(.bold)).foregroundStyle(DartTheme.limeDeep)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Deliver to").font(.caption2.weight(.semibold)).foregroundStyle(DartTheme.muted)
                    Text(place ?? "Choose a drop-off").font(.subheadline.weight(.bold)).foregroundStyle(DartTheme.text)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(DartTheme.muted)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(DartTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(DartTheme.line))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Deliver to \(place ?? "not set")")
        .accessibilityHint("Changes your default drop-off")
    }
}

/// A requester's order in progress: the status is the headline, then what happens next.
struct ActiveOrderCard: View {
    let item: DartItem
    /// The latest update line, e.g. "Accepted by Maya".
    let update: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let spot = item.pickupSpot {
                        SpotBadge(spot: spot, size: 44)
                    } else {
                        DartIconTile(symbol: item.status.icon, size: 44, highlighted: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.pickupSpot?.name ?? item.title)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(DartTheme.muted).lineLimit(1)
                        Text("To \(item.destination)")
                            .font(.subheadline).foregroundStyle(DartTheme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DartTheme.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.status.rawValue)
                        .font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                    Text(update)
                        .font(.subheadline).foregroundStyle(DartTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CompactStatusTrack(status: item.status)
            }
            .padding(18)
            .background(DartTheme.limeWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DartTheme.limeDeep.opacity(0.22)))
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens tracking and actions")
    }
}

/// Darter home: an online switch, what you're carrying (with its next step right on the card),
/// then open orders nearest first while you're online.
struct DeliverView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    /// nil shows every spot.
    @State private var filter: PickupSpot?
    @State private var showMap = false

    private var allOpenOrders: [DartItem] {
        store.feed(for: .earn).filter { $0.status == .waiting }
    }

    private var openOrders: [DartItem] {
        allOpenOrders.filter { filter == nil || $0.pickupSpot == filter }
    }

    private var currentDeliveries: [DartItem] {
        store.activities(for: .helping).filter { DartStatus.active.contains($0.currentStatus) }.map(\.item)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .center) {
                        Text("Deliver").font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
                        Spacer()
                        if state.darterOnline, openOrders.contains(where: { $0.mapLocation != nil }) {
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

                    OnlineCard(online: $state.darterOnline, waiting: allOpenOrders.count)

                    if !currentDeliveries.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(currentDeliveries.count == 1 ? "Current delivery" : "Current deliveries")
                            ForEach(currentDeliveries) { item in
                                DeliveryTaskCard(item: item) { state.openItem = item }
                            }
                        }
                    }

                    if !store.myActiveRuns.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Your trip")
                            ForEach(store.myActiveRuns) { item in
                                LiveOrderRow(item: item) { state.openItem = item }
                            }
                        }
                    }

                    if state.darterOnline {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Orders near you")
                            filterBar
                            if openOrders.isEmpty {
                                Text(filter == nil ? "No open orders right now. New ones show up here and as a notification."
                                                   : "Nothing at \(filter!.name) right now.")
                                    .font(.subheadline)
                                    .foregroundStyle(DartTheme.muted)
                                    .frame(maxWidth: .infinity)
                                    .multilineTextAlignment(.center)
                                    .padding(.vertical, 28)
                            }
                            ForEach(openOrders) { item in
                                Button { state.openItem = item } label: { DartItemCard(item: item) }
                                    .buttonStyle(PressableStyle())
                            }
                        }

                        if store.myActiveRuns.isEmpty {
                            Button { state.creating = .run } label: {
                                HStack(spacing: 12) {
                                    DartIconTile(symbol: "figure.walk", size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Already heading to an eatery?").font(.headline)
                                        Text("Share your trip and we’ll match orders to it").font(.caption).foregroundStyle(DartTheme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DartTheme.muted)
                                }
                                .foregroundStyle(DartTheme.text)
                                .padding(14)
                                .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DartTheme.line))
                            }
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

/// The darter's on/off switch. Offline is one big button; online is a quiet status line.
private struct OnlineCard: View {
    @Binding var online: Bool
    let waiting: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if online {
                HStack(spacing: 12) {
                    Circle().fill(DartTheme.limeDeep).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You’re online").font(.headline).foregroundStyle(DartTheme.text)
                        Text("We’ll notify you when an order comes in.").font(.caption).foregroundStyle(DartTheme.muted)
                    }
                    Spacer()
                    Button { toggle() } label: {
                        Text("Go offline")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(DartTheme.text)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(DartTheme.surface, in: Capsule())
                            .overlay(Capsule().stroke(DartTheme.line))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(16)
                .background(DartTheme.limeWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DartTheme.limeDeep.opacity(0.22)))
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You’re offline").font(.title3.weight(.heavy)).foregroundStyle(.white)
                        Text(waiting == 0 ? "Go online to start getting orders."
                                          : "\(waiting) \(waiting == 1 ? "order is" : "orders are") waiting near you.")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.72))
                    }
                    Button { toggle() } label: {
                        PrimaryButtonLabel(title: "Go online", icon: "bolt.fill")
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(18)
                .background(DartTheme.limeInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .sensoryFeedback(.success, trigger: online)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { online.toggle() }
    }
}

/// An order the darter is carrying. The card says where to go now and has the next step as its button.
private struct DeliveryTaskCard: View {
    @EnvironmentObject private var store: DartStore
    let item: DartItem
    let open: () -> Void
    @State private var working = false

    private var firstName: String { item.person.name.split(separator: " ").first.map(String.init) ?? "the requester" }

    private var heading: (label: String, place: String) {
        switch item.status {
        case .accepted, .pickingUp: ("Pick up at", item.pickupSpot?.name ?? item.pickup)
        case .delivered: ("Waiting for \(firstName) to confirm", item.destination)
        default: ("Drop off at", item.destination)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: open) {
                HStack(spacing: 12) {
                    if let spot = item.pickupSpot {
                        SpotBadge(spot: spot, size: 48)
                    } else {
                        DartIconTile(symbol: item.status.icon, size: 48, highlighted: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(heading.label).font(.caption.weight(.semibold)).foregroundStyle(DartTheme.muted)
                        Text(heading.place).font(.headline).foregroundStyle(DartTheme.text).lineLimit(1)
                        Text("For \(firstName)").font(.caption).foregroundStyle(DartTheme.muted)
                    }
                    Spacer(minLength: 4)
                    if let reward = item.reward {
                        Text("$\(reward)").font(.headline.weight(.heavy)).foregroundStyle(DartTheme.limeDeep)
                    }
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DartTheme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Opens the order")

            CompactStatusTrack(status: item.status)

            if store.isLive, item.backend?.role == .helper, let next = item.status.nextHelperStep {
                Button {
                    Task { working = true; _ = await store.advance(item, to: next); working = false }
                } label: {
                    PrimaryButtonLabel(title: next.helperActionTitle, icon: next.icon)
                }
                .buttonStyle(PressableStyle())
                .disabled(working)
            }
        }
        .padding(16)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(DartTheme.limeDeep.opacity(0.3), lineWidth: 1.5))
    }
}

extension DartStatus {
    /// Button title for a darter moving an order to this status.
    var helperActionTitle: String {
        switch self {
        case .pickingUp: "I’m at the eatery"
        case .onTheWay: "I have the order"
        case .delivered: "I dropped it off"
        default: rawValue
        }
    }

    /// What happens next, on the requester's side.
    var requesterNextStep: String {
        switch self {
        case .waiting: "We’re showing your order to darters nearby."
        case .accepted: "Your darter is heading to the eatery."
        case .pickingUp: "Your darter is picking up your order."
        case .onTheWay: "Your darter has your order and is on the way."
        case .delivered: "Your darter dropped it off. Confirm you got it."
        case .completed: "Delivered. Enjoy!"
        case .cancelled: "This order was cancelled."
        case .expired: "Nobody accepted in time. You can request again."
        }
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

/// An order or trip in progress: who's doing what, with a progress bar. Tap for details and actions.
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
