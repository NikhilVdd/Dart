import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @State private var selectedRecord: ActivityRecord?

    private var records: [ActivityRecord] { store.activities(for: state.activityMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !store.isLive { PreviewPill() }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Activity").font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
                        Text("Every active Dart and past handoff, in one place.")
                            .font(.subheadline).foregroundStyle(DartTheme.muted)
                    }
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
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .dartModal(item: $selectedRecord) { ActivityTimelineView(record: $0) }
        }
    }
}

private struct ActivityCard: View {
    let record: ActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                DartIconTile(symbol: record.currentStatus.icon, size: 48, highlighted: DartStatus.active.contains(record.currentStatus))
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.item.title).font(.headline.weight(.bold)).foregroundStyle(DartTheme.text)
                    Text(record.lastUpdate).font(.subheadline).foregroundStyle(DartTheme.muted)
                }
                Spacer()
                if let reward = record.item.reward {
                    Text("$\(reward)").font(.headline.weight(.heavy)).foregroundStyle(DartTheme.limeInk)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(DartTheme.lime, in: Capsule())
                }
            }
            CompactStatusTrack(status: record.currentStatus)
            HStack {
                Text(record.currentStatus.rawValue)
                    .font(.caption.weight(.bold)).foregroundStyle(DartTheme.text)
                Spacer()
                Text("Track & manage").font(.caption.weight(.bold)).foregroundStyle(DartTheme.limeInk)
                Image(systemName: "arrow.right").font(.caption.bold()).foregroundStyle(DartTheme.limeInk)
            }
        }
        .padding(18)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.cardRadius).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens status timeline")
    }
}

private struct ActivityTimelineView: View {
    @Environment(\.dartDismiss) private var dismiss
    @EnvironmentObject private var store: DartStore
    @State private var showDetail = false
    let record: ActivityRecord

    private let stages = DartStatus.timeline
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
                    .dartSurface()

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
                .padding(DartTheme.pageInset)
            }
            .background(DartBackdrop())
            .navigationTitle("Timeline")
            .dartModal(isPresented: $showDetail) { ItemDetailView(item: record.item) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .macSheetSize()
    }
}

private struct TimelineStep: View {
    enum StepState { case past, current, future }
    let status: DartStatus
    let state: StepState
    let showsLine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: state == .past ? "checkmark.circle.fill" : status.icon)
                    .font(.title3)
                    .foregroundStyle(state == .future ? Color.secondary.opacity(0.4) : (status == .completed ? DartTheme.gold : DartTheme.blue))
                    .frame(width: 28, height: 28)
                if showsLine {
                    Rectangle().fill(state == .future ? Color.secondary.opacity(0.15) : DartTheme.blue.opacity(0.35)).frame(width: 2, height: 38)
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
