import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: GrabStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: GrabItem?
    @State private var showCreate = false
    @State private var appeared = false

    private var feed: [GrabItem] { store.feed(for: state.homeMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    if store.phase == .signedOut { SignInBanner() }
                    SlidingSegmentedControl(selection: $state.homeMode)
                    primaryAction
                    if let active = store.activeItem(for: state.homeMode) { activeCard(active) }
                    SectionHeading(
                        title: state.homeMode == .request ? "Nearby & for you" : "Earn nearby",
                        subtitle: state.homeMode == .request ? "Store runs and current requests" : "Paid opportunities with clear effort"
                    )
                    FeedMapCard(items: feed) { selectedItem = $0 }
                    if store.isLive && feed.isEmpty {
                        ContentStateCard(state: store.isLoading ? .loading : .empty)
                    }
                    ForEach(Array(feed.enumerated()), id: \.element.id) { index, item in
                        Button { selectedItem = item } label: { GrabItemCard(item: item) }
                            .buttonStyle(PressableStyle())
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.07), value: appeared)
                    }
                }
                .padding(.horizontal, GrabTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(GrabBackdrop())
            .refreshable { await store.refresh() }
            .onAppear { appeared = true }
            .sheet(item: $selectedItem) { ItemDetailView(item: $0) }
            .sheet(isPresented: $showCreate) { CreateMenuView() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(greeting), \(store.firstName ?? state.profileName)").font(.subheadline).foregroundStyle(.secondary)
                Text("What can we grab?").font(.largeTitle.bold())
                Label(store.campusName ?? state.campus, systemImage: "graduationcap.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(GrabTheme.blue)
            }
            Spacer()
            if !store.isLive { PreviewPill(text: "PREVIEW") }
        }
    }

    private var primaryAction: some View {
        Button {
            if state.homeMode == .request { showCreate = true }
            else if let first = feed.first { selectedItem = first }
        } label: {
            PrimaryButtonLabel(
                title: state.homeMode == .request ? "What do you need?" : "Find a nearby task",
                icon: state.homeMode == .request ? "plus" : "location.fill"
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func activeCard(_ item: GrabItem) -> some View {
        Button { selectedItem = item } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(state.homeMode == .request ? "ACTIVE REQUEST" : "ACTIVE JOB", systemImage: "waveform.path.ecg")
                        .font(.caption2.bold()).tracking(0.8).foregroundStyle(GrabTheme.blue)
                    Spacer()
                    StatusChip(status: item.status)
                }
                Text(item.title)
                    .font(.headline).foregroundStyle(.primary)
                Text(activeSubtitle(item))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(18)
            .grabGlass()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens active item details")
    }

    private func activeSubtitle(_ item: GrabItem) -> String {
        guard store.isLive else {
            return state.homeMode == .request ? "Accepted by Maya · merchandise budget is separate" : "Returning to The Durant · $5 preview reward"
        }
        let reward = item.reward.map { " · $\($0) reward" } ?? ""
        return "\(item.pickup) → \(item.destination)\(reward)"
    }
}
