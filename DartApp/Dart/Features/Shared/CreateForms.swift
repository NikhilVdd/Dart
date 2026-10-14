import SwiftUI

// Live create forms, shown when signed in. Both end on a "what's already happening" screen:
// a new request lists runs that could carry it; a new run lists requests that fit the trip.

/// Where a request or run is shared.
private enum Audience: Hashable {
    case campus
    case group(UUID)
}

struct RequestFormView: View {
    @EnvironmentObject private var store: GrabStore
    let onFinish: () -> Void

    @State private var title = ""
    @State private var details = ""
    @State private var pickupID: UUID?          // nil = any store
    @State private var destinationID: UUID?
    @State private var minutes = 60
    @State private var reward = 6
    @State private var budget = ""
    @State private var audience: Audience = .campus
    @State private var working = false
    @State private var result: [(RunMatch, GrabItem)]?

    var body: some View {
        Group {
            if let result {
                MatchResultsView(
                    title: "Request posted",
                    subtitle: result.isEmpty
                        ? "Nobody’s trip fits yet. Your request is visible to helpers nearby."
                        : "These trips are already happening and can carry it with a small detour. It appears in each runner’s list of requests that fit.",
                    rows: result.map { match, run in
                        MatchRow(id: match.runID, title: run.title, detail: "+\(match.detourMinutes) min · \(run.destination)",
                                 amount: GrabStore.dollars(match.feeCents), action: nil)
                    },
                    onDone: onFinish
                )
            } else {
                form
            }
        }
        .navigationTitle("New request")
    }

    private var form: some View {
        Form {
            Section("What do you need?") {
                TextField("e.g. Blender under $50", text: $title)
                TextField("Details for the helper", text: $details, axis: .vertical).lineLimit(2...5)
            }
            Section {
                PlaceField(title: "Pick up from", selection: $pickupID, filter: .any, allowsAnyStore: true)
                PlaceField(title: "Deliver to", selection: $destinationID, filter: .destinations)
                Picker("Needed within", selection: $minutes) {
                    ForEach([15, 30, 60, 120, 240], id: \.self) { Text($0 < 60 ? "\($0) min" : "\($0 / 60) hr").tag($0) }
                }
            } header: {
                Text("Where and when")
            } footer: {
                Text("“Any store” lets someone already shopping nearby pick it up. Search to add a place that isn’t listed.")
            }
            Section {
                Stepper("Helper reward: $\(reward)", value: $reward, in: 0...50)
                TextField("Item budget in dollars (optional)", text: $budget)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                AudiencePicker(audience: $audience, groups: store.groups)
            } header: {
                Text("Payment")
            } footer: {
                Text("The reward goes to your helper; the item budget is separate. Payments are recorded, not charged, in this build.")
            }
            Section {
                Button { Task { await submit() } } label: {
                    if working { ProgressView().frame(maxWidth: .infinity) } else { Text("Post request").frame(maxWidth: .infinity).bold() }
                }
                .disabled(working || title.trimmingCharacters(in: .whitespaces).isEmpty || destinationID == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GrabBackdrop())
        .onAppear { destinationID = destinationID ?? store.profile?.homePlaceID }
    }

    private func submit() async {
        guard let destination = store.places.first(where: { $0.id == destinationID }) else { return }
        let pickup = store.places.first { $0.id == pickupID }
        working = true
        defer { working = false }
        let request = NewRequest(
            groupID: audience.groupID,
            title: title.trimmingCharacters(in: .whitespaces),
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            pickupPlaceID: pickup?.id,
            pickupLabel: pickup?.label ?? "Any store",
            destinationPlaceID: destination.id,
            destinationLabel: destination.label,
            deliverBy: Date().addingTimeInterval(TimeInterval(minutes * 60)),
            rewardCents: reward * 100,
            merchandiseBudgetCents: Int(budget.filter(\.isNumber)).map { $0 * 100 }
        )
        if let posted = await store.postRequest(request) { result = posted.matches }
    }
}

struct RunFormView: View {
    @EnvironmentObject private var store: GrabStore
    let onFinish: () -> Void

    @State private var storeID: UUID?
    @State private var destinationID: UUID?
    @State private var note = ""
    @State private var minutes = 30
    @State private var fee = 5
    @State private var maxDetour = 10
    @State private var audience: Audience = .campus
    @State private var working = false
    @State private var runID: UUID?
    @State private var result: [(RequestMatch, GrabItem)]?
    @State private var accepted: Set<UUID> = []

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
                        ? "No open requests fit this trip yet. New ones will show up on the run’s detail page."
                        : "These requests fit your trip. Accept any you want to carry.",
                    rows: result.map { match, request in
                        MatchRow(id: match.requestID, title: request.title,
                                 detail: [match.detourMinutes.map { "+\($0) min" }, request.destination].compactMap { $0 }.joined(separator: " · "),
                                 amount: GrabStore.dollars(match.rewardCents),
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
        Form {
            Section("Where are you going?") {
                PlaceField(title: "Store", selection: $storeID, filter: .stores)
                PlaceField(title: "Heading back to", selection: $destinationID, filter: .destinations)
                TextField("Note (optional)", text: $note)
            }
            Section {
                AudiencePicker(audience: $audience, groups: store.groups)
                Picker("Taking requests for", selection: $minutes) {
                    ForEach([10, 20, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
                if !isFriendRun {
                    Stepper("Fee per request: $\(fee)", value: $fee, in: 0...20)
                }
                Stepper("Max detour: \(maxDetour) min", value: $maxDetour, in: 2...30)
            } header: {
                Text("Who can ask")
            } footer: {
                Text(isFriendRun
                     ? "Runs for friends are always free."
                     : "Only requests that add at most \(maxDetour) minutes to your trip are suggested.")
            }
            Section {
                Button { Task { await submit() } } label: {
                    if working { ProgressView().frame(maxWidth: .infinity) } else { Text("Announce run").frame(maxWidth: .infinity).bold() }
                }
                .disabled(working || storeID == nil || destinationID == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GrabBackdrop())
        .onAppear { destinationID = destinationID ?? store.profile?.homePlaceID }
    }

    private func submit() async {
        guard let shop = store.places.first(where: { $0.id == storeID }),
              let destination = store.places.first(where: { $0.id == destinationID }) else { return }
        working = true
        defer { working = false }
        let groupKind = audience.groupID.flatMap { id in store.groups.first { $0.id == id }?.kind }
        let run = NewRun(
            groupID: audience.groupID,
            audience: groupKind == .friends ? "friends" : (groupKind == .building ? "building" : "campus"),
            storePlaceID: shop.id,
            storeLabel: shop.label,
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
    let groups: [GrabGroup]

    var body: some View {
        Picker("Visible to", selection: $audience) {
            Text("Everyone on campus").tag(Audience.campus)
            ForEach(groups) { group in Text(group.name).tag(Audience.group(group.id)) }
        }
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
                Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(GrabTheme.gold)
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
                            if row.amount > 0 { Text("$\(row.amount)").font(.headline).foregroundStyle(GrabTheme.gold) }
                            if let action = row.action {
                                Button("Accept") { Task { await action() } }.buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(16)
                        .grabGlass()
                    }
                }
                Button(action: onDone) { PrimaryButtonLabel(title: "Done", icon: "checkmark") }
                    .buttonStyle(PressableStyle())
            }
            .padding(GrabTheme.pageInset)
        }
        .background(GrabBackdrop())
    }
}
