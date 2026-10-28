import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dartDismiss) private var dismiss
    @EnvironmentObject private var store: DartStore
    let initialItem: DartItem
    @State private var showUpcoming = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var showSafetyActions = false
    @State private var reportDetails = ""
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: DartItem) { initialItem = item }

    private var item: DartItem { store.latest(initialItem) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailHero

                    if DartStatus.active.contains(item.status) || item.status == .completed {
                        LiveTrackingCard(item: item)
                    }

                    // What you can do next comes first; reference details follow.
                    if store.isLive, item.backend != nil {
                        LiveItemActions(item: item) { dismiss() }
                    } else {
                        Button { showUpcoming = true } label: {
                            PrimaryButtonLabel(title: futureActionTitle, icon: "arrow.right.circle.fill")
                        }
                        .buttonStyle(PressableStyle())
                        Text("Preview only. Sign in to accept and deliver real orders.")
                            .font(.footnote).foregroundStyle(DartTheme.muted)
                            .frame(maxWidth: .infinity)
                    }

                    VStack(spacing: 0) {
                        if item.backend?.role != .owner {
                            DetailRow(icon: "person.fill", label: item.kind == .campusRequest ? "Requester" : "Darter", value: item.person.name)
                            Divider().padding(.leading, 50)
                        }
                        DetailRow(icon: "mappin.and.ellipse", label: "Pickup", value: item.pickup)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "location.fill", label: "Drop-off", value: item.destination)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "clock.fill", label: item.kind == .friendRun ? "Cutoff" : "Timing", value: item.timing)
                    }
                    .padding(.horizontal, 16)
                    .dartSurface()

                    if let budget = item.merchandiseBudget {
                        MoneyCard(label: "Item budget", amount: budget, emphasized: false)
                    }

                    if store.isLive, item.backend != nil {
                        RequestChatCard(item: item)
                    }

                    RouteMapCard(item: item)
                }
                .padding(DartTheme.pageInset)
                .padding(.bottom, 20)
            }
            .background(DartBackdrop())
            .navigationTitle(isSpotOrder ? "Order" : "Details")
            .toolbar {
                if store.isLive, item.person.id != store.userID {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showSafetyActions = true } label: {
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
            .dartDialog(isPresented: $showSafetyActions) {
                SafetyActionCard(name: item.person.name) {
                    showSafetyActions = false
                    showReport = true
                } onBlock: {
                    showSafetyActions = false
                    confirmBlock = true
                } onCancel: {
                    showSafetyActions = false
                }
            }
            .dartDialog(isPresented: $showReport) {
                ReportPromptCard(name: item.person.name, details: $reportDetails) {
                    let details = reportDetails.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !details.isEmpty else { return }
                    showReport = false
                    Task {
                        if await store.reportUser(item.person.id, item: item, category: "other", details: details) {
                            reportDetails = ""
                        }
                    }
                } onCancel: {
                    showReport = false
                    reportDetails = ""
                }
            }
            .dartDialog(isPresented: $confirmBlock) {
                DartAlertCard(symbol: "hand.raised.fill", title: "Block \(item.person.name)?",
                              message: "You will no longer see each other’s requests or runs. Blocking does not submit a report.",
                              primaryTitle: "Block account", primaryIsDestructive: true,
                              primaryAction: {
                                  confirmBlock = false
                                  Task { if await store.blockUser(item.person.id) { dismiss() } }
                              }, secondaryTitle: "Cancel", secondaryAction: { confirmBlock = false })
            }
            .dartDialog(isPresented: $showUpcoming) {
                DartAlertCard(symbol: "person.crop.circle.badge.plus", title: "Sign in to continue",
                              message: store.isConfigured
                                ? "Sign in from Account to accept orders and track deliveries."
                                : "This build has no backend configured, so actions are shown for preview only.",
                              primaryTitle: "Got it") {
                    showUpcoming = false
                }
            }
        }
        .macSheetSize()
    }

    /// Orders use the eatery as the title; the generated "Pick up X's order…" sentence only repeats
    /// the rows below, so it's shown only for runs and other free-form items.
    private var isSpotOrder: Bool { item.kind == .campusRequest && item.pickupSpot != nil }

    private var detailHero: some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                if let spot = item.pickupSpot {
                    SpotBadge(spot: spot, size: 56)
                } else {
                    DartIconTile(symbol: itemSymbol, size: 56, highlighted: true)
                }
            }
            .scaleEffect(appeared ? 1 : 0.75)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kindLabel.uppercased())
                    .font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.muted)
                Text(isSpotOrder ? item.pickupSpot!.name : item.title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(DartTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !isSpotOrder {
                    Text(item.detail).font(.subheadline).foregroundStyle(DartTheme.muted)
                }
            }
            Spacer(minLength: 4)
            if let reward = item.reward {
                Text("$\(reward)")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(DartTheme.limeInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DartTheme.lime, in: Capsule())
                    .accessibilityLabel("$\(reward) reward")
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
    }

    private var itemSymbol: String {
        if let spot = item.pickupSpot { return spot.symbol }
        return switch item.kind {
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
    @EnvironmentObject private var state: AppState
    let item: DartItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("STATUS").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.muted)
                    Text(item.status.rawValue).font(.title3.weight(.heavy)).foregroundStyle(DartTheme.text)
                }
                Spacer()
                Image(systemName: item.status.icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DartTheme.limeInk)
                    .frame(width: 48, height: 48)
                    .background(DartTheme.surface, in: Circle())
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
        .background(DartTheme.limeWash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DartTheme.limeDeep.opacity(0.22)))
        .accessibilityElement(children: .combine)
    }

    private var nextStep: String {
        // Preview items have no backend row, so fall back to the side of the app you're on.
        let isRequester = item.backend.map { $0.role == .owner } ?? (state.role != .darter)
        guard !isRequester else { return item.status.requesterNextStep }
        return switch item.status {
        case .waiting: "Accept it and pick it up at \(item.pickupSpot?.name ?? item.pickup)."
        case .accepted: "Head to \(item.pickupSpot?.name ?? item.pickup) for pickup."
        case .pickingUp: "Grab the order, then tap “I have the order”."
        case .onTheWay: "Bring it to \(item.destination)."
        case .delivered: "Waiting for the requester to confirm. It completes on its own after 24 hours."
        case .completed: "Delivered. Nice work."
        case .cancelled: "This order was cancelled."
        case .expired: "This order expired."
        }
    }
}

private struct SafetyActionCard: View {
    let name: String
    let onReport: () -> Void
    let onBlock: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DartIconTile(symbol: "shield.lefthalf.filled", size: 58, highlighted: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Safety options").font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                Text("Choose what you need for your interaction with \(name).")
                    .font(.subheadline).foregroundStyle(DartTheme.muted)
            }
            action("Report privately", "exclamationmark.bubble.fill", DartTheme.text, onReport)
            action("Block account", "hand.raised.fill", DartTheme.danger, onBlock)
            Button("Cancel", action: onCancel).font(.headline).foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
    }

    private func action(_ title: String, _ symbol: String, _ color: Color, _ handler: @escaping () -> Void) -> some View {
        Button(action: handler) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.headline).foregroundStyle(color).frame(width: 42, height: 42)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                Text(title).font(.headline).foregroundStyle(color)
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(color)
            }
            .padding(12)
            .background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct ReportPromptCard: View {
    let name: String
    @Binding var details: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DartIconTile(symbol: "exclamationmark.bubble.fill", size: 56, highlighted: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Report \(name)").font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                Text("Reports are private and sent to Dart’s safety review queue. Call local emergency services for immediate danger.")
                    .font(.subheadline).foregroundStyle(DartTheme.muted)
            }
            DartField(label: "What happened?") {
                TextField("Share the important details", text: $details, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(3...6)
            }
            Button(action: onSubmit) { PrimaryButtonLabel(title: "Submit private report", icon: "paperplane.fill") }
                .buttonStyle(PressableStyle())
                .disabled(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", action: onCancel).font(.headline).foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
    }
}

private struct RunChoiceCard: View {
    let runs: [DartItem]
    let onRun: (UUID?) -> Void
    let onDedicatedTrip: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DartIconTile(symbol: "point.topleft.down.to.point.bottomright.curvepath", size: 56, highlighted: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("How are you helping?").font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                Text("Attach this request to a route you already shared or make a dedicated trip.")
                    .font(.subheadline).foregroundStyle(DartTheme.muted)
            }
            ForEach(runs) { run in
                Button { onRun(run.backend?.id) } label: {
                    HStack(spacing: 12) {
                        DartIconTile(symbol: "cart.fill", size: 42)
                        Text(run.title).font(.headline).foregroundStyle(DartTheme.text).lineLimit(2)
                        Spacer()
                        Image(systemName: "arrow.right").foregroundStyle(DartTheme.limeInk)
                    }
                    .padding(12).background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 17))
                }
                .buttonStyle(PressableStyle())
            }
            Button(action: onDedicatedTrip) { PrimaryButtonLabel(title: "Make a dedicated trip", icon: "figure.walk") }
                .buttonStyle(PressableStyle())
            Button("Cancel", action: onCancel).font(.headline).foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
    }
}

private struct AskRunnerCard: View {
    let isFriendRun: Bool
    let reward: Int
    let pickup: String
    @Binding var title: String
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            DartIconTile(symbol: isFriendRun ? "cart.badge.plus" : "bag.badge.plus", size: 56, highlighted: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(isFriendRun ? "Add to the list" : "Ask them to grab your order?")
                    .font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                Text(isFriendRun ? "Friend runs are free."
                     : "They’ll pick up your Grubhub order at \(pickup) on the way back. The $\(reward) reward goes to them.")
                    .font(.subheadline).foregroundStyle(DartTheme.muted)
            }
            if isFriendRun {
                DartField(label: "Item") { TextField("e.g. my Grubhub order", text: $title).textFieldStyle(.plain) }
            }
            Button(action: onSend) { PrimaryButtonLabel(title: "Send request", icon: "paperplane.fill") }
                .buttonStyle(PressableStyle())
                .disabled(isFriendRun && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", action: onCancel).font(.headline).foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
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
    @State private var matches: [(RequestMatch, DartItem)] = []

    private var ref: BackendRef { item.backend! }

    var body: some View {
        VStack(spacing: 12) {
            switch (ref.source, ref.role) {
            case (.request, .viewer):
                if item.status == .waiting {
                    primary(item.reward.map { "Accept · earn $\($0)" } ?? "Accept order", icon: "hand.raised.fill") {
                        if store.myActiveRuns.isEmpty { _ = await store.accept(item) } else { chooseRun = true }
                    }
                }
            case (.request, .helper):
                if let next = item.status.nextHelperStep {
                    primary(next.helperActionTitle, icon: next.icon) {
                        _ = await store.advance(item, to: next)
                    }
                }
                if [.accepted, .pickingUp].contains(item.status) {
                    secondary("Release to someone else", role: .destructive) { await finish(store.release(item)) }
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
                primary(item.kind == .friendRun ? "Add to the shopping list" : "Ask \(item.person.name.split(separator: " ").first ?? "them") to grab my order",
                        icon: item.kind == .friendRun ? "cart.badge.plus" : "bag.badge.plus") {
                    askRunner = true
                }
            }
        }
        .disabled(working)
        .dartDialog(isPresented: $chooseRun) {
            RunChoiceCard(runs: store.myActiveRuns) { runID in
                chooseRun = false
                Task { _ = await store.accept(item, onRun: runID) }
            } onDedicatedTrip: {
                chooseRun = false
                Task { _ = await store.accept(item) }
            } onCancel: {
                chooseRun = false
            }
        }
        .dartDialog(isPresented: $askRunner) {
            AskRunnerCard(isFriendRun: item.kind == .friendRun, reward: item.reward ?? 0,
                          pickup: item.pickupSpot?.name ?? item.pickup, title: $askTitle) {
                askRunner = false
                Task { await sendAsk() }
            } onCancel: {
                askRunner = false
            }
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
        let typed = askTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.kind == .friendRun ? typed : (item.pickupSpot?.requestTitle ?? "Grubhub order from \(item.pickup)")
        guard !title.isEmpty else { return }
        working = true
        defer { working = false }
        let ok: Bool
        if item.kind == .friendRun, let groupID = ref.groupID {
            ok = await store.addListItem(title, groupID: groupID, runID: ref.id)
        } else {
            ok = await store.requestFromRun(item, title: title, budgetDollars: nil)
        }
        askTitle = ""
        await finish(ok)
    }
}
