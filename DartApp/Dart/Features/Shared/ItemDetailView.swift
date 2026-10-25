import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DartStore
    let initialItem: DartItem
    @State private var showUpcoming = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var reportDetails = ""
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: DartItem) { initialItem = item }

    private var item: DartItem { store.latest(initialItem) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    detailHero

                    if DartStatus.active.contains(item.status) || item.status == .completed {
                        LiveTrackingCard(item: item)
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
                    .dartSurface()

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
                        .background(DartTheme.paleBlue.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        Button { showUpcoming = true } label: {
                            PrimaryButtonLabel(title: futureActionTitle, icon: "arrow.right.circle.fill")
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(DartTheme.pageInset)
                .padding(.bottom, 20)
            }
            .background(DartBackdrop())
            .navigationTitle("Dart details")
            .toolbar {
                if store.isLive, item.person.id != store.userID {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Report", systemImage: "exclamationmark.bubble") { showReport = true }
                            Button("Block \(item.person.name)", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Safety actions")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) { appeared = true }
            }
            .alert("Report \(item.person.name)", isPresented: $showReport) {
                TextField("What happened?", text: $reportDetails)
                Button("Submit report") {
                    let details = reportDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        if await store.reportUser(item.person.id, item: item, category: "other", details: details) {
                            reportDetails = ""
                        }
                    }
                }
                .disabled(reportDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) { reportDetails = "" }
            } message: {
                Text("Reports are private and sent to Dart’s safety review queue. Call local emergency services for immediate danger.")
            }
            .confirmationDialog("Block \(item.person.name)?", isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block user", role: .destructive) {
                    Task { if await store.blockUser(item.person.id) { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will no longer see each other’s requests or runs. Blocking does not submit a report.")
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

    private var detailHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                DartIconTile(symbol: itemSymbol, size: 66, highlighted: true)
                    .scaleEffect(appeared ? 1 : 0.75)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.kindLabel.uppercased())
                        .font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.muted)
                    Text(item.title)
                        .font(.system(size: 29, weight: .heavy, design: .rounded))
                        .foregroundStyle(DartTheme.text)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if let reward = item.reward {
                    VStack(spacing: 0) {
                        Text("$\(reward)").font(.title2.weight(.heavy))
                        Text("reward").font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(DartTheme.limeInk)
                    .padding(10)
                    .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: 15))
                }
            }
            Text(item.detail).font(.body).foregroundStyle(DartTheme.muted)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private var itemSymbol: String {
        switch item.kind {
        case .campusRequest: "bag.fill"
        case .friendRun: "person.2.fill"
        case .buildingRun: "building.2.fill"
        case .campusRun: "storefront.fill"
        }
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

private struct LiveTrackingCard: View {
    let item: DartItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT STATUS").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.limeInk)
                    Text(item.status.rawValue).font(.title3.weight(.heavy)).foregroundStyle(DartTheme.text)
                }
                Spacer()
                Image(systemName: item.status.icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DartTheme.limeInk)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.50), in: Circle())
            }
            CompactStatusTrack(status: item.status)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(DartTheme.limeInk)
                Text(nextStep)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DartTheme.text)
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [DartTheme.lime.opacity(0.90), DartTheme.limeSoft.opacity(0.68)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var nextStep: String {
        switch item.status {
        case .waiting: "Next: a nearby helper accepts your request."
        case .accepted: "Next: the helper heads to the pickup."
        case .pickingUp: "Next: the helper confirms they are on the way."
        case .onTheWay: "Next: meet at the destination shown below."
        case .delivered: "Next: the requester confirms receipt."
        case .completed: "This Dart is complete."
        case .cancelled: "No further action is needed."
        case .expired: "Post a new Dart if you still need help."
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(DartTheme.blue).frame(width: 24)
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
            Text("$\(amount)").font(.title.bold()).foregroundStyle(emphasized ? DartTheme.limeInk : DartTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(emphasized ? DartTheme.lime.opacity(0.18) : DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(emphasized ? DartTheme.limeSoft.opacity(0.5) : DartTheme.line))
    }
}

/// Actions for a live request or run, chosen by your role and the item's status.
private struct LiveItemActions: View {
    @EnvironmentObject private var store: DartStore
    let item: DartItem
    let onDone: () -> Void

    @State private var working = false
    @State private var chooseRun = false
    @State private var askRunner = false
    @State private var askTitle = ""
    @State private var askBudget = ""
    @State private var matches: [(RequestMatch, DartItem)] = []

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
                    Text("$\(DartStore.dollars(match.rewardCents))").font(.headline).foregroundStyle(DartTheme.gold)
                    Button("Accept") {
                        Task {
                            if await store.accept(request, onRun: ref.id) { matches = await store.matches(forRun: ref.id) }
                        }
                    }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(DartTheme.limeInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(DartTheme.lime, in: Capsule())
                        .buttonStyle(PressableStyle())
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
        .foregroundStyle(role == .destructive ? DartTheme.danger : DartTheme.text)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.controlRadius).stroke(role == .destructive ? DartTheme.danger.opacity(0.35) : DartTheme.line))
        .buttonStyle(PressableStyle())
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
