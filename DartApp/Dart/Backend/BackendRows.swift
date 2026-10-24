import Foundation

// Wire types for the Supabase schema in /supabase/migrations. Column names are snake_case;
// money is integer cents. These stay separate from the view-facing models in Domain/Models.swift.

struct PersonRow: Decodable, Hashable {
    let id: UUID
    let displayName: String
    let initials: String

    enum CodingKeys: String, CodingKey {
        case id, initials
        case displayName = "display_name"
    }
}

struct ProfileRecord: Decodable, Hashable {
    let id: UUID
    let displayName: String
    let initials: String
    let campusID: UUID?
    let homePlaceID: UUID?
    let ageBand: String
    let safetyRulesAcceptedAt: Date?
    let campus: CampusRow?
    let homePlace: PlaceRow?

    static let select = "id, display_name, initials, campus_id, home_place_id, age_band, safety_rules_accepted_at, campus:campuses(id, name, lat, lng), home_place:places!home_place_id(*)"

    enum CodingKeys: String, CodingKey {
        case id, initials, campus
        case displayName = "display_name"
        case campusID = "campus_id"
        case homePlaceID = "home_place_id"
        case ageBand = "age_band"
        case safetyRulesAcceptedAt = "safety_rules_accepted_at"
        case homePlace = "home_place"
    }
}

struct BlockedUserRow: Decodable, Hashable, Identifiable {
    let blockedID: UUID
    let blocked: PersonRow?

    var id: UUID { blockedID }
    static let select = "blocked_id, blocked:profiles!user_blocks_blocked_id_fkey(id, display_name, initials)"

    enum CodingKeys: String, CodingKey {
        case blocked
        case blockedID = "blocked_id"
    }
}

struct CampusRow: Decodable, Hashable {
    let id: UUID
    let name: String
    let lat: Double
    let lng: Double
}

struct PlaceRow: Decodable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let detail: String?
    let kind: String
    let lat: Double
    let lng: Double

    var label: String { detail.map { "\(name) · \($0)" } ?? name }
    var isStore: Bool { kind == "store" || kind == "restaurant" }
}

struct GroupRow: Decodable, Hashable {
    let id: UUID
    let name: String
    let kind: String
    let inviteCode: String
    let placeID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case inviteCode = "invite_code"
        case placeID = "place_id"
    }
}

struct MemberRow: Decodable, Hashable {
    struct Initials: Decodable, Hashable { let initials: String }
    let groupID: UUID
    let userID: UUID
    let profile: Initials?

    static let select = "group_id, user_id, profile:profiles(initials)"

    enum CodingKeys: String, CodingKey {
        case profile
        case groupID = "group_id"
        case userID = "user_id"
    }
}

struct RunRow: Decodable, Hashable {
    let id: UUID
    let runnerID: UUID
    let groupID: UUID?
    let audience: String
    let storePlaceID: UUID?
    let destinationPlaceID: UUID?
    let storeLabel: String
    let destinationLabel: String
    let note: String?
    let status: String
    let closesAt: Date
    let feeCents: Int
    let maxAddedMinutes: Int
    let capacity: Int
    let runner: PersonRow?

    static let select = "*, runner:profiles!runner_id(id, display_name, initials)"

    enum CodingKeys: String, CodingKey {
        case id, audience, note, status, capacity, runner
        case runnerID = "runner_id"
        case groupID = "group_id"
        case storePlaceID = "store_place_id"
        case destinationPlaceID = "destination_place_id"
        case storeLabel = "store_label"
        case destinationLabel = "destination_label"
        case closesAt = "closes_at"
        case feeCents = "fee_cents"
        case maxAddedMinutes = "max_added_minutes"
    }
}

struct RequestRow: Decodable, Hashable {
    let id: UUID
    let requesterID: UUID
    let groupID: UUID?
    let runID: UUID?
    let title: String
    let details: String
    let pickupPlaceID: UUID?
    let destinationPlaceID: UUID?
    let pickupLabel: String
    let destinationLabel: String
    let deliverBy: Date
    let rewardCents: Int
    let merchandiseBudgetCents: Int?
    let estMinutes: Int?
    let status: String
    let helperID: UUID?
    let createdAt: Date
    let acceptedAt: Date?
    let completedAt: Date?
    let requester: PersonRow?
    let helper: PersonRow?

    static let select = "*, requester:profiles!requester_id(id, display_name, initials), helper:profiles!helper_id(id, display_name, initials)"

    enum CodingKeys: String, CodingKey {
        case id, title, details, status, requester, helper
        case requesterID = "requester_id"
        case groupID = "group_id"
        case runID = "run_id"
        case pickupPlaceID = "pickup_place_id"
        case destinationPlaceID = "destination_place_id"
        case pickupLabel = "pickup_label"
        case destinationLabel = "destination_label"
        case deliverBy = "deliver_by"
        case rewardCents = "reward_cents"
        case merchandiseBudgetCents = "merchandise_budget_cents"
        case estMinutes = "est_minutes"
        case helperID = "helper_id"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case completedAt = "completed_at"
    }
}

struct MessageRow: Decodable, Hashable {
    struct Sender: Decodable, Hashable {
        let displayName: String
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
    let id: UUID
    let groupID: UUID
    let senderID: UUID?
    let body: String
    let createdAt: Date
    let sender: Sender?

    static let select = "id, group_id, sender_id, body, created_at, sender:profiles!sender_id(display_name)"

    enum CodingKeys: String, CodingKey {
        case id, body, sender
        case groupID = "group_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
    }
}

struct RequestMessageRow: Decodable, Hashable {
    let id: UUID
    let requestID: UUID
    let senderID: UUID?
    let body: String
    let createdAt: Date
    let sender: MessageRow.Sender?

    static let select = "id, request_id, sender_id, body, created_at, sender:profiles!sender_id(display_name)"

    enum CodingKeys: String, CodingKey {
        case id, body, sender
        case requestID = "request_id"
        case senderID = "sender_id"
        case createdAt = "created_at"
    }
}

struct ListItemRow: Decodable, Hashable {
    let id: UUID
    let groupID: UUID
    let runID: UUID?
    let body: String
    let quantity: Int
    let status: String
    let addedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case id, body, quantity, status
        case groupID = "group_id"
        case runID = "run_id"
        case addedBy = "added_by"
    }
}

struct EarningsRow: Decodable, Hashable {
    let completedCount: Int
    let earnedCents: Int
    let activeCount: Int

    enum CodingKeys: String, CodingKey {
        case completedCount = "completed_count"
        case earnedCents = "earned_cents"
        case activeCount = "active_count"
    }
}

/// An active run that could carry one of your requests.
struct RunMatch: Decodable, Hashable {
    let runID: UUID
    let detourMinutes: Int
    let feeCents: Int
    let seatsLeft: Int

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case detourMinutes = "detour_minutes"
        case feeCents = "fee_cents"
        case seatsLeft = "seats_left"
    }
}

/// An open request that fits on one of your runs.
struct RequestMatch: Decodable, Hashable {
    let requestID: UUID
    let detourMinutes: Int?
    let rewardCents: Int

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case detourMinutes = "detour_minutes"
        case rewardCents = "reward_cents"
    }
}

// MARK: - Inserts

/// Parameters for `create_place`. `kind` is a `place_kind` value.
struct NewPlace: Encodable {
    var name: String
    var kind: String
    var lat: Double
    var lng: Double
    var detail: String?
    var address: String?

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case kind = "p_kind"
        case lat = "p_lat"
        case lng = "p_lng"
        case detail = "p_detail"
        case address = "p_address"
    }
}

struct NewRequest: Encodable {
    var groupID: UUID?
    var title: String
    var details: String
    var pickupPlaceID: UUID?
    var pickupLabel: String
    var destinationPlaceID: UUID?
    var destinationLabel: String
    var deliverBy: Date
    var rewardCents: Int
    var merchandiseBudgetCents: Int?

    enum CodingKeys: String, CodingKey {
        case title, details
        case groupID = "group_id"
        case pickupPlaceID = "pickup_place_id"
        case pickupLabel = "pickup_label"
        case destinationPlaceID = "destination_place_id"
        case destinationLabel = "destination_label"
        case deliverBy = "deliver_by"
        case rewardCents = "reward_cents"
        case merchandiseBudgetCents = "merchandise_budget_cents"
    }
}

struct NewRun: Encodable {
    var groupID: UUID?
    var audience: String
    var storePlaceID: UUID?
    var storeLabel: String
    var destinationPlaceID: UUID?
    var destinationLabel: String
    var note: String?
    var closesAt: Date
    var feeCents: Int
    var maxAddedMinutes: Int

    enum CodingKeys: String, CodingKey {
        case audience, note
        case groupID = "group_id"
        case storePlaceID = "store_place_id"
        case storeLabel = "store_label"
        case destinationPlaceID = "destination_place_id"
        case destinationLabel = "destination_label"
        case closesAt = "closes_at"
        case feeCents = "fee_cents"
        case maxAddedMinutes = "max_added_minutes"
    }
}
