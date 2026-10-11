import Foundation
import Supabase

/// App-wide data source. When Supabase is configured and the user is signed in, it serves live
/// data mapped onto the existing view models; otherwise it serves the Section 1 preview fixtures.
@MainActor
final class GrabStore: ObservableObject {
    enum Phase: Equatable {
        case preview    // no Supabase configuration in this build
        case signedOut  // configured, waiting for sign-in
        case live       // signed in; data comes from Supabase
    }

    @Published private(set) var phase: Phase
    @Published private(set) var isLoading = false
    @Published private(set) var profile: ProfileRecord?
    @Published private(set) var places: [PlaceRow] = []
    @Published private(set) var earnings: EarningsRow?
    @Published private(set) var discoverableGroups: [GrabGroup] = []
    @Published var lastError: String?

    @Published private var runFeed: [GrabItem] = []
    @Published private var myRequestItems: [GrabItem] = []
    @Published private var earnItems: [GrabItem] = []
    @Published private var liveGroups: [GrabGroup] = []
    @Published private var liveActivities: [ActivityRecord] = []
    @Published private var conversations: [UUID: [Message]] = [:]

    let backend: GrabBackend?
    private var myRuns: [RunRow] = []
    private var openConversations: Set<UUID> = []
    private var authTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var channel: RealtimeChannelV2?

    init(config: SupabaseConfig? = SupabaseConfig.load()) {
        backend = config.map(GrabBackend.init)
        phase = backend == nil ? .preview : .signedOut
        if backend != nil { observeAuth() }
    }

    var isLive: Bool { phase == .live }
    var isConfigured: Bool { backend != nil }
    var userID: UUID? { profile?.id ?? backend?.currentUserID }

    // MARK: View-facing data (falls back to preview fixtures)

    func feed(for mode: HomeMode) -> [GrabItem] {
        guard isLive else {
            return mode == .request
                ? [PreviewData.traderJoes, PreviewData.buildingRun, PreviewData.shampoo]
                : [PreviewData.charger, PreviewData.shampoo, PreviewData.buildingRun]
        }
        switch mode {
        case .request: return runFeed + myRequestItems.filter { GrabStatus.active.contains($0.status) }
        case .earn: return earnItems
        }
    }

    func activeItem(for mode: HomeMode) -> GrabItem? {
        guard isLive else { return mode == .request ? PreviewData.shampoo : PreviewData.buildingRun }
        let active = GrabStatus.active
        switch mode {
        case .request:
            return myRequestItems.first { active.contains($0.status) }
        case .earn:
            return liveActivities.first { $0.mode == .helping && active.contains($0.currentStatus) }?.item
                ?? runFeedMine.first
        }
    }

    var groups: [GrabGroup] { isLive ? liveGroups : PreviewData.groups }

    func group(id: UUID) -> GrabGroup? {
        groups.first { $0.id == id } ?? discoverableGroups.first { $0.id == id }
    }

    func activities(for mode: ActivityMode) -> [ActivityRecord] {
        (isLive ? liveActivities : PreviewData.activities).filter { $0.mode == mode }
    }

    func conversation(for group: GrabGroup) -> [Message] {
        isLive ? (conversations[group.id] ?? group.conversation) : group.conversation
    }

    var firstName: String? { profile?.displayName.split(separator: " ").first.map(String.init) }
    var campusName: String? { profile?.campus?.name }
    var buildingName: String? { profile?.homePlace?.name }
    var stores: [PlaceRow] { places.filter(\.isStore) }

    /// Where place searches are centered: your campus, else UC Berkeley.
    var campusCenter: (lat: Double, lng: Double) {
        profile?.campus.map { ($0.lat, $0.lng) } ?? (37.8719, -122.2585)
    }

    /// Adds a place from a map search result and makes it available to the forms immediately.
    func createPlace(_ place: NewPlace) async -> PlaceRow? {
        guard let backend else { return nil }
        do {
            let row = try await backend.createPlace(place)
            if !places.contains(where: { $0.id == row.id }) {
                places.append(row)
                places.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            return row
        } catch {
            report(error)
            return nil
        }
    }

    private var runFeedMine: [GrabItem] {
        myRuns.map { item(from: $0) }
    }

    // MARK: Auth

    func sendCode(to email: String) async -> Bool {
        await perform { try await $0.sendCode(to: email) }
    }

    func verify(email: String, code: String) async -> Bool {
        await perform { try await $0.verify(email: email, code: code) }
    }

    func signOut() async {
        _ = await perform { try await $0.signOut() }
    }

    /// Permanently deletes the account and its data, then returns to the signed-out state.
    func deleteAccount() async -> Bool {
        await perform { try await $0.deleteAccount() }
    }

    func updateDisplayName(_ name: String) async {
        guard let userID else { return }
        _ = await perform { try await $0.updateDisplayName(name, userID: userID) }
        await refresh()
    }

    private func observeAuth() {
        guard let backend else { return }
        authTask = Task { [weak self] in
            for await (event, session) in backend.client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn:
                    if session != nil {
                        if self.phase != .live {
                            self.phase = .live
                            await self.refresh()
                            await self.startRealtime()
                        }
                    } else {
                        self.phase = .signedOut
                    }
                case .signedOut:
                    await self.stopRealtime()
                    self.clear()
                    self.phase = .signedOut
                default:
                    break
                }
            }
        }
    }

    // MARK: Loading

    func refresh() async {
        guard let backend, isLive, let userID = backend.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let profileRow = backend.profile(id: userID)
            async let placeRows = backend.places()
            async let groupRows = backend.groups()
            async let memberRows = backend.members()
            async let runRows = backend.activeRuns()
            async let requestRows = backend.myRequests(userID: userID)
            async let itemRows = backend.listItems()
            async let messageRows = backend.latestMessages()
            async let earningsRow = backend.earnings()

            let profile = try await profileRow
            let home = profile.homePlace
            async let nearbyRows = backend.openRequestsNearby(lat: home?.lat, lng: home?.lng)

            let (places, groups, members, runs, requests, items, messages, earnings, nearby) = try await (
                placeRows, groupRows, memberRows, runRows, requestRows, itemRows, messageRows, earningsRow, nearbyRows
            )
            apply(userID: userID, profile: profile, places: places, groups: groups, members: members, runs: runs,
                  requests: requests, nearby: nearby, items: items, messages: messages, earnings: earnings)
            for groupID in openConversations { await loadConversation(groupID: groupID) }
        } catch {
            report(error)
        }
    }

    func openConversation(groupID: UUID) async {
        openConversations.insert(groupID)
        await loadConversation(groupID: groupID)
    }

    func closeConversation(groupID: UUID) {
        openConversations.remove(groupID)
    }

    private func loadConversation(groupID: UUID) async {
        guard let backend, isLive, let userID else { return }
        do {
            conversations[groupID] = try await backend.messages(groupID: groupID).map { message(from: $0, me: userID) }
        } catch {
            report(error)
        }
    }

    private func clear() {
        profile = nil
        places = []
        earnings = nil
        runFeed = []
        myRuns = []
        myRequestItems = []
        earnItems = []
        liveGroups = []
        discoverableGroups = []
        liveActivities = []
        conversations = [:]
    }

    // MARK: Actions

    @discardableResult
    func postRequest(_ request: NewRequest) async -> (request: RequestRow, matches: [(RunMatch, GrabItem)])? {
        guard let backend else { return nil }
        do {
            let row = try await backend.postRequest(request)
            let matches = try await backend.matchRuns(forRequest: row.id)
            let runs = try await backend.runs(ids: matches.map(\.runID))
            let paired = matches.compactMap { match in runs.first { $0.id == match.runID }.map { (match, item(from: $0)) } }
            await refresh()
            return (row, paired)
        } catch {
            report(error)
            return nil
        }
    }

    @discardableResult
    func announceRun(_ run: NewRun) async -> (run: RunRow, matches: [(RequestMatch, GrabItem)])? {
        guard let backend, let userID else { return nil }
        do {
            let row = try await backend.announceRun(run)
            let matches = try await backend.matchRequests(forRun: row.id)
            let requests = try await backend.requests(ids: matches.map(\.requestID))
            let paired = matches.compactMap { match in
                requests.first { $0.id == match.requestID }.map { (match, item(from: $0, me: userID)) }
            }
            await refresh()
            return (row, paired)
        } catch {
            report(error)
            return nil
        }
    }

    /// Requests that fit on one of your active runs, smallest detour first.
    func matches(forRun runID: UUID) async -> [(RequestMatch, GrabItem)] {
        guard let backend, let userID else { return [] }
        do {
            let matches = try await backend.matchRequests(forRun: runID)
            let requests = try await backend.requests(ids: matches.map(\.requestID))
            return matches.compactMap { match in
                requests.first { $0.id == match.requestID }.map { (match, item(from: $0, me: userID)) }
            }
        } catch {
            report(error)
            return []
        }
    }

    /// Your runs that are still collecting requests.
    var myActiveRuns: [GrabItem] { runFeedMine }

    func accept(_ item: GrabItem, onRun runID: UUID? = nil) async -> Bool {
        guard let ref = item.backend, ref.source == .request else { return false }
        return await mutate { try await $0.accept(requestID: ref.id, runID: runID) }
    }

    func advance(_ item: GrabItem, to status: GrabStatus) async -> Bool {
        guard let ref = item.backend, ref.source == .request, let raw = status.requestStatus else { return false }
        return await mutate { try await $0.advance(requestID: ref.id, to: raw) }
    }

    func release(_ item: GrabItem) async -> Bool {
        guard let ref = item.backend else { return false }
        return await mutate { try await $0.release(requestID: ref.id) }
    }

    func cancel(_ item: GrabItem) async -> Bool {
        guard let ref = item.backend else { return false }
        return await mutate { try await $0.cancel(requestID: ref.id) }
    }

    func setRunStatus(_ item: GrabItem, _ status: String) async -> Bool {
        guard let ref = item.backend, ref.source == .run else { return false }
        return await mutate { try await $0.setRunStatus(ref.id, status: status) }
    }

    func requestFromRun(_ item: GrabItem, title: String, budgetDollars: Int?) async -> Bool {
        guard let ref = item.backend, ref.source == .run else { return false }
        return await mutate { try await $0.requestFromRun(runID: ref.id, title: title, budgetCents: budgetDollars.map { $0 * 100 }) }
    }

    func sendMessage(_ body: String, to groupID: UUID) async -> Bool {
        let ok = await mutate { try await $0.sendMessage(groupID: groupID, body: body) }
        if ok { await loadConversation(groupID: groupID) }
        return ok
    }

    func addListItem(_ body: String, groupID: UUID, runID: UUID?) async -> Bool {
        await mutate { try await $0.addListItem(groupID: groupID, runID: runID, body: body) }
    }

    func toggle(_ item: ShoppingItem) async -> Bool {
        await mutate { try await $0.setListItem(item.id, picked: !item.isPicked) }
    }

    func createGroup(named name: String) async -> Bool {
        await mutate { _ = try await $0.createGroup(name: name) }
    }

    func joinGroup(code: String) async -> Bool {
        await mutate { _ = try await $0.joinGroup(inviteCode: code) }
    }

    func joinBuilding(_ group: GrabGroup) async -> Bool {
        await mutate { _ = try await $0.joinBuilding(groupID: group.id) }
    }

    private func mutate(_ work: (GrabBackend) async throws -> Void) async -> Bool {
        let ok = await perform(work)
        if ok { await refresh() }
        return ok
    }

    private func perform(_ work: (GrabBackend) async throws -> Void) async -> Bool {
        guard let backend else { return false }
        do {
            try await work(backend)
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        if let error = error as? PostgrestError {
            lastError = error.message
        } else {
            lastError = error.localizedDescription
        }
    }

    // MARK: Realtime

    private func startRealtime() async {
        guard let backend, channel == nil else { return }
        let channel = backend.client.channel("grab-live")
        let changes = channel.postgresChange(AnyAction.self, schema: "public")
        self.channel = channel
        do {
            try await channel.subscribeWithError()
        } catch {
            report(error)
            return
        }
        realtimeTask = Task { [weak self] in
            for await _ in changes {
                self?.scheduleRefresh()
            }
        }
    }

    private func stopRealtime() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let channel, let backend { await backend.client.removeChannel(channel) }
        channel = nil
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: Mapping rows onto view models

    private func apply(userID: UUID, profile: ProfileRecord, places: [PlaceRow], groups: [GroupRow], members: [MemberRow],
                       runs: [RunRow], requests: [RequestRow], nearby: [RequestRow], items: [ListItemRow],
                       messages: [MessageRow], earnings: EarningsRow?) {
        self.profile = profile
        self.places = places
        self.earnings = earnings

        myRuns = runs.filter { $0.runnerID == userID }
        runFeed = runs.filter { $0.runnerID != userID }.map { item(from: $0) }
        myRequestItems = requests.filter { $0.requesterID == userID }.map { item(from: $0, me: userID) }
        earnItems = nearby.map { item(from: $0, me: userID) }
        liveActivities = requests.map { record(from: $0, me: userID) }

        let membersByGroup = Dictionary(grouping: members, by: \.groupID)
        let latestByGroup = Dictionary(grouping: messages, by: \.groupID).compactMapValues(\.first)
        let itemsByGroup = Dictionary(grouping: items, by: \.groupID)

        let mapped = groups.map { row -> GrabGroup in
            let roster = membersByGroup[row.id] ?? []
            let latest = latestByGroup[row.id]
            let run = runs.first { $0.groupID == row.id }.map { item(from: $0) }
            return GrabGroup(
                id: row.id,
                name: row.name,
                kind: row.kind == "building" ? .building : .friends,
                memberCount: roster.count,
                memberInitials: roster.compactMap { $0.profile?.initials },
                latestMessage: latest.map { "\($0.sender?.displayName.split(separator: " ").first.map(String.init) ?? "Someone"): \($0.body)" } ?? "No messages yet",
                conversation: conversations[row.id] ?? [],
                run: run,
                shoppingList: (itemsByGroup[row.id] ?? []).filter { $0.status != "unavailable" }.map {
                    ShoppingItem(id: $0.id, body: $0.body, quantity: $0.quantity, isPicked: $0.status == "picked")
                },
                inviteCode: row.inviteCode,
                isMember: roster.contains { $0.userID == userID }
            )
        }
        liveGroups = mapped.filter(\.isMember)
        discoverableGroups = mapped.filter { !$0.isMember }
    }

    private func item(from run: RunRow) -> GrabItem {
        let me = userID
        let isMine = run.runnerID == me
        let runner = run.runner.map { Person(id: $0.id, name: $0.displayName, initials: $0.initials) }
            ?? Person(id: run.runnerID, name: "A neighbor", initials: "?")
        let firstName = isMine ? "You" : (runner.name.split(separator: " ").first.map(String.init) ?? runner.name)
        let store = run.storeLabel.components(separatedBy: " · ").first ?? run.storeLabel
        let kind: GrabItem.Kind = switch run.audience {
        case "friends": .friendRun
        case "building": .buildingRun
        default: .campusRun
        }
        let title = switch run.status {
        case "shopping": isMine ? "You’re at \(store)" : "\(firstName) is at \(store)"
        case "returning": isMine ? "You’re heading back from \(store)" : "\(firstName) is heading back from \(store)"
        default: isMine ? "Your \(store) run" : "\(firstName) is going to \(store)"
        }
        let subtitle = run.note ?? (kind == .friendRun
            ? "Add something before \(firstName) checks out"
            : "Heading to \(run.destinationLabel)")
        let timing = kind == .friendRun
            ? "List closes \(Self.relative(run.closesAt))"
            : "Requests close at \(Self.time(run.closesAt))"
        return GrabItem(
            id: run.id,
            title: title,
            subtitle: subtitle,
            person: runner,
            pickup: run.storeLabel,
            destination: run.destinationLabel,
            timing: timing,
            reward: run.feeCents > 0 ? Self.dollars(run.feeCents) : nil,
            merchandiseBudget: nil,
            effort: nil,
            kind: kind,
            status: GrabStatus(runStatus: run.status),
            detail: [run.note, "Takes requests that add up to \(run.maxAddedMinutes) min to the trip."].compactMap { $0 }.joined(separator: " "),
            backend: BackendRef(source: .run, id: run.id, groupID: run.groupID, role: isMine ? .owner : .viewer, rawStatus: run.status)
        )
    }

    private func item(from request: RequestRow, me: UUID) -> GrabItem {
        let requester = request.requester.map { Person(id: $0.id, name: $0.displayName, initials: $0.initials) }
            ?? Person(id: request.requesterID, name: "A neighbor", initials: "?")
        let role: BackendRef.Role = request.requesterID == me ? .owner : (request.helperID == me ? .helper : .viewer)
        var detail = request.details
        if let helper = request.helper, request.status != "open" {
            let who = request.helperID == me ? "you" : helper.displayName
            detail += (detail.isEmpty ? "" : "\n\n") + "Accepted by \(who)."
        }
        return GrabItem(
            id: request.id,
            title: request.title,
            subtitle: request.details.isEmpty ? "\(request.pickupLabel) → \(request.destinationLabel)" : request.details,
            person: requester,
            pickup: request.pickupLabel,
            destination: request.destinationLabel,
            timing: "By \(Self.time(request.deliverBy))",
            reward: Self.dollars(request.rewardCents),
            merchandiseBudget: request.merchandiseBudgetCents.map(Self.dollars),
            effort: request.estMinutes.map { "\($0) min" },
            kind: .campusRequest,
            status: GrabStatus(requestStatus: request.status),
            detail: detail.isEmpty ? "No extra details." : detail,
            backend: BackendRef(source: .request, id: request.id, groupID: request.groupID, role: role, rawStatus: request.status)
        )
    }

    private func record(from request: RequestRow, me: UUID) -> ActivityRecord {
        let isRequester = request.requesterID == me
        let helperName = request.helperID == me ? "you" : (request.helper?.displayName.split(separator: " ").first.map(String.init) ?? "your helper")
        let status = GrabStatus(requestStatus: request.status)
        let update: String = switch status {
        case .waiting: "Posted \(Self.relative(request.createdAt))"
        case .accepted: isRequester ? "Accepted by \(helperName)" : "You accepted \(Self.relative(request.acceptedAt ?? request.createdAt))"
        case .pickingUp: isRequester ? "\(helperName.capitalized) is picking it up" : "Picking up at \(request.pickupLabel)"
        case .onTheWay: isRequester ? "\(helperName.capitalized) is on the way" : "Heading to \(request.destinationLabel)"
        case .delivered: isRequester ? "Delivered · confirm you got it" : "Delivered · waiting for confirmation"
        case .completed: "Completed \(Self.relative(request.completedAt ?? request.createdAt))"
        case .cancelled: "Cancelled"
        case .expired: "Expired · nobody took it in time"
        }
        return ActivityRecord(id: request.id, item: item(from: request, me: me), mode: isRequester ? .requesting : .helping,
                              currentStatus: status, lastUpdate: update)
    }

    private func message(from row: MessageRow, me: UUID) -> Message {
        let mine = row.senderID == me
        return Message(
            id: row.id,
            sender: mine ? "You" : (row.sender?.displayName.split(separator: " ").first.map(String.init) ?? "Someone"),
            body: row.body,
            time: Self.time(row.createdAt),
            isCurrentUser: mine
        )
    }

    // MARK: Formatting

    static func dollars(_ cents: Int) -> Int { Int((Double(cents) / 100).rounded()) }

    static func time(_ date: Date) -> String {
        date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened)
    }

    static func relative(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

extension GrabStatus {
    init(requestStatus: String) {
        switch requestStatus {
        case "accepted": self = .accepted
        case "picking_up": self = .pickingUp
        case "on_the_way": self = .onTheWay
        case "delivered": self = .delivered
        case "completed": self = .completed
        case "cancelled": self = .cancelled
        case "expired": self = .expired
        default: self = .waiting
        }
    }

    init(runStatus: String) {
        switch runStatus {
        case "returning": self = .onTheWay
        case "completed": self = .completed
        case "cancelled": self = .cancelled
        default: self = .pickingUp
        }
    }

    /// The `request_status` value for lifecycle RPCs.
    var requestStatus: String? {
        switch self {
        case .waiting: nil
        case .accepted: "accepted"
        case .pickingUp: "picking_up"
        case .onTheWay: "on_the_way"
        case .delivered: "delivered"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .expired: "expired"
        }
    }

    /// The next step the helper can move a request to. Completion is the requester's to confirm.
    var nextHelperStep: GrabStatus? {
        switch self {
        case .accepted: .pickingUp
        case .pickingUp: .onTheWay
        case .onTheWay: .delivered
        default: nil
        }
    }
}
