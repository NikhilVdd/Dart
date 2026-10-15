import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: GrabStore
    let initialItem: GrabItem
    @State private var showUpcoming = false

    init(item: GrabItem) { initialItem = item }

    private var item: GrabItem { store.latest(initialItem) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        PreviewPill(text: item.kindLabel.uppercased())
                        Text(item.title)
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.82)
                        Text(item.detail).font(.body).foregroundStyle(.secondary)
                        StatusChip(status: item.status)
                    }

                    VStack(spacing: 0) {
                        DetailRow(icon: "person.fill", label: item.kind == .campusRequest ? "Requester" : "Shopper", value: item.person.name)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "mappin.and.ellipse", label: "Pickup", value: item.pickup)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "location.fill", label: "Destination", value: item.destination)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "clock.fill", label: item.kind == .friendRun ? "Cutoff" : "Timing", value: item.timing)
                    }
                    .padding(.horizontal, 16)
                    .grabGlass()

                    RouteMapCard(item: item)

                    if item.reward != nil || item.merchandiseBudget != nil {
                        HStack(spacing: 12) {
                            if let reward = item.reward {
                                MoneyCard(label: "Helper reward", amount: reward, emphasized: true)
                            }
                            if let budget = item.merchandiseBudget {
                                MoneyCard(label: "Item budget", amount: budget, emphasized: false)
                            }
                        }
                    }

                    if store.isLive, item.backend != nil {
                        RequestChatCard(item: item)
                        LiveItemActions(item: item) { dismiss() }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Preview only").font(.headline)
                            Text("Accepting, purchasing, list editing, and delivery completion need a signed-in account. No payment or delivery is happening here.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .background(GrabTheme.paleBlue.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Button { showUpcoming = true } label: {
                            PrimaryButtonLabel(title: futureActionTitle, icon: "arrow.right.circle.fill")
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(GrabTheme.pageInset)
            }
            .background(GrabBackdrop())
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("Sign in to continue", isPresented: $showUpcoming) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text(store.isConfigured
                     ? "Sign in from Profile to accept requests, join runs, and track deliveries."
                     : "This build has no backend configured, so actions are shown for preview only.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .macSheetSize()
    }

    private var futureActionTitle: String {
        switch item.kind {
        case .campusRequest: "Preview accept flow"
        case .friendRun: "Preview add item flow"
        case .buildingRun: "Preview building request"
        case .campusRun: "Preview store-run request"
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(GrabTheme.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.medium))
            }
            Spacer()
        }
        .padding(.vertical, 14)
    }
}

private struct MoneyCard: View {
    let label: String
    let amount: Int
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("$\(amount)").font(.title.bold()).foregroundStyle(emphasized ? GrabTheme.gold : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.06)))
    }
}

/// Actions for a live request or run, chosen by your role and the item's status.
private struct LiveItemActions: View {
    @EnvironmentObject private var store: GrabStore
    let item: GrabItem
    let onDone: () -> Void

    @State private var working = false
    @State private var chooseRun = false
    @State private var askRunner = false
    @State private var askTitle = ""
    @State private var askBudget = ""
    @State private var matches: [(RequestMatch, GrabItem)] = []

    private var ref: BackendRef { item.backend! }

    var body: some View {
        VStack(spacing: 12) {
            switch (ref.source, ref.role) {
            case (.request, .viewer):
                if item.status == .waiting {
                    primary("Accept request", icon: "hand.raised.fill") {
                        if store.myActiveRuns.isEmpty { _ = await store.accept(item) } else { chooseRun = true }
                    }
                }
            case (.request, .helper):
                if let next = item.status.nextHelperStep {
                    primary("Mark \(next.rawValue.lowercased())", icon: next.icon) {
                        _ = await store.advance(item, to: next)
                    }
                }
                if [.accepted, .pickingUp].contains(item.status) {
                    secondary("Release to someone else", role: .destructive) { await finish(store.release(item)) }
                }
                if item.status == .delivered {
                    Text("Waiting for \(item.person.name.split(separator: " ").first ?? "the requester") to confirm. It completes automatically after 24 hours.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            case (.request, .owner):
                if [.onTheWay, .delivered].contains(item.status) {
                    primary("Confirm I received it", icon: "checkmark.circle.fill") { await finish(store.advance(item, to: .completed)) }
                }
                if [.waiting, .accepted].contains(item.status) {
                    secondary("Cancel request", role: .destructive) { await finish(store.cancel(item)) }
                }
            case (.run, .owner):
                runOwnerActions
            case (.run, _):
                primary(item.kind == .friendRun ? "Add to the shopping list" : "Ask \(item.person.name.split(separator: " ").first ?? "them") to grab something",
                        icon: item.kind == .friendRun ? "cart.badge.plus" : "bag.badge.plus") {
                    askRunner = true
                }
            }
        }
        .disabled(working)
        .confirmationDialog("Take this on one of your runs?", isPresented: $chooseRun, titleVisibility: .visible) {
            ForEach(store.myActiveRuns) { run in
                Button("Add to \(run.title)") { Task { _ = await store.accept(item, onRun: run.backend?.id) } }
            }
            Button("Make a dedicated trip") { Task { _ = await store.accept(item) } }
            Button("Cancel", role: .cancel) { }
        }
        .alert(item.kind == .friendRun ? "Add to the list" : "What should they grab?", isPresented: $askRunner) {
            TextField("Item", text: $askTitle)
            if item.kind != .friendRun {
                TextField("Item budget in dollars (optional)", text: $askBudget)
            }
            Button("Send") { Task { await sendAsk() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(item.kind == .friendRun
                 ? "Friends’ runs are free. Settle up for the item itself directly."
                 : "The $\(item.reward ?? 0) run fee goes to the shopper; the item budget is separate.")
        }
        .task { if ref.source == .run, ref.role == .owner { matches = await store.matches(forRun: ref.id) } }
    }

    @ViewBuilder private var runOwnerActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Requests that fit this trip", subtitle: "Smallest detour first")
            if matches.isEmpty {
                Text("Nothing fits right now. New requests appear here as people post them.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(matches, id: \.0.requestID) { match, request in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(request.title).font(.headline)
                        Text(match.detourMinutes.map { "+\($0) min · \(request.destination)" } ?? request.destination)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("$\(GrabStore.dollars(match.rewardCents))").font(.headline).foregroundStyle(GrabTheme.gold)
                    Button("Accept") {
                        Task {
                            if await store.accept(request, onRun: ref.id) { matches = await store.matches(forRun: ref.id) }
                        }
                    }
                        .buttonStyle(.borderedProminent)
                }
                .padding(14)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
            }
        }
        switch ref.rawStatus {
        case "open":
            primary("I’m in the store", icon: "bag.fill") { await finish(store.setRunStatus(item, "shopping")) }
        case "shopping":
            primary("Heading back", icon: "figure.walk") { await finish(store.setRunStatus(item, "returning")) }
        case "returning":
            primary("Finish run", icon: "checkmark.circle.fill") { await finish(store.setRunStatus(item, "completed")) }
        default:
            EmptyView()
        }
        secondary("Cancel run", role: .destructive) { await finish(store.setRunStatus(item, "cancelled")) }
    }

    private func primary(_ title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button { Task { working = true; await action(); working = false } } label: {
            PrimaryButtonLabel(title: title, icon: icon)
        }
        .buttonStyle(PressableStyle())
    }

    private func secondary(_ title: String, role: ButtonRole? = nil, action: @escaping () async -> Void) -> some View {
        Button(role: role) { Task { working = true; await action(); working = false } } label: {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
        }
        .buttonStyle(.bordered)
    }

    private func finish(_ ok: Bool) async {
        if ok { onDone() }
    }

    private func sendAsk() async {
        let title = askTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        working = true
        defer { working = false }
        let ok: Bool
        if item.kind == .friendRun, let groupID = ref.groupID {
            ok = await store.addListItem(title, groupID: groupID, runID: ref.id)
        } else {
            ok = await store.requestFromRun(item, title: title, budgetDollars: Int(askBudget.filter(\.isNumber)))
        }
        askTitle = ""
        askBudget = ""
        await finish(ok)
    }
}
