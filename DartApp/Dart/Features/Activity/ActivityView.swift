import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore

    private var records: [ActivityRecord] { store.activities(for: state.activityMode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    PageHeader(title: "Activity", subtitle: "Every order you’ve requested or delivered.")
                        .padding(.bottom, 10)
                    SlidingSegmentedControl(selection: $state.activityMode)
                        .padding(.bottom, 8)
                    if records.isEmpty {
                        Text(state.activityMode == .requesting ? "Orders you request will show up here."
                                                               : "Orders you deliver will show up here.")
                            .font(.subheadline)
                            .foregroundStyle(DartTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                    ForEach(records) { record in
                        Button { state.openItem = record.item } label: {
                            ActivityRow(record: record)
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
        }
    }
}

private struct ActivityRow: View {
    let record: ActivityRecord

    private var isActive: Bool { DartStatus.active.contains(record.currentStatus) }

    var body: some View {
        HStack(spacing: 14) {
            if let spot = record.item.pickupSpot {
                SpotBadge(spot: spot, size: 44)
            } else {
                DartIconTile(symbol: record.currentStatus.icon, size: 44, highlighted: isActive)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.item.pickupSpot?.name ?? record.item.title)
                    .font(.headline).foregroundStyle(DartTheme.text).lineLimit(1)
                Text(record.lastUpdate)
                    .font(.subheadline).foregroundStyle(DartTheme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let reward = record.item.reward {
                Text("$\(reward)").font(.subheadline.weight(.bold)).foregroundStyle(DartTheme.text)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(DartTheme.muted)
        }
        .padding(14)
        .background(isActive ? DartTheme.limeWash : DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(isActive ? DartTheme.limeDeep.opacity(0.22) : DartTheme.line))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the order")
    }
}
