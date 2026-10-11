import Foundation

enum HomeMode: String, CaseIterable, Codable, Identifiable {
    case request = "Request"
    case earn = "Earn"
    var id: String { rawValue }
}

enum ActivityMode: String, CaseIterable, Codable, Identifiable {
    case requesting = "Requesting"
    case helping = "Helping"
    var id: String { rawValue }
}

enum AppearanceChoice: String, CaseIterable, Codable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

enum GrabStatus: String, Codable, CaseIterable {
    case waiting = "Waiting for someone"
    case accepted = "Accepted"
    case pickingUp = "Picking up"
    case onTheWay = "On the way"
    case completed = "Completed"

    var icon: String {
        switch self {
        case .waiting: "clock"
        case .accepted: "person.crop.circle.badge.checkmark"
        case .pickingUp: "bag"
        case .onTheWay: "figure.walk"
        case .completed: "checkmark.circle.fill"
        }
    }
}

struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let initials: String
}

struct GrabItem: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case campusRequest
        case friendRun
        case buildingRun
    }

    let id: UUID
    let title: String
    let subtitle: String
    let person: Person
    let pickup: String
    let destination: String
    let timing: String
    let reward: Int?
    let merchandiseBudget: Int?
    let effort: String?
    let kind: Kind
    let status: GrabStatus
    let detail: String

    var kindLabel: String {
        switch kind {
        case .campusRequest: "Campus request"
        case .friendRun: "Free friend run"
        case .buildingRun: "Paid building run"
        }
    }
}

struct GrabGroup: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case friends = "Free friend group"
        case building = "Paid building community"
    }

    let id: UUID
    let name: String
    let kind: Kind
    let memberCount: Int
    let memberInitials: [String]
    let latestMessage: String
    let conversation: [Message]
    let run: GrabItem
    let shoppingList: [String]
}

struct Message: Identifiable, Hashable, Codable {
    let id: UUID
    let sender: String
    let body: String
    let time: String
    let isCurrentUser: Bool
}

struct ActivityRecord: Identifiable, Hashable, Codable {
    let id: UUID
    let item: GrabItem
    let mode: ActivityMode
    let currentStatus: GrabStatus
    let lastUpdate: String
}

enum PreviewData {
    static let maya = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Maya Chen", initials: "MC")
    static let jordan = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Jordan Lee", initials: "JL")
    static let devon = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Devon Park", initials: "DP")

    static let charger = GrabItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        title: "Grab my charger from the library",
        subtitle: "USB-C charger at Moffitt Library",
        person: jordan,
        pickup: "Moffitt Library · Front desk",
        destination: "Unit 4 · Ida Sproul Hall",
        timing: "By 6:30 PM",
        reward: 10,
        merchandiseBudget: nil,
        effort: "12–18 min",
        kind: .campusRequest,
        status: .waiting,
        detail: "Jordan left a labeled charger at the front desk. Show the preview request name when you arrive."
    )

    static let shampoo = GrabItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        title: "Pick up shampoo from Target",
        subtitle: "Any unscented everyday shampoo",
        person: devon,
        pickup: "Target · Shattuck Avenue",
        destination: "Blackwell Hall",
        timing: "Before 8:00 PM",
        reward: 6,
        merchandiseBudget: 14,
        effort: "8–12 min added",
        kind: .campusRequest,
        status: .accepted,
        detail: "A flexible product request. The merchandise budget is separate from the helper reward."
    )

    static let traderJoes = GrabItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        title: "Maya is at Trader Joe’s",
        subtitle: "Add something before Maya checks out",
        person: maya,
        pickup: "Trader Joe’s · University Avenue",
        destination: "Friends: Sunday Dinner",
        timing: "List closes in 18 min",
        reward: nil,
        merchandiseBudget: nil,
        effort: nil,
        kind: .friendRun,
        status: .pickingUp,
        detail: "Maya shared this free run with friends. Items and reimbursements arrive in a later section."
    )

    static let buildingRun = GrabItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
        title: "Target run back to your building",
        subtitle: "One neighbor request still available",
        person: maya,
        pickup: "Target · Shattuck Avenue",
        destination: "The Durant · Lobby",
        timing: "Requests close at 7:15 PM",
        reward: 5,
        merchandiseBudget: 22,
        effort: "10 min added",
        kind: .buildingRun,
        status: .onTheWay,
        detail: "A paid building run approved by the shopper. Building broadcasts are never automatic in this preview."
    )

    static let friendMessages = [
        Message(id: UUID(), sender: "Maya", body: "Heading to Trader Joe’s — add anything you need.", time: "5:42 PM", isCurrentUser: false),
        Message(id: UUID(), sender: "You", body: "Perfect timing. I’ll add sparkling water later!", time: "5:44 PM", isCurrentUser: true)
    ]

    static let groups = [
        GrabGroup(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "Sunday Dinner", kind: .friends, memberCount: 6, memberInitials: ["MC", "NV", "JL"], latestMessage: "Maya started a Trader Joe’s run", conversation: friendMessages, run: traderJoes, shoppingList: ["Sparkling water", "Pasta", "Basil"]),
        GrabGroup(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, name: "Design Studio", kind: .friends, memberCount: 9, memberInitials: ["DP", "AK", "NV"], latestMessage: "Anyone going near the art store?", conversation: [Message(id: UUID(), sender: "Devon", body: "Anyone going near the art store tonight?", time: "4:18 PM", isCurrentUser: false)], run: traderJoes, shoppingList: ["Tracing paper", "Black markers"]),
        GrabGroup(id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!, name: "The Durant", kind: .building, memberCount: 84, memberInitials: ["MC", "DP", "JL"], latestMessage: "Target run · requests close at 7:15 PM", conversation: [Message(id: UUID(), sender: "Maya", body: "I approved a Target run for the building.", time: "5:31 PM", isCurrentUser: false)], run: buildingRun, shoppingList: ["Laundry detergent", "Paper towels", "Shampoo"])
    ]

    static let activities = [
        ActivityRecord(id: UUID(), item: charger, mode: .requesting, currentStatus: .waiting, lastUpdate: "Posted 8 min ago"),
        ActivityRecord(id: UUID(), item: shampoo, mode: .requesting, currentStatus: .accepted, lastUpdate: "Accepted by Maya"),
        ActivityRecord(id: UUID(), item: traderJoes, mode: .helping, currentStatus: .pickingUp, lastUpdate: "List closes in 18 min"),
        ActivityRecord(id: UUID(), item: buildingRun, mode: .helping, currentStatus: .onTheWay, lastUpdate: "Returning to The Durant"),
        ActivityRecord(id: UUID(), item: charger, mode: .helping, currentStatus: .completed, lastUpdate: "Preview record · yesterday")
    ]
}
