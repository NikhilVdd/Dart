import SwiftUI

/// Requester's Orders tab: what's in progress, then past orders.
struct OrdersView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Orders").font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
                    RecordSections(records: store.activities(for: .requesting),
                                   emptyMessage: "Orders you request show up here.") { state.openItem = $0 }
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

/// Darter's Earnings tab: the running total up top, then every delivery.
struct EarningsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Earnings").font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
                    totalCard
                    RecordSections(records: store.activities(for: .helping),
                                   emptyMessage: "Deliveries you make show up here.") { state.openItem = $0 }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(store.isLive ? "Total earned" : "Sample earnings").font(.subheadline.weight(.semibold))
                    .foregroundStyle(DartTheme.muted)
                Spacer()
                if !store.isLive { PreviewPill(text: "SAMPLE") }
            }
            Text("$\(store.earnings.map { DartStore.dollars($0.earnedCents) } ?? 46)")
                .font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(DartTheme.text)
            HStack(spacing: 18) {
                stat("\(store.earnings?.completedCount ?? 9)", "delivered")
                stat("\(store.earnings?.activeCount ?? 1)", "in progress")
            }
            Text("Payouts aren’t live yet. Earnings are tracked here until they are.")
                .font(.caption).foregroundStyle(DartTheme.muted)
                .padding(.top, 4)
        }
        .padding(18)
        .background(DartTheme.limeWash, in: RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous).stroke(DartTheme.limeDeep.opacity(0.25)))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(value).font(.headline).foregroundStyle(DartTheme.text)
            Text(label).font(.subheadline).foregroundStyle(DartTheme.muted)
        }
    }
}

/// "In progress" and "Past" lists of activity rows.
private struct RecordSections: View {
    let records: [ActivityRecord]
    let emptyMessage: String
    let open: (DartItem) -> Void

    private var active: [ActivityRecord] { records.filter { DartStatus.active.contains($0.currentStatus) } }
    private var past: [ActivityRecord] { records.filter { !DartStatus.active.contains($0.currentStatus) } }

    var body: some View {
        if records.isEmpty {
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        }
        section("In progress", active)
        section("Past", past)
    }

    @ViewBuilder private func section(_ title: String, _ rows: [ActivityRecord]) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title)
                ForEach(rows) { record in
                    Button { open(record.item) } label: { ActivityRow(record: record) }
                        .buttonStyle(PressableStyle())
                }
            }
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
