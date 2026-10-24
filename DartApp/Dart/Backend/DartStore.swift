import Foundation
import Supabase

/// App-wide data source. Preview fixtures are available only in Debug builds. Release builds fail
/// closed when configuration is missing so production can never silently show demo accounts.
@MainActor
final class DartStore: ObservableObject {
    enum Phase: Equatable {
        case launching
        case preview
        case unconfigured
        case signedOut
        case live
    }

    @Published private(set) var phase: Phase
    @Published private(set) var isLoading = false
    @Published private(set) var profile: ProfileRecord?
    @Published private(set) var places: [PlaceRow] = []
    @Published private(set) var earnings: EarningsRow?
    @Published private(set) var discoverableGroups: [DartGroup] = []
    @Published private(set) var blockedUsers: [BlockedUserRow] = []
    @Published private(set) var requiresPasswordUpdate = false
    @Published var lastError: String?

    @Published private var runFeed: [DartItem] = []
    @Published private var myRequestItems: [DartItem] = []
    @Published private var earnItems: [DartItem] = []
    @Published private var liveGroups: [DartGroup] = []
    @Published private var liveActivities: [ActivityRecord] = []
    @Published private var conversations: [UUID: [Message]] = [:]
    @Published private var requestChats: [UUID: [Message]] = [:]

    let backend: DartBackend?
    private var myRuns: [RunRow] = []
    private var openConversations: Set<UUID> = []
    private var openRequestChats: Set<UUID> = []
    private let notifier = Notifier()
    private let liveActivityCoordinator = LiveActivityCoordinator()
    private let location = LocationProvider()
    /// What the last refresh saw, so the next one can tell what other people changed.
    private var seen: Seen?

    private struct Seen {
        var requestStatuses: [UUID: String]
        var nearbyIDs: Set<UUID>
        var messageIDs: Set<UUID>
    }
    private var authTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var channel: RealtimeChannelV2?
    private var notificationObservers: [NSObjectProtocol] = []

    init(config: SupabaseConfig? = SupabaseConfig.load()) {
        backend = config.map(DartBackend.init)
        if backend != nil {
            phase = .launching
        } else {
            #if DEBUG
            phase = .preview
            #else
            phase = .unconfigured
            #endif
        }
        if backend != nil { observeAuth() }
        location.onUpdate = { [weak self] _ in self?.scheduleRefresh() }
        observePushTokens()
    }

    var isLive: Bool { phase == .live }
    var isConfigured: Bool { backend != nil }
    var userID: UUID? { profile?.id ?? backend?.currentUserID }
    var needsOnboarding: Bool {
        guard isLive, let profile else { return false }
        return profile.ageBand == "not_set" || profile.homePlaceID == nil || profile.safetyRulesAcceptedAt == nil
    }

    private var canUsePreviewData: Bool {
        #if DEBUG
        phase == .preview
        #else
        false
        #endif
    }

    // MARK: View-facing data (falls back to preview fixtures)

    func feed(for mode: HomeMode) -> [DartItem] {
        guard isLive else {
            guard canUsePreviewData else { return [] }
            return mode == .request
                ? [PreviewData.traderJoes, PreviewData.buildingRun, PreviewData.shampoo]
                : [PreviewData.charger, PreviewData.shampoo, PreviewData.buildingRun]
        }
        switch mode {
        case .request: return runFeed + myRequestItems.filter { DartStatus.active.contains($0.status) }
        case .earn: return earnItems
        }
    }

    func activeItem(for mode: HomeMode) -> DartItem? {
        guard isLive else {
            guard canUsePreviewData else { return nil }
            return mode == .request ? PreviewData.shampoo : PreviewData.buildingRun
        }
        let active = DartStatus.active
        switch mode {
        case .request:
            return myRequestItems.first { active.contains($0.status) }
        case .earn:
            return liveActivities.first { $0.mode == .helping && active.contains($0.currentStatus) }?.item
                ?? runFeedMine.first
        }
    }

    /// The closest open request you could take, after re-centering the Earn feed on a fresh location.
    /// The server returns open requests nearest-first and leaves out your own.
    func findNearbyTask() async -> DartItem? {
        guard isLive else { return canUsePreviewData ? feed(for: .earn).first : nil }
        _ = await location.freshFix()
        await refresh()
        return earnItems.first
    }

    /// The latest version of an item, so open screens follow realtime changes.
    func latest(_ item: DartItem) -> DartItem {
        guard isLive else { return item }
        return myRequestItems.first { $0.id == item.id }
            ?? liveActivities.first { $0.id == item.id }?.item
            ?? earnItems.first { $0.id == item.id }
            ?? runFeed.first { $0.id == item.id }
            ?? runFeedMine.first { $0.id == item.id }
            ?? item
    }

    var groups: [DartGroup] { isLive ? liveGroups : (canUsePreviewData ? PreviewData.groups : []) }

    func group(id: UUID) -> DartGroup? {
        groups.first { $0.id == id } ?? discoverableGroups.first { $0.id == id }
    }

    func activities(for mode: ActivityMode) -> [ActivityRecord] {
        (isLive ? liveActivities : (canUsePreviewData ? PreviewData.activities : [])).filter { $0.mode == mode }
    }

    func conversation(for group: DartGroup) -> [Message] {
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

    private var runFeedMine: [DartItem] {
        myRuns.map { item(from: $0) }
    }

    // MARK: Auth

    enum AccountCreationResult {
        case signedIn
        case confirmationRequired
    }

    func signIn(email: String, password: String) async -> Bool {
        await perform { try await $0.signIn(email: email, password: password) }
    }

    func createAccount(email: String, password: String, displayName: String) async -> AccountCreationResult? {
        guard let backend else { return nil }
        do {
            let signedIn = try await backend.createAccount(
                email: email,
                password: password,
                displayName: displayName
            )
            return signedIn ? .signedIn : .confirmationRequired
        } catch {
            report(error)
            return nil
        }
    }

    func requestPasswordReset(email: String) async -> Bool {
        await perform { try await $0.requestPasswordReset(email: email) }
    }

    func updatePassword(_ password: String) async -> Bool {
        let updated = await perform { try await $0.updatePassword(password) }
        if updated { requiresPasswordUpdate = false }
        return updated
    }

    func handleDeepLink(_ url: URL) {
        if url.scheme == "dart", url.host == "auth" {
            backend?.handleAuthCallback(url)
        }
    }

    func dismissPasswordUpdate() {
        requiresPasswordUpdate = false
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

    func setAgeBand(_ value: String) async -> Bool {
        await mutate { try await $0.setAgeBand(value) }
    }

    func acceptSafetyRules() async -> Bool {
        await mutate { try await $0.acceptSafetyRules() }
    }

    func requestNotificationPermission() {
        notifier.requestPermission()
    }

    private func observeAuth() {
        guard let backend else { return }
        authTask = Task { [weak self] in
            for await (event, session) in backend.client.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .passwordRecovery:
                    self.requiresPasswordUpdate = true
                    if session != nil { self.phase = .live }
                case .initialSession, .signedIn:
                    if session != nil {
                        if self.phase != .live {
                            self.phase = .live
                            self.notifier.requestPermission()
                            self.location.refresh()
                            await self.refresh()
                            await self.registerCurrentPushToken()
                            await self.startRealtime()
                        }
                    } else {
                        self.phase = .signedOut
                    }
                case .signedOut:
                    await self.stopRealtime()
                    await self.liveActivityCoordinator.endAll()
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
            async let blockedRows = backend.blockedUsers()
            async let runRows = backend.activeRuns()
            async let requestRows = backend.myRequests(userID: userID)
            async let itemRows = backend.listItems()
            async let messageRows = backend.latestMessages()
            async let earningsRow = backend.earnings()

            async let requestMessageRows = backend.latestRequestMessages()

            let profile = try await profileRow
            let origin = nearbyOrigin(profile: profile)
            async let nearbyRows = backend.openRequestsNearby(lat: origin?.lat, lng: origin?.lng)

            let (places, groups, members, blocked, runs, requests, items, messages, earnings, nearby, requestMessages) = try await (
                placeRows, groupRows, memberRows, blockedRows, runRows, requestRows, itemRows, messageRows, earningsRow, nearbyRows, requestMessageRows
            )
            self.blockedUsers = blocked
            apply(userID: userID, profile: profile, places: places, groups: groups, members: members, runs: runs,
                  requests: requests, nearby: nearby, items: items, messages: messages, earnings: earnings)
            await liveActivityCoordinator.sync(records: liveActivities)
            notifyChanges(userID: userID, requests: requests, nearby: nearby, messages: messages, requestMessages: requestMessages)
            for groupID in openConversations { await loadConversation(groupID: groupID) }
            for requestID in openRequestChats { await loadRequestChat(requestID: requestID) }
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

    /// Where the Earn feed is centered: where you are now if that's near campus, else your home.
    private func nearbyOrigin(profile: ProfileRecord) -> GeoPoint? {
        if let here = location.current, let campus = profile.campus,
           here.distance(to: GeoPoint(lat: campus.lat, lng: campus.lng)) < 15_000 {
            return here
        }
        return profile.homePlace.map { GeoPoint(lat: $0.lat, lng: $0.lng) }
    }

    /// The private chat between a request's requester and helper.
    func requestChat(for requestID: UUID) -> [Message] { requestChats[requestID] ?? [] }

    func openRequestChat(requestID: UUID) async {
        openRequestChats.insert(requestID)
        await loadRequestChat(requestID: requestID)
    }

    func closeRequestChat(requestID: UUID) {
        openRequestChats.remove(requestID)
    }

    func sendRequestMessage(_ body: String, requestID: UUID) async -> Bool {
        let ok = await perform { try await $0.sendRequestMessage(requestID: requestID, body: body) }
        if ok { await loadRequestChat(requestID: requestID) }
        return ok
    }

    private func loadRequestChat(requestID: UUID) async {
        guard let backend, isLive, let userID else { return }
        do {
            requestChats[requestID] = try await backend.requestMessages(requestID: requestID).map { row in
                let mine = row.senderID == userID
                return Message(id: row.id,
                               sender: mine ? "You" : (row.sender?.displayName.split(separator: " ").first.map(String.init) ?? "Someone"),
                               body: row.body, time: Self.time(row.createdAt), isCurrentUser: mine)
            }
        } catch {
            report(error)
        }
    }

    // MARK: Notifications

    private func observePushTokens() {
        let center = NotificationCenter.default
        notificationObservers.append(center.addObserver(forName: .dartAPNSDeviceToken, object: nil, queue: .main) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String else { return }
            Task { @MainActor in await self?.registerPushToken(token) }
        })
        notificationObservers.append(center.addObserver(forName: .dartLiveActivityPushToken, object: nil, queue: .main) { [weak self] note in
            guard let token = note.userInfo?["token"] as? String,
                  let request = note.userInfo?["requestID"] as? String,
                  let requestID = UUID(uuidString: request) else { return }
            Task { @MainActor in await self?.registerLiveActivityToken(token, requestID: requestID) }
        })
    }

    private func registerCurrentPushToken() async {
        if let token = PushTokenCenter.shared.currentToken { await registerPushToken(token) }
    }

    private func registerPushToken(_ token: String) async {
        guard let backend, isLive else { return }
        do {
            try await backend.registerPushToken(
                token,
                bundleID: Bundle.main.bundleIdentifier ?? "org.example.dart",
                appVariant: "full"
            )
        } catch {
            report(error)
        }
    }

    private func registerLiveActivityToken(_ token: String, requestID: UUID) async {
        guard let backend, isLive else { return }
        do {
            try await backend.registerLiveActivityToken(
                token,
                requestID: requestID,
                bundleID: Bundle.main.bundleIdentifier ?? "org.example.dart",
                appVariant: "full"
            )
        } catch {
            report(error)
        }
    }

    private func notifyChanges(userID: UUID, requests: [RequestRow], nearby: [RequestRow], messages: [MessageRow],
                               requestMessages: [RequestMessageRow]) {
        let now = Seen(requestStatuses: Dictionary(requests.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a }),
                       nearbyIDs: Set(nearby.map(\.id)),
                       messageIDs: Set(messages.map(\.id) + requestMessages.map(\.id)))
        defer { seen = now }
        guard let before = seen else { return }  // first load after sign-in: nothing is "new"

        for request in requests {
            let old = before.requestStatuses[request.id]
            guard old != request.status else { continue }
            let mine = request.requesterID == userID
            let helper = request.helper?.displayName.split(separator: " ").first.map(String.init) ?? "Your helper"
            let requester = request.requester?.displayName.split(separator: " ").first.map(String.init) ?? "The requester"
            let text: String? = switch (mine, request.status) {
            case (true, "accepted"): "\(helper) accepted “\(request.title)”."
            case (true, "picking_up"): "\(helper) is picking up “\(request.title)”."
            case (true, "on_the_way"): "\(helper) is on the way with “\(request.title)”."
            case (true, "delivered"): "“\(request.title)” was delivered. Confirm you got it."
            case (true, "expired"): "Nobody took “\(request.title)” in time."
            case (false, "completed") where old != nil: "\(requester) confirmed “\(request.title)”. You earned $\(Self.dollars(request.rewardCents))."
            case (false, "cancelled") where old != nil: "\(requester) cancelled “\(request.title)”."
            case (false, "accepted") where old == nil && request.runID != nil && !before.nearbyIDs.contains(request.id): "New request on your run: “\(request.title)”."
            default: nil
            }
            if let text { notifier.post("Dart", text, id: "request-\(request.id)-\(request.status)") }
        }

        for request in nearby where !before.nearbyIDs.contains(request.id) && request.requesterID != userID {
            notifier.post("New request nearby", "\(request.title) · $\(Self.dollars(request.rewardCents)) reward", id: "nearby-\(request.id)")
        }

        for message in messages where !before.messageIDs.contains(message.id) && message.senderID != userID
            && !openConversations.contains(message.groupID) {
            let group = liveGroups.first { $0.id == message.groupID }?.name ?? "Your group"
            let sender = message.sender?.displayName.split(separator: " ").first.map(String.init) ?? "Someone"
            notifier.post(group, "\(sender): \(message.body)", id: "message-\(message.id)")
        }

        for message in requestMessages where !before.messageIDs.contains(message.id) && message.senderID != userID
            && !openRequestChats.contains(message.requestID) {
            let title = requests.first { $0.id == message.requestID }?.title ?? "Your request"
            let sender = message.sender?.displayName.split(separator: " ").first.map(String.init) ?? "Someone"
            notifier.post(title, "\(sender): \(message.body)", id: "request-message-\(message.id)")
        }
    }

    private func clear() {
        seen = nil
        requestChats = [:]
        profile = nil
        places = []
        earnings = nil
        runFeed = []
        myRuns = []
        myRequestItems = []
        earnItems = []
        liveGroups = []
        discoverableGroups = []
        blockedUsers = []
        liveActivities = []
        conversations = [:]
    }

    // MARK: Actions

    @discardableResult
    func postRequest(_ request: NewRequest) async -> (request: RequestRow, matches: [(RunMatch, DartItem)])? {
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
    func announceRun(_ run: NewRun) async -> (run: RunRow, matches: [(RequestMatch, DartItem)])? {
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
    func matches(forRun runID: UUID) async -> [(RequestMatch, DartItem)] {
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
    var myActiveRuns: [DartItem] { runFeedMine }

    func accept(_ item: DartItem, onRun runID: UUID? = nil) async -> Bool {
        guard let ref = item.backend, ref.source == .request else { return false }
        return await mutate { try await $0.accept(requestID: ref.id, runID: runID) }
    }

    func advance(_ item: DartItem, to status: DartStatus) async -> Bool {
        guard let ref = item.backend, ref.source == .request, let raw = status.requestStatus else { return false }
        return await mutate { try await $0.advance(requestID: ref.id, to: raw) }
    }

    func release(_ item: DartItem) async -> Bool {
        guard let ref = item.backend else { return false }
        return await mutate { try await $0.release(requestID: ref.id) }
    }

    func cancel(_ item: DartItem) async -> Bool {
        guard let ref = item.backend else { return false }
        return await mutate { try await $0.cancel(requestID: ref.id) }
    }

    func setRunStatus(_ item: DartItem, _ status: String) async -> Bool {
        guard let ref = item.backend, ref.source == .run else { return false }
        return await mutate { try await $0.setRunStatus(ref.id, status: status) }
    }

    func requestFromRun(_ item: DartItem, title: String, budgetDollars: Int?) async -> Bool {
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

    func joinBuilding(_ group: DartGroup) async -> Bool {
        await mutate { try await $0.joinBuilding(groupID: group.id) }
    }

    /// Sets your home; choosing a residence also joins (or starts) that building's group.
    func setHome(_ placeID: UUID?) async -> Bool {
        await mutate { try await $0.setHomePlace(placeID) }
    }

    func leave(_ group: DartGroup) async -> Bool {
        await mutate { try await $0.leaveGroup(group.id) }
    }

    func blockUser(_ userID: UUID) async -> Bool {
        await mutate { try await $0.blockUser(userID) }
    }

    func unblockUser(_ userID: UUID) async -> Bool {
        await mutate { try await $0.unblockUser(userID) }
    }

    func reportUser(_ userID: UUID, item: DartItem, category: String, details: String) async -> Bool {
        await perform {
            try await $0.reportUser(
                userID,
                requestID: item.backend?.source == .request ? item.backend?.id : nil,
                groupID: item.backend?.groupID,
                category: category,
                details: details
            )
        }
    }

    func delete(_ item: ShoppingItem) async -> Bool {
        await mutate { try await $0.deleteListItem(item.id) }
    }

    private func mutate(_ work: (DartBackend) async throws -> Void) async -> Bool {
        let ok = await perform(work)
        if ok { await refresh() }
        return ok
    }

    private func perform(_ work: (DartBackend) async throws -> Void) async -> Bool {
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
        let channel = backend.client.channel("dart-live")
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

        let mapped = groups.map { row -> DartGroup in
            let roster = membersByGroup[row.id] ?? []
            let latest = latestByGroup[row.id]
            let run = runs.first { $0.groupID == row.id }.map { item(from: $0) }
            return DartGroup(
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

    private func item(from run: RunRow) -> DartItem {
        let me = userID
        let isMine = run.runnerID == me
        let runner = run.runner.map { Person(id: $0.id, name: $0.displayName, initials: $0.initials) }
            ?? Person(id: run.runnerID, name: "A neighbor", initials: "?")
        let firstName = isMine ? "You" : (runner.name.split(separator: " ").first.map(String.init) ?? runner.name)
        let store = run.storeLabel.components(separatedBy: " · ").first ?? run.storeLabel
        let kind: DartItem.Kind = switch run.audience {
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
        return DartItem(
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
            status: DartStatus(runStatus: run.status),
            detail: [run.note, "Takes requests that add up to \(run.maxAddedMinutes) min to the trip."].compactMap { $0 }.joined(separator: " "),
            backend: BackendRef(source: .run, id: run.id, groupID: run.groupID, role: isMine ? .owner : .viewer, rawStatus: run.status),
            pickupLocation: location(of: run.storePlaceID),
            destinationLocation: location(of: run.destinationPlaceID)
        )
    }

    private func item(from request: RequestRow, me: UUID) -> DartItem {
        let requester = request.requester.map { Person(id: $0.id, name: $0.displayName, initials: $0.initials) }
            ?? Person(id: request.requesterID, name: "A neighbor", initials: "?")
        let role: BackendRef.Role = request.requesterID == me ? .owner : (request.helperID == me ? .helper : .viewer)
        var detail = request.details
        if let helper = request.helper, request.status != "open" {
            let who = request.helperID == me ? "you" : helper.displayName
            detail += (detail.isEmpty ? "" : "\n\n") + "Accepted by \(who)."
        }
        return DartItem(
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
            status: DartStatus(requestStatus: request.status),
            detail: detail.isEmpty ? "No extra details." : detail,
            backend: BackendRef(source: .request, id: request.id, groupID: request.groupID, role: role, rawStatus: request.status),
            pickupLocation: location(of: request.pickupPlaceID),
            destinationLocation: location(of: request.destinationPlaceID)
        )
    }

    private func record(from request: RequestRow, me: UUID) -> ActivityRecord {
        let isRequester = request.requesterID == me
        let helperName = request.helperID == me ? "you" : (request.helper?.displayName.split(separator: " ").first.map(String.init) ?? "your helper")
        let status = DartStatus(requestStatus: request.status)
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

    private func location(of placeID: UUID?) -> GeoPoint? {
        guard let placeID, let place = places.first(where: { $0.id == placeID }) else { return nil }
        return GeoPoint(lat: place.lat, lng: place.lng)
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

extension DartStatus {
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
    var nextHelperStep: DartStatus? {
        switch self {
        case .accepted: .pickingUp
        case .pickingUp: .onTheWay
        case .onTheWay: .delivered
        default: nil
        }
    }
}
