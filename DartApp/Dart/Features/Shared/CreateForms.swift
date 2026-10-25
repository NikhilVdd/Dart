import SwiftUI

// Live create forms, shown when signed in. Both end on a "what's already happening" screen:
// a new request lists runs that could carry it; a new run lists requests that fit the trip.

/// Where a request or run is shared.
private enum Audience: Hashable {
    case campus
    case group(UUID)
}

private enum RequestCategory: String, CaseIterable, Identifiable {
    case food = "Food"
    case groceries = "Groceries"
    case errand = "Errand"
    case pickup = "Pickup"
    case other = "Other"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "basket.fill"
        case .errand: "figure.walk.motion"
        case .pickup: "shippingbox.fill"
        case .other: "sparkles"
        }
    }
    var prompt: String {
        switch self {
        case .food: "e.g. Pick up a burrito from Chipotle"
        case .groceries: "e.g. Milk and bananas from Trader Joe’s"
        case .errand: "e.g. Return a library book"
        case .pickup: "e.g. Grab my package from the mailroom"
        case .other: "What can another student help with?"
        }
    }
}

struct RequestFormView: View {
    @EnvironmentObject private var store: DartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onFinish: () -> Void

    @AppStorage("dart.requestDraft.title") private var title = ""
    @AppStorage("dart.requestDraft.details") private var details = ""
    @AppStorage("dart.requestDraft.category") private var categoryRaw = RequestCategory.groceries.rawValue
    @AppStorage("dart.requestDraft.minutes") private var minutes = 60
    @AppStorage("dart.requestDraft.reward") private var reward = 6
    @AppStorage("dart.requestDraft.budget") private var budget = ""
    @State private var pickupID: UUID?          // nil = any store
    @State private var destinationID: UUID?
    @State private var audience: Audience = .campus
    @State private var working = false
    @State private var result: [(RunMatch, DartItem)]?
    @State private var step = 0
    @State private var showErrors = false

    private var category: RequestCategory {
        get { RequestCategory(rawValue: categoryRaw) ?? .groceries }
        nonmutating set { categoryRaw = newValue.rawValue }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canContinue: Bool {
        switch step {
        case 0: !trimmedTitle.isEmpty
        case 1: destinationID != nil
        default: !trimmedTitle.isEmpty && destinationID != nil
        }
    }

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
                                 amount: DartStore.dollars(match.feeCents), action: nil)
                    },
                    onDone: onFinish
                )
            } else {
                form
            }
        }
        .navigationTitle("Post a Dart")
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                DartProgressRail(current: step, total: 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(stepTitle).font(.largeTitle.weight(.heavy)).foregroundStyle(DartTheme.text)
                    Text(stepSubtitle).font(.subheadline).foregroundStyle(DartTheme.muted)
                }
                Group {
                    switch step {
                    case 0: detailsStep
                    case 1: logisticsStep
                    default: reviewStep
                    }
                }
                .id(step)
                .transition(reduceMotion ? .identity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                navigationButtons
            }
            .padding(DartTheme.pageInset)
        }
        .background(DartBackdrop())
        .onAppear { destinationID = destinationID ?? store.profile?.homePlaceID }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: step)
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose a category").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(RequestCategory.allCases) { item in
                    Button {
                        category = item
                    } label: {
                        HStack(spacing: 10) {
                            DartIconTile(symbol: item.symbol, size: 42, highlighted: category == item)
                            Text(item.rawValue).font(.subheadline.weight(.bold)).foregroundStyle(DartTheme.text)
                            Spacer(minLength: 0)
                        }
                        .padding(11)
                        .background(category == item ? DartTheme.lime.opacity(0.22) : DartTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(category == item ? DartTheme.limeSoft : DartTheme.line, lineWidth: category == item ? 2 : 1))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            DartField(label: "What do you need?", error: showErrors && trimmedTitle.isEmpty ? "Add a short, specific request" : nil) {
                TextField(category.prompt, text: $title)
                    .textFieldStyle(.plain)
            }
            DartField(label: "Helpful details") {
                TextField("Brand, size, color, pickup instructions…", text: $details, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...5)
            }
            Label("Draft saves automatically on this device", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium)).foregroundStyle(DartTheme.muted)
        }
    }

    private var logisticsStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            DartField(label: "Pick up from") {
                PlaceField(title: "Pickup", selection: $pickupID, filter: .any, allowsAnyStore: true)
            }
            DartField(label: "Deliver to", error: showErrors && destinationID == nil ? "Choose a destination" : nil) {
                PlaceField(title: "Destination", selection: $destinationID, filter: .destinations)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("WHEN DO YOU NEED IT?").font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(DartTheme.muted)
                HStack(spacing: 8) {
                    ForEach([30, 60, 120, 240], id: \.self) { value in
                        Button { minutes = value } label: {
                            Text(value < 60 ? "\(value)m" : "\(value / 60)h")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(minutes == value ? DartTheme.limeInk : DartTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(minutes == value ? DartTheme.lime : DartTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(minutes == value ? Color.clear : DartTheme.line))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("WHO CAN SEE IT?").font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(DartTheme.muted)
                AudiencePicker(audience: $audience, groups: store.groups)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(DartTheme.line))
            }
            Text("Choosing “Any store” helps Dart match you with someone already shopping nearby.")
                .font(.caption).foregroundStyle(DartTheme.muted)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    DartIconTile(symbol: category.symbol, size: 54, highlighted: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.rawValue.uppercased()).font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(DartTheme.muted)
                        Text(trimmedTitle.isEmpty ? "Your request" : trimmedTitle).font(.title3.weight(.bold)).foregroundStyle(DartTheme.text)
                    }
                    Spacer()
                    Button("Edit") { step = 0 }.font(.subheadline.weight(.bold)).foregroundStyle(DartTheme.limeInk)
                }
                reviewLine("mappin.and.ellipse", pickupLabel)
                reviewLine("location.fill", destinationLabel)
                reviewLine("clock.fill", minutes < 60 ? "Within \(minutes) minutes" : "Within \(minutes / 60) hour\(minutes == 60 ? "" : "s")")
            }
            .padding(18)
            .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.line))

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("HELPER REWARD").font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(DartTheme.muted)
                        Text("$\(reward)").font(.system(size: 36, weight: .heavy, design: .rounded)).foregroundStyle(DartTheme.text)
                    }
                    Spacer()
                    DartNumberStepper(title: "Helper reward", value: $reward, range: 0...50)
                }
                DartField(label: "Merchandise budget (optional)") {
                    TextField("$0", text: $budget)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Text("The reward and merchandise budget stay separate. Charges remain disabled until the server enables payments.")
                    .font(.caption).foregroundStyle(DartTheme.muted)
            }
            .padding(18)
            .background(DartTheme.lime.opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.limeSoft.opacity(0.45)))
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button { step -= 1; showErrors = false } label: {
                    SecondaryButtonLabel(title: "Back", icon: "arrow.left")
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: 125)
            }
            Button {
                guard canContinue else { showErrors = true; return }
                showErrors = false
                if step < 2 { step += 1 } else { Task { await submit() } }
            } label: {
                if working {
                    HStack(spacing: 10) {
                        ProgressView().tint(DartTheme.limeInk)
                        Text("Posting Dart…").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .foregroundStyle(DartTheme.limeInk)
                    .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                } else {
                    PrimaryButtonLabel(title: step == 2 ? "Post Dart" : "Continue", icon: step == 2 ? "paperplane.fill" : "arrow.right")
                }
            }
            .buttonStyle(PressableStyle())
            .disabled(working)
        }
    }

    private var stepTitle: String {
        switch step { case 0: "What do you need?"; case 1: "Where and when?"; default: "Review your Dart" }
    }

    private var stepSubtitle: String {
        switch step {
        case 0: "Start with the essentials. You can add context without filling a long form."
        case 1: "Dart uses these details to find the most convenient helper."
        default: "Everything looks right? Set the reward and publish."
        }
    }

    private var pickupLabel: String {
        store.places.first(where: { $0.id == pickupID })?.label ?? "Any nearby store"
    }

    private var destinationLabel: String {
        store.places.first(where: { $0.id == destinationID })?.label ?? "Choose a destination"
    }

    private func reviewLine(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.subheadline.weight(.medium)).foregroundStyle(DartTheme.muted)
    }

    private func submit() async {
        guard let destination = store.places.first(where: { $0.id == destinationID }) else { return }
        let pickup = store.places.first { $0.id == pickupID }
        working = true
        defer { working = false }
        let request = NewRequest(
            groupID: audience.groupID,
            title: trimmedTitle,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            pickupPlaceID: pickup?.id,
            pickupLabel: pickup?.label ?? "Any store",
            destinationPlaceID: destination.id,
            destinationLabel: destination.label,
            deliverBy: Date().addingTimeInterval(TimeInterval(minutes * 60)),
            rewardCents: reward * 100,
            merchandiseBudgetCents: Int(budget.filter(\.isNumber)).map { $0 * 100 }
        )
        if let posted = await store.postRequest(request) {
            result = posted.matches
            title = ""
            details = ""
            budget = ""
            categoryRaw = RequestCategory.groceries.rawValue
        }
    }
}

struct RunFormView: View {
    @EnvironmentObject private var store: DartStore
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
                        ? "No open requests fit this trip yet. New ones will show up on the run’s detail page."
                        : "These requests fit your trip. Accept any you want to carry.",
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
                        Text("Share your route")
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(DartTheme.text)
                        Text("Let the right people ask while you’re already out.")
                            .font(.subheadline).foregroundStyle(DartTheme.muted)
                    }
                    Spacer()
                    DartIconTile(symbol: "cart.fill", size: 62, highlighted: true)
                }

                VStack(alignment: .leading, spacing: 16) {
                    DartField(label: "Store", error: showErrors && storeID == nil ? "Choose where you’re going" : nil) {
                        PlaceField(title: "Going to", selection: $storeID, filter: .stores)
                    }
                    DartField(label: "Heading back to", error: showErrors && destinationID == nil ? "Choose a destination" : nil) {
                        PlaceField(title: "Destination", selection: $destinationID, filter: .destinations)
                    }
                    DartField(label: "Optional note") {
                        TextField("e.g. I can carry two small bags", text: $note).textFieldStyle(.plain)
                    }
                }
                .padding(18)
                .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.line))

                VStack(alignment: .leading, spacing: 16) {
                    Text("WHO CAN ASK?").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(DartTheme.muted)
                    AudiencePicker(audience: $audience, groups: store.groups)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
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
                .background(DartTheme.lime.opacity(0.13), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.limeSoft.opacity(0.45)))

                Text(isFriendRun
                     ? "Friend runs are always free. Your group sees the shared shopping list immediately."
                     : "Only requests within your detour limit are suggested. You approve each one.")
                    .font(.caption).foregroundStyle(DartTheme.muted)

                Button {
                    guard storeID != nil, destinationID != nil else { showErrors = true; return }
                    Task { await submit() }
                } label: {
                    if working {
                        HStack { ProgressView().tint(DartTheme.limeInk); Text("Sharing run…").font(.headline) }
                            .frame(maxWidth: .infinity).padding(.vertical, 17)
                            .foregroundStyle(DartTheme.limeInk)
                            .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                    } else {
                        PrimaryButtonLabel(title: "Share store run", icon: "paperplane.fill")
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
