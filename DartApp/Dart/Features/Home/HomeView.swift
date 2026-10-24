import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: DartItem?
    @State private var creating: CreateSheet.Destination?
    @State private var appeared = false
    @State private var findingTask = false
    @State private var noTaskNearby = false

    private var feed: [DartItem] { store.feed(for: state.homeMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    if store.phase == .signedOut { SignInBanner() }
                    SlidingSegmentedControl(selection: $state.homeMode)
                    primaryAction
                    if state.homeMode == .earn { announceRunAction }
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
                        Button { selectedItem = item } label: { DartItemCard(item: item) }
                            .buttonStyle(PressableStyle())
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(Double(index) * 0.07), value: appeared)
                    }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .onAppear { appeared = true }
            .sheet(item: $selectedItem) { ItemDetailView(item: $0) }
            .sheet(item: $creating) { CreateSheet(destination: $0) }
            .alert("No tasks nearby right now", isPresented: $noTaskNearby) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("There are no open requests within 5 km. We'll notify you when one comes in.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(greeting), \(store.firstName ?? state.profileName)").font(.subheadline).foregroundStyle(.secondary)
                Text("What can we grab?").font(.largeTitle.bold())
                Label(store.campusName ?? state.campus, systemImage: "graduationcap.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(DartTheme.blue)
            }
            Spacer()
            if !store.isLive { PreviewPill(text: "PREVIEW") }
        }
    }

    private var primaryAction: some View {
        Button {
            if state.homeMode == .request { creating = .request }
            else { findNearbyTask() }
        } label: {
            PrimaryButtonLabel(
                title: state.homeMode == .request ? "What do you need?" : (findingTask ? "Finding a task…" : "Find a nearby task"),
                icon: state.homeMode == .request ? "plus" : "location.fill"
            )
        }
        .buttonStyle(PressableStyle())
        .disabled(findingTask)
    }

    private var announceRunAction: some View {
        Button { creating = .run } label: {
            SecondaryButtonLabel(title: "Announce a store run", icon: "storefront.fill")
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Let friends or approved neighbors know you’re already going")
    }

    private func findNearbyTask() {
        findingTask = true
        Task {
            let task = await store.findNearbyTask()
            findingTask = false
            if let task { selectedItem = task } else { noTaskNearby = true }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private func activeCard(_ item: DartItem) -> some View {
        Button { selectedItem = item } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(state.homeMode == .request ? "ACTIVE REQUEST" : "ACTIVE JOB", systemImage: "waveform.path.ecg")
                        .font(.caption2.bold()).tracking(0.8).foregroundStyle(DartTheme.blue)
                    Spacer()
                    StatusChip(status: item.status)
                }
                Text(item.title)
                    .font(.headline).foregroundStyle(.primary)
                Text(activeSubtitle(item))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(18)
            .dartSurface()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens active item details")
    }

    private func activeSubtitle(_ item: DartItem) -> String {
        guard store.isLive else {
            return state.homeMode == .request ? "Accepted by Maya · merchandise budget is separate" : "Returning to The Durant · $5 preview reward"
        }
        let reward = item.reward.map { " · $\($0) reward" } ?? ""
        return "\(item.pickup) → \(item.destination)\(reward)"
    }
}
