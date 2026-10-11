import Foundation
import Supabase

/// Thin, typed wrapper over the Supabase client. Every call is subject to row level security,
/// and request status changes go through the lifecycle functions defined in the migrations.
final class GrabBackend {
    let client: SupabaseClient

    init(config: SupabaseConfig) {
        client = SupabaseClient(
            supabaseURL: config.url,
            supabaseKey: config.anonKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }

    var currentUserID: UUID? { client.auth.currentUser?.id }

    // MARK: Auth (6-digit email code)

    func sendCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    func verify(email: String, code: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .email)
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

    func joinBuilding(groupID: UUID) async throws -> GroupRow {
        try await client.rpc("join_building_group", params: ["p_group_id": groupID]).single().execute().value
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
