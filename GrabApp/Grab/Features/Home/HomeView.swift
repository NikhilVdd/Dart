import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: GrabItem?
    @State private var showCreate = false
    @State private var appeared = false

    private var feed: [GrabItem] {
        state.homeMode == .request
        ? [PreviewData.traderJoes, PreviewData.buildingRun, PreviewData.shampoo]
        : [PreviewData.charger, PreviewData.shampoo, PreviewData.buildingRun]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    SlidingSegmentedControl(selection: $state.homeMode)
                    primaryAction
                    activeCard
                    SectionHeading(
                        title: state.homeMode == .request ? "Nearby & for you" : "Earn nearby",
                        subtitle: state.homeMode == .request ? "Store runs and current requests" : "Paid opportunities with clear effort"
                    )
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
            .onAppear { appeared = true }
            .sheet(item: $selectedItem) { ItemDetailView(item: $0) }
            .sheet(isPresented: $showCreate) { CreateMenuView() }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Good afternoon, Nikhil").font(.subheadline).foregroundStyle(.secondary)
                Text("What can we grab?").font(.largeTitle.bold())
                Label(state.campus, systemImage: "graduationcap.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(GrabTheme.blue)
            }
            Spacer()
            PreviewPill(text: "PREVIEW")
        }
    }

    private var primaryAction: some View {
        Button {
            if state.homeMode == .request { showCreate = true }
            else { selectedItem = PreviewData.charger }
        } label: {
            PrimaryButtonLabel(
                title: state.homeMode == .request ? "What do you need?" : "Find a nearby task",
                icon: state.homeMode == .request ? "plus" : "location.fill"
            )
        }
        .buttonStyle(PressableStyle())
    }

    private var activeCard: some View {
        Button { selectedItem = state.homeMode == .request ? PreviewData.shampoo : PreviewData.buildingRun } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(state.homeMode == .request ? "ACTIVE REQUEST" : "ACTIVE JOB", systemImage: "waveform.path.ecg")
                        .font(.caption2.bold()).tracking(0.8).foregroundStyle(GrabTheme.blue)
                    Spacer()
                    StatusChip(status: state.homeMode == .request ? .accepted : .onTheWay)
                }
                Text(state.homeMode == .request ? "Pick up shampoo from Target" : "Target run back to your building")
                    .font(.headline).foregroundStyle(.primary)
                Text(state.homeMode == .request ? "Accepted by Maya · merchandise budget is separate" : "Returning to The Durant · $5 preview reward")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(18)
            .grabGlass()
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("Opens active item details")
    }
}
