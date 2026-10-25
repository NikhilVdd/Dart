import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: DartItem?
    @State private var creating: CreateSheet.Destination?
    @State private var showGroups = false
    @State private var showNotifications = false
    @State private var appeared = false

    private var recommendations: [DartItem] {
        Array(store.feed(for: .request).filter { $0.status == .waiting || $0.backend?.source == .run }.prefix(4))
    }

    private var activeItem: DartItem? {
        store.activeItem(for: .request) ?? store.activeItem(for: .earn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    welcomeHero
                    if let activeItem { activeTaskCard(activeItem) }
                    quickActions
                    communityStrip
                    recommendationsSection
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 14)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) { appeared = true }
            }
            .dartModal(item: $selectedItem) { ItemDetailView(item: $0) }
            .dartModal(item: $creating) { CreateSheet(destination: $0) }
            .dartModal(isPresented: $showGroups) { GroupsView().macSheetSize() }
            .dartModal(isPresented: $showNotifications) { NotificationInboxSheet() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(greeting)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DartTheme.muted)
                Text(store.firstName ?? state.profileName)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(DartTheme.text)
            }
            Spacer()
            campusPill
            Button { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(DartTheme.text)
                        .frame(width: 44, height: 44)
                        .background(DartTheme.surface, in: Circle())
                        .overlay(Circle().stroke(DartTheme.line))
                    if activeItem != nil {
                        Circle().fill(DartTheme.lime).frame(width: 11, height: 11)
                            .overlay(Circle().stroke(DartTheme.surface, lineWidth: 2))
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Notifications")
        }
    }

    private var campusPill: some View {
        Label(store.campusName ?? state.campus, systemImage: "graduationcap.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(DartTheme.limeInk)
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(DartTheme.lime, in: Capsule())
            .lineLimit(1)
    }

    private var welcomeHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Campus moves faster together.")
                        .font(.system(size: 31, weight: .heavy, design: .rounded))
                        .foregroundStyle(DartTheme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Post what you need. A nearby student can help.")
                        .font(.subheadline)
                        .foregroundStyle(DartTheme.muted)
                }
                DartIconTile(symbol: "bolt.fill", size: 66, highlighted: true)
            }
            Button { creating = .request } label: {
                PrimaryButtonLabel(title: "Request something", icon: "plus")
            }
            .buttonStyle(PressableStyle())
            .accessibilityHint("Starts a guided request")
        }
        .padding(20)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.08), radius: 22, y: 10)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Quick actions", subtitle: "The shortest path to what you need")
            HStack(spacing: 10) {
                QuickAction(title: "Explore", subtitle: "Earn nearby", symbol: "safari.fill") {
                    state.selectedTab = 1
                }
                QuickAction(title: "Store run", subtitle: "Ask your circle", symbol: "cart.fill") {
                    creating = .run
                }
                QuickAction(title: "Groups", subtitle: "Friends & home", symbol: "person.2.fill") {
                    showGroups = true
                }
            }
        }
    }

    @ViewBuilder private var communityStrip: some View {
        if !store.groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(title: "Your circles", subtitle: "Ask the people already close by")
                    Button("See all") { showGroups = true }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DartTheme.limeInk)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.groups.prefix(4)) { group in
                            Button { showGroups = true } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    AvatarStack(initials: group.memberInitials)
                                    Text(group.name).font(.headline).foregroundStyle(DartTheme.text).lineLimit(1)
                                    Text(group.latestMessage).font(.caption).foregroundStyle(DartTheme.muted).lineLimit(2)
                                }
                                .frame(width: 180, alignment: .leading)
                                .padding(16)
                                .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(DartTheme.line))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
        }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                SectionHeading(title: "Happening nearby", subtitle: "Relevant runs and open requests")
                Button("Explore") { state.selectedTab = 1 }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DartTheme.limeInk)
            }
            if store.isLive && recommendations.isEmpty {
                ContentStateCard(state: store.isLoading ? .loading : .empty)
            }
            ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, item in
                Button { selectedItem = item } label: { DartItemCard(item: item) }
                    .buttonStyle(PressableStyle())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.06), value: appeared)
            }
        }
    }

    private func activeTaskCard(_ item: DartItem) -> some View {
        Button { selectedItem = item } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Label("LIVE DART", systemImage: "waveform.path.ecg")
                        .font(.caption2.weight(.heavy)).tracking(1)
                        .foregroundStyle(DartTheme.limeInk)
                    Spacer()
                    Text(item.status.rawValue).font(.caption.weight(.bold)).foregroundStyle(DartTheme.limeInk)
                }
                Text(item.title).font(.title3.weight(.bold)).foregroundStyle(DartTheme.text)
                Text(nextStep(for: item)).font(.subheadline).foregroundStyle(DartTheme.muted)
                CompactStatusTrack(status: item.status)
                HStack {
                    Label("Open tracking", systemImage: "location.fill")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(DartTheme.limeInk)
            }
            .padding(18)
            .background(
                LinearGradient(colors: [DartTheme.lime.opacity(0.88), DartTheme.limeSoft.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens active Dart tracking")
    }

    private func nextStep(for item: DartItem) -> String {
        switch item.status {
        case .waiting: "Waiting for a nearby student to accept"
        case .accepted: "Your helper has the details"
        case .pickingUp: "Pickup is in progress"
        case .onTheWay: "Your Dart is on the way"
        case .delivered: "Confirm when you have it"
        case .completed: "All done"
        case .cancelled: "This Dart was cancelled"
        case .expired: "This Dart expired"
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
}

struct ExploreView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case quick = "Quick"
        case highReward = "Top pay"
        case runs = "Store runs"
        var id: String { rawValue }
    }

    @EnvironmentObject private var store: DartStore
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var selectedItem: DartItem?
    @State private var finding = false
    @State private var noTaskNearby = false

    private var items: [DartItem] {
        store.feed(for: .earn).filter { item in
            let text = "\(item.title) \(item.subtitle) \(item.pickup) \(item.destination)"
            let matchesQuery = query.isEmpty || text.localizedCaseInsensitiveContains(query)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .quick: matchesFilter = item.effort?.contains("min") == true
            case .highReward: matchesFilter = (item.reward ?? 0) >= 8
            case .runs: matchesFilter = item.kind != .campusRequest
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Explore")
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(DartTheme.text)
                        Text("Help nearby. Earn on your way.")
                            .font(.subheadline)
                            .foregroundStyle(DartTheme.muted)
                    }
                    DartSearchField(prompt: "Search requests, stores, or places", text: $query)
                    filterBar
                    Button { findClosest() } label: {
                        PrimaryButtonLabel(title: finding ? "Finding the closest Dart…" : "Find the closest Dart", icon: "location.fill")
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(finding)
                    FeedMapCard(items: items) { selectedItem = $0 }
                    HStack {
                        SectionHeading(title: "Available now", subtitle: "\(items.count) relevant opportunities")
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down").foregroundStyle(DartTheme.muted)
                    }
                    if store.isLive && items.isEmpty {
                        EmptyStateCard(title: "No matches yet", message: "Try another filter or pull to refresh. We’ll keep new requests organized by relevance.")
                    }
                    ForEach(items) { item in
                        Button { selectedItem = item } label: { DartItemCard(item: item) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .dartModal(item: $selectedItem) { ItemDetailView(item: $0) }
            .dartDialog(isPresented: $noTaskNearby) {
                DartAlertCard(symbol: "location.magnifyingglass", title: "Nothing nearby yet",
                              message: "We’ll surface a relevant request here as soon as one opens near campus.",
                              primaryTitle: "Got it") {
                    noTaskNearby = false
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { filter = item }
                    } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(filter == item ? DartTheme.limeInk : DartTheme.muted)
                            .padding(.horizontal, 15)
                            .frame(height: 42)
                            .background(filter == item ? DartTheme.lime : DartTheme.surface, in: Capsule())
                            .overlay(Capsule().stroke(filter == item ? Color.clear : DartTheme.line))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func findClosest() {
        finding = true
        Task {
            let task = await store.findNearbyTask()
            finding = false
            if let task { selectedItem = task } else { noTaskNearby = true }
        }
    }
}

private struct QuickAction: View {
    let title: String
    let subtitle: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                DartIconTile(symbol: symbol, size: 44)
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(DartTheme.text)
                Text(subtitle).font(.caption2).foregroundStyle(DartTheme.muted).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .padding(13)
            .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(DartTheme.line))
        }
        .buttonStyle(PressableStyle())
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

private struct NotificationInboxSheet: View {
    @Environment(\.dartDismiss) private var dismiss
    @EnvironmentObject private var store: DartStore
    @State private var selected: DartItem?

    private var records: [ActivityRecord] {
        Array((store.activities(for: .requesting) + store.activities(for: .helping)).prefix(12))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Updates that need you appear first. Dart groups repeat events instead of spamming you.")
                        .font(.subheadline)
                        .foregroundStyle(DartTheme.muted)
                    if records.isEmpty {
                        EmptyStateCard(title: "You’re all caught up", message: "Status changes, nearby opportunities, and group activity will appear here.")
                    }
                    ForEach(records) { record in
                        Button { selected = record.item } label: {
                            HStack(alignment: .top, spacing: 14) {
                                DartIconTile(symbol: record.currentStatus.icon, size: 46, highlighted: DartStatus.active.contains(record.currentStatus))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.item.title).font(.headline).foregroundStyle(DartTheme.text)
                                    Text(notificationCopy(record)).font(.subheadline).foregroundStyle(DartTheme.muted).multilineTextAlignment(.leading)
                                    Text(record.lastUpdate).font(.caption.weight(.semibold)).foregroundStyle(DartTheme.limeInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(DartTheme.muted)
                            }
                            .padding(16)
                            .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(DartTheme.line))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(DartTheme.pageInset)
            }
            .background(DartBackdrop())
            .navigationTitle("Notifications")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .dartModal(item: $selected) { ItemDetailView(item: $0) }
        }
        .macSheetSize()
    }

    private func notificationCopy(_ record: ActivityRecord) -> String {
        switch record.currentStatus {
        case .waiting: "Your Dart is live and visible to relevant helpers."
        case .accepted: "A helper accepted it. Open for details and messaging."
        case .pickingUp: "Pickup is in progress."
        case .onTheWay: "It’s on the way to the destination."
        case .delivered: "Delivered—confirm when you have it."
        case .completed: "Completed successfully."
        case .cancelled: "This Dart was cancelled."
        case .expired: "This Dart expired without a match."
        }
    }
}
