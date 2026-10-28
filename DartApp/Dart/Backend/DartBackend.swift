import Foundation
import Supabase

/// Thin, typed wrapper over the Supabase client. Every call is subject to row level security,
/// and request status changes go through the lifecycle functions defined in the migrations.
final class DartBackend {
    let client: SupabaseClient

    init(config: SupabaseConfig) {
        #if os(macOS)
        // The macOS harness is ad-hoc signed, so its signature changes every build and the keychain
        // asks for a password on each launch. Keep its dev session in a file instead.
        let auth = SupabaseClientOptions.AuthOptions(storage: FileSessionStorage(), emitLocalSessionAsInitialSession: true)
        #else
        let auth = SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
        #endif
        client = SupabaseClient(supabaseURL: config.url, supabaseKey: config.anonKey,
                                options: SupabaseClientOptions(auth: auth))
    }

    var currentUserID: UUID? { client.auth.currentUser?.id }

    // MARK: Auth (email and password)

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    /// Returns true when Supabase creates a session immediately. When hosted email confirmation is
    /// enabled, the account is created but the user must confirm it before the first sign-in.
    /// The role goes in auth metadata; the signup trigger turns it into the profile's role flags.
    func createAccount(email: String, password: String, displayName: String, role: AppRole) async throws -> Bool {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName), "role": .string(role.rawValue)]
        )
        return response.session != nil
    }

    func addMyRole(_ role: AppRole) async throws {
        try await client.rpc("add_my_role", params: ["p_role": role.rawValue]).execute()
    }

    func requestPasswordReset(email: String) async throws {
        try await client.auth.resetPasswordForEmail(
            email,
            redirectTo: URL(string: "dart://auth/recovery")
        )
    }

    func updatePassword(_ password: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: password))
    }

    func handleAuthCallback(_ url: URL) {
        client.auth.handle(url)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        // The server session is gone with the user; just drop the local one.
        try await client.auth.signOut(scope: .local)
    }

    // MARK: Reads

    func profile(id: UUID) async throws -> ProfileRecord {
        try await client.from("profiles").select(ProfileRecord.select).eq("id", value: id).single().execute().value
    }

    func places() async throws -> [PlaceRow] {
        try await client.from("places").select().order("name").execute().value
    }

    func groups() async throws -> [GroupRow] {
        try await client.from("groups").select("id, name, kind, invite_code, place_id").order("name").execute().value
    }

    func members() async throws -> [MemberRow] {
        try await client.from("group_members").select(MemberRow.select).execute().value
    }

    func blockedUsers() async throws -> [BlockedUserRow] {
        try await client.from("user_blocks").select(BlockedUserRow.select).order("created_at", ascending: false).execute().value
    }

    /// Active runs you can see: your own, your groups', and campus-wide ones.
    func activeRuns() async throws -> [RunRow] {
        try await client.from("runs").select(RunRow.select)
            .in("status", values: ["open", "shopping", "returning"])
            .gt("closes_at", value: Date())
            .order("closes_at")
            .execute().value
    }

    /// Requests you posted or are helping with, newest first.
    func myRequests(userID: UUID) async throws -> [RequestRow] {
        try await client.from("requests").select(RequestRow.select)
            .or("requester_id.eq.\(userID),helper_id.eq.\(userID)")
            .order("created_at", ascending: false)
            .limit(100)
            .execute().value
    }

    /// Open requests you could take, nearest to the given point first.
    func openRequestsNearby(lat: Double?, lng: Double?) async throws -> [RequestRow] {
        try await client.rpc("open_requests_nearby", params: NearbyParams(lat: lat, lng: lng))
            .select(RequestRow.select)
            .limit(50)
            .execute().value
    }

    func listItems() async throws -> [ListItemRow] {
        try await client.from("list_items").select().order("created_at").execute().value
    }

    func latestMessages(limit: Int = 200) async throws -> [MessageRow] {
        try await client.from("messages").select(MessageRow.select)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    func messages(groupID: UUID, limit: Int = 100) async throws -> [MessageRow] {
        let rows: [MessageRow] = try await client.from("messages").select(MessageRow.select)
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return rows.reversed()
    }

    func earnings() async throws -> EarningsRow? {
        let rows: [EarningsRow] = try await client.rpc("my_earnings").execute().value
        return rows.first
    }

    func runs(ids: [UUID]) async throws -> [RunRow] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("runs").select(RunRow.select).in("id", values: ids).execute().value
    }

    func requests(ids: [UUID]) async throws -> [RequestRow] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("requests").select(RequestRow.select).in("id", values: ids).execute().value
    }

    /// Adds a place, or returns the existing one with the same name within 150 m.
    func createPlace(_ place: NewPlace) async throws -> PlaceRow {
        try await client.rpc("create_place", params: place).single().execute().value
    }

    // MARK: Matching

    func matchRuns(forRequest id: UUID) async throws -> [RunMatch] {
        try await client.rpc("match_runs_for_request", params: ["p_request_id": id]).execute().value
    }

    func matchRequests(forRun id: UUID) async throws -> [RequestMatch] {
        try await client.rpc("match_requests_for_run", params: ["p_run_id": id]).execute().value
    }

    // MARK: Writes

    func updateDisplayName(_ name: String, userID: UUID) async throws {
        try await client.from("profiles").update(["display_name": name]).eq("id", value: userID).execute()
    }

    func setAgeBand(_ ageBand: String) async throws {
        try await client.rpc("set_my_age_band", params: ["p_age_band": ageBand]).execute()
    }

    func acceptSafetyRules() async throws {
        try await client.rpc("accept_safety_rules").execute()
    }

    func postRequest(_ request: NewRequest) async throws -> RequestRow {
        try await client.from("requests").insert(request).select(RequestRow.select).single().execute().value
    }

    func announceRun(_ run: NewRun) async throws -> RunRow {
        try await client.from("runs").insert(run).select(RunRow.select).single().execute().value
    }

    func setRunStatus(_ id: UUID, status: String) async throws {
        try await client.from("runs").update(["status": status]).eq("id", value: id).execute()
    }

    func accept(requestID: UUID, runID: UUID?) async throws {
        try await client.rpc("accept_request", params: AcceptParams(requestID: requestID, runID: runID)).execute()
    }

    func advance(requestID: UUID, to status: String) async throws {
        try await client.rpc("advance_request", params: ["p_request_id": requestID.uuidString, "p_status": status]).execute()
    }

    func release(requestID: UUID) async throws {
        try await client.rpc("release_request", params: ["p_request_id": requestID]).execute()
    }

    func cancel(requestID: UUID) async throws {
        try await client.rpc("cancel_request", params: ["p_request_id": requestID]).execute()
    }

    func requestFromRun(runID: UUID, title: String, budgetCents: Int?) async throws {
        try await client.rpc("request_from_run", params: RequestFromRunParams(runID: runID, title: title, budgetCents: budgetCents)).execute()
    }

    func sendMessage(groupID: UUID, body: String) async throws {
        try await client.from("messages").insert(["group_id": groupID.uuidString, "body": body]).execute()
    }

    func addListItem(groupID: UUID, runID: UUID?, body: String) async throws {
        var row = ["group_id": groupID.uuidString, "body": body]
        row["run_id"] = runID?.uuidString
        try await client.from("list_items").insert(row).execute()
    }

    func setListItem(_ id: UUID, picked: Bool) async throws {
        try await client.from("list_items").update(["status": picked ? "picked" : "needed"]).eq("id", value: id).execute()
    }

    func createGroup(name: String) async throws -> GroupRow {
        try await client.rpc("create_group", params: ["p_name": name]).single().execute().value
    }

    func joinGroup(inviteCode: String) async throws -> GroupRow {
        try await client.rpc("join_group", params: ["p_invite_code": inviteCode]).single().execute().value
    }

    func joinBuilding(groupID: UUID) async throws {
        try await client.rpc("join_building_group", params: ["p_group_id": groupID]).execute()
    }

    /// Sets where you live; for a residence this also puts you in that building's group.
    func setHomePlace(_ placeID: UUID?) async throws {
        try await client.rpc("set_home_place", params: ["p_place_id": placeID]).execute()
    }

    func leaveGroup(_ groupID: UUID) async throws {
        try await client.rpc("leave_group", params: ["p_group_id": groupID]).execute()
    }

    func blockUser(_ userID: UUID) async throws {
        try await client.from("user_blocks").insert(["blocked_id": userID.uuidString]).execute()
    }

    func unblockUser(_ userID: UUID) async throws {
        try await client.from("user_blocks").delete().eq("blocked_id", value: userID).execute()
    }

    func reportUser(_ userID: UUID, requestID: UUID?, groupID: UUID?, category: String, details: String) async throws {
        try await client.from("safety_reports").insert(SafetyReportPayload(
            reportedUserID: userID,
            requestID: requestID,
            groupID: groupID,
            category: category,
            details: details
        )).execute()
    }

    func deleteListItem(_ id: UUID) async throws {
        try await client.from("list_items").delete().eq("id", value: id).execute()
    }

    // MARK: Requester <-> helper chat

    func requestMessages(requestID: UUID) async throws -> [RequestMessageRow] {
        try await client.from("request_messages").select(RequestMessageRow.select)
            .eq("request_id", value: requestID)
            .order("created_at")
            .limit(200)
            .execute().value
    }

    /// Recent messages across every request you're part of (RLS limits it to those).
    func latestRequestMessages(limit: Int = 100) async throws -> [RequestMessageRow] {
        try await client.from("request_messages").select(RequestMessageRow.select)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    func sendRequestMessage(requestID: UUID, body: String) async throws {
        try await client.from("request_messages").insert(["request_id": requestID.uuidString, "body": body]).execute()
    }

    // MARK: Push notifications + Live Activities

    func registerPushToken(_ token: String, bundleID: String, appVariant: String) async throws {
        let row = PushTokenRegistration(
            token: token,
            bundleID: bundleID,
            appVariant: appVariant,
            environment: Self.pushEnvironment
        )
        try await client.from("push_tokens").upsert(row, onConflict: "user_id,token").execute()
    }

    func registerLiveActivityToken(_ token: String, requestID: UUID, bundleID: String, appVariant: String) async throws {
        let row = LiveActivityTokenRegistration(
            requestID: requestID,
            token: token,
            bundleID: bundleID,
            appVariant: appVariant,
            environment: Self.pushEnvironment
        )
        try await client.from("live_activity_tokens").upsert(row, onConflict: "user_id,request_id,token").execute()
    }

    private static var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

// MARK: - RPC parameter payloads

private struct NearbyParams: Encodable {
    let lat: Double?
    let lng: Double?

    enum CodingKeys: String, CodingKey {
        case lat = "p_lat"
        case lng = "p_lng"
    }

    // Encode nulls explicitly so PostgREST resolves the function signature.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lat, forKey: .lat)
        try container.encode(lng, forKey: .lng)
    }
}

private struct AcceptParams: Encodable {
    let requestID: UUID
    let runID: UUID?

    enum CodingKeys: String, CodingKey {
        case requestID = "p_request_id"
        case runID = "p_run_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(runID, forKey: .runID)
    }
}

private struct RequestFromRunParams: Encodable {
    let runID: UUID
    let title: String
    let budgetCents: Int?

    enum CodingKeys: String, CodingKey {
        case runID = "p_run_id"
        case title = "p_title"
        case budgetCents = "p_merchandise_budget_cents"
    }
}

private struct PushTokenRegistration: Encodable {
    let token: String
    let bundleID: String
    let appVariant: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case token, environment
        case bundleID = "bundle_id"
        case appVariant = "app_variant"
    }
}

private struct LiveActivityTokenRegistration: Encodable {
    let requestID: UUID
    let token: String
    let bundleID: String
    let appVariant: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case token, environment
        case requestID = "request_id"
        case bundleID = "bundle_id"
        case appVariant = "app_variant"
    }
}

private struct SafetyReportPayload: Encodable {
    let reportedUserID: UUID
    let requestID: UUID?
    let groupID: UUID?
    let category: String
    let details: String

    enum CodingKeys: String, CodingKey {
        case category, details
        case reportedUserID = "reported_user_id"
        case requestID = "request_id"
        case groupID = "group_id"
    }
}

#if os(macOS)
/// Session storage for the macOS development harness: one file per key in Application Support.
/// `DART_DEV_PROFILE` picks a separate login, so two windows can be two different accounts.
private struct FileSessionStorage: AuthLocalStorage {
    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DartDev/auth-\(ProcessInfo.processInfo.environment["DART_DEV_PROFILE"] ?? "default")",
                                    isDirectory: true)
    }

    private func file(_ key: String) -> URL {
        folder.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_"))
    }

    func store(key: String, value: Data) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try value.write(to: file(key), options: .atomic)
    }

    func retrieve(key: String) throws -> Data? {
        try? Data(contentsOf: file(key))
    }

    func remove(key: String) throws {
        try? FileManager.default.removeItem(at: file(key))
    }
}
#endif
