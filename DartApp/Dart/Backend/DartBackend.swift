import Foundation
import Supabase

<<<<<<< Updated upstream:DartApp/Dart/Backend/DartBackend.swift
=======
enum GrabBackendError: LocalizedError {
    case invalidEmail
    case unsupportedCampus
    case accountMissing

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            "Enter a valid email address, like you@berkeley.edu."
        case .unsupportedCampus:
            "That email is not connected to a supported campus yet. For this launch, use an @berkeley.edu address."
        case .accountMissing:
            "This account no longer exists. Sign in again to create a new one."
        }
    }
}

/// Email rules shared by the sign-in screen and the backend.
enum EmailAddress {
    /// Trimmed and lowercased, which is how Supabase Auth stores addresses.
    static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// A practical check for a deliverable address: one @, a local part, and a dotted domain.
    static func isValid(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, email.count <= 254,
              !email.contains(where: { $0.isWhitespace || $0.isNewline }) else { return false }
        let local = parts[0], domain = parts[1]
        guard (1...64).contains(local.count) else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    static func domain(of email: String) -> String {
        email.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
    }
}

>>>>>>> Stashed changes:GrabApp/Grab/Backend/GrabBackend.swift
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

<<<<<<< Updated upstream:DartApp/Dart/Backend/DartBackend.swift
    // MARK: Auth (email and password)

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    /// Returns true when Supabase creates a session immediately. When hosted email confirmation is
    /// enabled, the account is created but the user must confirm it before the first sign-in.
    func createAccount(email: String, password: String, displayName: String) async throws -> Bool {
        let response = try await client.auth.signUp(
=======
    // MARK: Auth (6-digit email code)
    //
    // Signing in and signing up are the same step: the first verified code creates the account,
    // and the database links it to the campus for its email domain (migration 20261011000010
    // refuses any other domain). The app then asks for a name before showing live data.

    /// Emails a sign-in code. Checks the campus first so unsupported addresses get a clear answer
    /// without an email being sent.
    func sendCode(to email: String) async throws {
        guard EmailAddress.isValid(email) else { throw GrabBackendError.invalidEmail }
        guard try await isCampusEmail(email) else { throw GrabBackendError.unsupportedCampus }
        try await client.auth.signInWithOTP(
>>>>>>> Stashed changes:GrabApp/Grab/Backend/GrabBackend.swift
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
<<<<<<< Updated upstream:DartApp/Dart/Backend/DartBackend.swift
        return response.session != nil
=======
    }

    func verify(email: String, code: String) async throws {
        guard EmailAddress.isValid(email) else { throw GrabBackendError.invalidEmail }
        try await client.auth.verifyOTP(email: email, token: code, type: .email)
    }

    private func isCampusEmail(_ email: String) async throws -> Bool {
        let domain = EmailAddress.domain(of: email)
        let campuses: [CampusAccessRow] = try await client.from("campuses")
            .select("name, email_domains")
            .execute().value
        return campuses.contains { campus in
            campus.emailDomains.contains { supported in
                domain == supported || domain.hasSuffix(".\(supported)")
            }
        }
    }

    /// Completes Supabase's magic-link/PKCE flow when the email opens the app directly.
    func completeSignIn(from url: URL) async throws {
        _ = try await client.auth.session(from: url)
>>>>>>> Stashed changes:GrabApp/Grab/Backend/GrabBackend.swift
    }

    /// Never fails: the library drops the local session before telling the server, so you are
    /// signed out on this device even when the network call doesn't go through.
    func signOut() async {
        try? await client.auth.signOut()
    }

    /// Drops this device's session without contacting the server (for accounts that are gone).
    func signOutLocally() async {
        try? await client.auth.signOut(scope: .local)
    }

    func deleteAccount() async throws {
        try await client.rpc("delete_my_account").execute()
        // The server session is gone with the user; just drop the local one.
        await signOutLocally()
    }

    /// Sets the user's name and marks the account registered. Also used for later name changes:
    /// the server tidies whitespace and applies the same rules either way.
    func completeRegistration(name: String) async throws {
        try await client.rpc("complete_registration", params: ["p_display_name": name]).execute()
    }

    /// A user-facing explanation for auth and network failures; nil for anything else.
    static func authMessage(for error: Error) -> String? {
        if let error = error as? GrabBackendError { return error.errorDescription }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You’re offline. Check your connection and try again."
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Grab can’t reach its server right now. Try again in a moment."
            default:
                return nil
            }
        }
        guard let error = error as? AuthError else { return nil }
        switch error {
        case let .api(message, code, _, _):
            switch code.rawValue {
            case "otp_expired":
                return "That code is incorrect or has expired. Check your latest email, or tap Resend code."
            case "over_email_send_rate_limit":
                if let seconds = message.split(whereSeparator: { !$0.isNumber }).first {
                    return "You can request another code in \(seconds) seconds."
                }
                return "Too many codes were requested. Wait a few minutes and try again."
            case "over_request_rate_limit":
                return "Too many attempts. Wait a few minutes and try again."
            case "signup_disabled", "otp_disabled", "email_provider_disabled":
                return "Sign-ups are paused right now. Please try again later."
            case "user_banned":
                return "This account has been suspended."
            case "email_address_invalid", "validation_failed":
                return GrabBackendError.invalidEmail.errorDescription
            case "email_address_not_authorized":
                return "We can’t send email to that address yet. Please try again later."
            default:
                // The database refuses accounts outside a supported campus (migration 20261011000010).
                if message.localizedCaseInsensitiveContains("saving new user") {
                    return GrabBackendError.unsupportedCampus.errorDescription
                }
                if message.localizedCaseInsensitiveContains("sending") {
                    return "We couldn’t send the email right now. Try again in a few minutes."
                }
                return message
            }
        case .sessionMissing:
            return "You’ve been signed out. Sign in again to continue."
        default:
            return error.localizedDescription
        }
    }

    // MARK: Profile

    /// Nil when the account has been deleted (the profile cascades with the auth user).
    func profile(id: UUID) async throws -> ProfileRecord? {
        let rows: [ProfileRecord] = try await client.from("profiles").select(ProfileRecord.select)
            .eq("id", value: id).limit(1).execute().value
        return rows.first
    }

    // MARK: Reads

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
