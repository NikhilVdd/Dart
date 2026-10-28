import SwiftUI

// Live create forms, shown when signed in. Both end on a "what's already happening" screen:
// a new request lists runs that could carry it; a new run lists requests that fit the trip.

/// Where a request or run is shared.
private enum Audience: Hashable {
    case campus
    case group(UUID)
}

/// One screen: pick the eatery your Grubhub order is at, confirm the drop-off (prefilled with
/// home), and send. Timing and reward default to the last values used.
struct RequestFormView: View {
    @EnvironmentObject private var store: DartStore
    let onFinish: () -> Void

    @AppStorage("dart.request.minutes") private var minutes = 30
    @AppStorage("dart.request.reward") private var reward = 3
    @State private var spot: PickupSpot?
    @State private var destinationID: UUID?
    @State private var working = false
    @State private var result: [(RunMatch, DartItem)]?
    @State private var showErrors = false

    private static let minuteChoices = [30, 60, 120]
    private static let rewardChoices = [2, 3, 5, 8]

    init(initialSpot: PickupSpot? = nil, onFinish: @escaping () -> Void) {
        _spot = State(initialValue: initialSpot)
        self.onFinish = onFinish
    }

    var body: some View {
        Group {
            if let result {
                MatchResultsView(
                    title: "Request sent",
                    subtitle: result.isEmpty
                        ? "Darters near \(spot?.name ?? "campus") can see it now. You’ll get a notification the moment someone accepts."
                        : "These darters are already heading out and can bring it with a small detour. Your request shows up in each of their lists.",
                    rows: result.map { match, run in
                        MatchRow(id: match.runID, title: run.title, detail: "+\(match.detourMinutes) min · \(run.destination)",
                                 amount: DartStore.dollars(match.feeCents), action: nil)
                    },
                    onDone: onFinish
                )
            } else {
                form
            }
        }
        .navigationTitle("Get my order")
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Where’s your order?").font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
                    Text("Pick the eatery your Grubhub order is at. A darter brings it to you.")
                        .font(.subheadline).foregroundStyle(DartTheme.muted)
                }

                VStack(alignment: .leading, spacing: 8) {
                    PickupSpotGrid(selection: spot) { spot = $0 }
                    if showErrors && spot == nil {
                        Label("Choose where your order is", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(DartTheme.danger)
                    }
                }

                DartField(label: "Deliver to", error: showErrors && destinationID == nil ? "Choose where to bring it" : nil) {
                    PlaceField(title: "Drop-off", selection: $destinationID, filter: .destinations)
                }

                ChoiceRow(title: "When do you need it?", values: Self.minuteChoices, selection: $minutes) {
                    $0 < 60 ? "\($0) min" : "\($0 / 60) hr"
                }

                VStack(alignment: .leading, spacing: 8) {
                    ChoiceRow(title: "Darter reward", values: Self.rewardChoices, selection: $reward) { "$\($0)" }
                    Text("Your food is already paid for on Grubhub. The reward goes to your darter.")
                        .font(.caption).foregroundStyle(DartTheme.muted)
                }

                Button {
                    guard spot != nil, destinationID != nil else { showErrors = true; return }
                    showErrors = false
                    Task { await submit() }
                } label: {
                    if working {
                        HStack(spacing: 10) {
                            ProgressView().tint(DartTheme.limeInk)
                            Text("Sending…").font(.headline)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .foregroundStyle(DartTheme.limeInk)
                        .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                    } else {
                        PrimaryButtonLabel(title: spot.map { "Request pickup from \($0.shortName)" } ?? "Request pickup",
                                           icon: "paperplane.fill")
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(working)
            }
            .padding(DartTheme.pageInset)
        }
        .background(DartBackdrop())
        .onAppear {
            destinationID = destinationID ?? store.profile?.homePlaceID
            if !Self.minuteChoices.contains(minutes) { minutes = 30 }
            if !Self.rewardChoices.contains(reward) { reward = 3 }
        }
    }

    private func submit() async {
        guard let spot, let destination = store.places.first(where: { $0.id == destinationID }) else { return }
        working = true
        defer { working = false }
        guard let pickup = await store.place(for: spot) else { return }
        let request = NewRequest(
            groupID: nil,
            title: spot.requestTitle,
            details: "",
            pickupPlaceID: pickup.id,
            pickupLabel: spot.pickupLabel,
            destinationPlaceID: destination.id,
            destinationLabel: destination.label,
            deliverBy: Date().addingTimeInterval(TimeInterval(minutes * 60)),
            rewardCents: reward * 100,
            merchandiseBudgetCents: nil
        )
        if let posted = await store.postRequest(request) {
            result = posted.matches
        }
    }
}

/// A row of equal-width option chips, e.g. timing or reward.
private struct ChoiceRow: View {
    let title: String
    let values: [Int]
    @Binding var selection: Int
    let label: (Int) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(DartTheme.muted)
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { selection = value } label: {
                        Text(label(value))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selection == value ? DartTheme.limeInk : DartTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(selection == value ? DartTheme.lime : DartTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selection == value ? Color.clear : DartTheme.line))
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: selection)
        }
    }
}

struct RunFormView: View {
    @EnvironmentObject private var store: DartStore
    let onFinish: () -> Void

    @State private var spot: PickupSpot?
    @State private var destinationID: UUID?
    @State private var note = ""
    @State private var minutes = 30
    @State private var fee = 5
    @State private var maxDetour = 10
    @State private var audience: Audience = .campus
    @State private var working = false
    @State private var runID: UUID?
    @State private var result: [(RequestMatch, DartItem)]?
    @State private var accepted: Set<UUID> = []
    @State private var showErrors = false

    private var isFriendRun: Bool {
        guard case .group(let id) = audience else { return false }
        return store.groups.first { $0.id == id }?.kind == .friends
    }

    var body: some View {
        Group {
            if let result, let runID {
                MatchResultsView(
                    title: "Run announced",
                    subtitle: result.isEmpty
                        ? "No orders fit this trip yet. New ones will show up on the run’s detail page."
                        : "These orders fit your trip. Accept any you want to carry.",
                    rows: result.map { match, request in
                        MatchRow(id: match.requestID, title: request.title,
                                 detail: [match.detourMinutes.map { "+\($0) min" }, request.destination].compactMap { $0 }.joined(separator: " · "),
                                 amount: DartStore.dollars(match.rewardCents),
                                 action: accepted.contains(match.requestID) ? nil : {
                                     if await store.accept(request, onRun: runID) { accepted.insert(match.requestID) }
                                 })
                    },
                    onDone: onFinish
                )
            } else {
                form
            }
        }
        .navigationTitle("Announce a run")
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Heading to an eatery?")
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(DartTheme.text)
                        Text("Carry a few Grubhub orders back with you and earn on the way.")
                            .font(.subheadline).foregroundStyle(DartTheme.muted)
                    }
                    Spacer()
                    DartIconTile(symbol: "figure.walk", size: 62, highlighted: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("GOING TO").font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(DartTheme.muted)
                    PickupSpotGrid(selection: spot) { spot = $0 }
                    if showErrors && spot == nil {
                        Label("Choose where you’re going", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(DartTheme.danger)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    DartField(label: "Heading back to", error: showErrors && destinationID == nil ? "Choose a destination" : nil) {
                        PlaceField(title: "Destination", selection: $destinationID, filter: .destinations)
                    }
                    DartField(label: "Optional note") {
                        TextField("e.g. I can carry three orders", text: $note).textFieldStyle(.plain)
                    }
                }
                .padding(18)
                .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.line))

                VStack(alignment: .leading, spacing: 16) {
                    if DartFeatures.groups {
                        Text("WHO CAN ASK?").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.muted)
                        AudiencePicker(audience: $audience, groups: store.groups)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
                    }
                    Text("REQUEST WINDOW").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([10, 20, 30, 45, 60, 90], id: \.self) { value in
                                Button { minutes = value } label: {
                                    Text("\(value) min").font(.caption.weight(.bold))
                                        .foregroundStyle(minutes == value ? DartTheme.limeInk : DartTheme.muted)
                                        .padding(.horizontal, 13).frame(height: 40)
                                        .background(minutes == value ? DartTheme.lime : DartTheme.surfaceRaised, in: Capsule())
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                    if !isFriendRun {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("REWARD PER REQUEST").font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(DartTheme.muted)
                                Text("$\(fee)").font(.title.weight(.heavy)).foregroundStyle(DartTheme.text)
                            }
                            Spacer()
                            DartNumberStepper(title: "Reward per request", value: $fee, range: 0...20)
                        }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MAXIMUM DETOUR").font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(DartTheme.muted)
                            Text("\(maxDetour) minutes").font(.headline).foregroundStyle(DartTheme.text)
                        }
                        Spacer()
                        DartNumberStepper(title: "Maximum detour", value: $maxDetour, range: 2...30)
                    }
                }
                .padding(18)
                .background(DartTheme.limeWash, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.limeDeep.opacity(0.25)))

                Text(isFriendRun
                     ? "Friend runs are always free. Your group can ask you to grab their order."
                     : "Only orders within your detour limit are suggested. You approve each one.")
                    .font(.caption).foregroundStyle(DartTheme.muted)

                Button {
                    guard spot != nil, destinationID != nil else { showErrors = true; return }
                    Task { await submit() }
                } label: {
                    if working {
                        HStack { ProgressView().tint(DartTheme.limeInk); Text("Sharing run…").font(.headline) }
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .foregroundStyle(DartTheme.limeInk)
                            .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                    } else {
                        PrimaryButtonLabel(title: spot.map { "Share run to \($0.shortName)" } ?? "Share run", icon: "paperplane.fill")
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(working)
            }
            .padding(DartTheme.pageInset)
        }
        .background(DartBackdrop())
        .onAppear { destinationID = destinationID ?? store.profile?.homePlaceID }
    }

    private func submit() async {
        guard let spot, let destination = store.places.first(where: { $0.id == destinationID }) else { return }
        working = true
        defer { working = false }
        guard let shop = await store.place(for: spot) else { return }
        let groupKind = audience.groupID.flatMap { id in store.groups.first { $0.id == id }?.kind }
        let run = NewRun(
            groupID: audience.groupID,
            audience: groupKind == .friends ? "friends" : (groupKind == .building ? "building" : "campus"),
            storePlaceID: shop.id,
            storeLabel: spot.pickupLabel,
            destinationPlaceID: destination.id,
            destinationLabel: destination.label,
            note: note.isEmpty ? nil : note,
            closesAt: Date().addingTimeInterval(TimeInterval(minutes * 60)),
            feeCents: isFriendRun ? 0 : fee * 100,
            maxAddedMinutes: maxDetour
        )
        if let announced = await store.announceRun(run) {
            runID = announced.run.id
            result = announced.matches
        }
    }
}

// MARK: - Shared pieces

private extension Audience {
    var groupID: UUID? {
        if case .group(let id) = self { return id }
        return nil
    }
}

private struct AudiencePicker: View {
    @Binding var audience: Audience
    let groups: [DartGroup]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                choice("Everyone", symbol: "graduationcap.fill", value: .campus)
                ForEach(groups) { group in
                    choice(group.name, symbol: group.kind == .friends ? "person.2.fill" : "building.2.fill",
                           value: .group(group.id))
                }
            }
            .padding(.vertical, 5)
        }
    }

    private func choice(_ title: String, symbol: String, value: Audience) -> some View {
        let selected = audience == value
        return Button { audience = value } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? DartTheme.limeInk : DartTheme.text)
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .background(selected ? DartTheme.lime : DartTheme.surface, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : DartTheme.line))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct MatchRow: Identifiable {
    let id: UUID
    let title: String
    let detail: String
    let amount: Int
    let action: (() async -> Void)?
}

private struct MatchResultsView: View {
    let title: String
    let subtitle: String
    let rows: [MatchRow]
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(DartTheme.gold)
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
                if !rows.isEmpty {
                    SectionHeading(title: "Already happening nearby")
                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title).font(.headline)
                                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if row.amount > 0 { Text("$\(row.amount)").font(.headline).foregroundStyle(DartTheme.gold) }
                            if let action = row.action {
                                Button("Accept") { Task { await action() } }
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(DartTheme.limeInk)
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 40)
                                    .background(DartTheme.lime, in: Capsule())
                                    .buttonStyle(PressableStyle())
                            }
                        }
                        .padding(16)
                        .dartSurface()
                    }
                }
                Button(action: onDone) { PrimaryButtonLabel(title: "Done", icon: "checkmark") }
                    .buttonStyle(PressableStyle())
            }
            .padding(DartTheme.pageInset)
        }
        .background(DartBackdrop())
    }
}
