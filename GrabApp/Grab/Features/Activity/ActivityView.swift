import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: GrabStore
    @State private var selectedRecord: ActivityRecord?

    private var records: [ActivityRecord] { store.activities(for: state.activityMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !store.isLive { PreviewPill() }
                    Text("Activity").font(.largeTitle.bold())
                    SlidingSegmentedControl(selection: $state.activityMode)
                    SectionHeading(title: state.activityMode == .requesting ? "Your requests" : "Your helping activity",
                                   subtitle: store.isLive ? "Every delivery stage, updated live" : "Preview records across each delivery stage")
                    if store.isLive && records.isEmpty {
                        EmptyStateCard(title: "Nothing yet",
                                       message: state.activityMode == .requesting ? "Requests you post will show up here." : "Requests you accept will show up here.")
                    }
                    ForEach(records) { record in
                        Button { selectedRecord = record } label: {
                            ActivityCard(record: record)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, GrabTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(GrabBackdrop())
            .refreshable { await store.refresh() }
            .sheet(item: $selectedRecord) { ActivityTimelineView(record: $0) }
        }
    }
}

private struct ActivityCard: View {
    let record: ActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.item.title).font(.headline).foregroundStyle(.primary)
                    Text(record.lastUpdate).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let reward = record.item.reward {
                    Text("$\(reward)").font(.headline).foregroundStyle(GrabTheme.gold)
                }
            }
            HStack {
                StatusChip(status: record.currentStatus)
                Spacer()
                Text("View timeline").font(.caption.weight(.semibold)).foregroundStyle(GrabTheme.blue)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(GrabTheme.blue)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GrabTheme.cardRadius).stroke(Color.primary.opacity(0.06)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens status timeline")
    }
}

private struct ActivityTimelineView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GrabStore
    @State private var showDetail = false
    let record: ActivityRecord

    private let stages = GrabStatus.timeline
    private var currentIndex: Int { stages.firstIndex(of: record.currentStatus) ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !store.isLive { PreviewPill(text: "STATUS PREVIEW") }
                    if [.cancelled, .expired].contains(record.currentStatus) { StatusChip(status: record.currentStatus) }
                    Text(record.item.title).font(.largeTitle.bold())
                    Text(record.item.subtitle).font(.title3).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                            TimelineStep(
                                status: stage,
                                state: index < currentIndex ? .past : (index == currentIndex ? .current : .future),
                                showsLine: index < stages.count - 1
                            )
                        }
                    }
                    .padding(20)
                    .grabGlass()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.isLive ? "Details" : "Available preview information").font(.headline)
                        Label(record.lastUpdate, systemImage: "clock")
                        Label(record.item.pickup, systemImage: "mappin.and.ellipse")
                        Label(record.item.destination, systemImage: "location.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))

                    if store.isLive, record.item.backend != nil {
                        Button { showDetail = true } label: {
                            PrimaryButtonLabel(title: "Open request", icon: "arrow.right.circle.fill")
                        }
                        .buttonStyle(PressableStyle())
                    } else {
                        Text("Statuses are local preview data. No real delivery or payment is represented.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(GrabTheme.pageInset)
            }
            .background(GrabBackdrop())
            .navigationTitle("Timeline")
            .sheet(isPresented: $showDetail) { ItemDetailView(item: record.item) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDragIndicator(.visible)
    }
}

private struct TimelineStep: View {
    enum StepState { case past, current, future }
    let status: GrabStatus
    let state: StepState
    let showsLine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: state == .past ? "checkmark.circle.fill" : status.icon)
                    .font(.title3)
                    .foregroundStyle(state == .future ? Color.secondary.opacity(0.4) : (status == .completed ? GrabTheme.gold : GrabTheme.blue))
                    .frame(width: 28, height: 28)
                if showsLine {
                    Rectangle().fill(state == .future ? Color.secondary.opacity(0.15) : GrabTheme.blue.opacity(0.35)).frame(width: 2, height: 38)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(status.rawValue).font(.body.weight(state == .current ? .bold : .medium))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 3)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch state {
        case .past: "Complete"
        case .current: "Current status"
        case .future: "Next step"
        }
    }
}
