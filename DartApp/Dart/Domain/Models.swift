import Foundation

/// Which side of Dart you're using. One account can do both; each role gets its own app shell.
enum AppRole: String, CaseIterable, Codable, Identifiable {
    case requester
    case darter
    var id: String { rawValue }

    static let defaultsKey = "dart.role.v1"
    static let onlineKey = "dart.darterOnline.v1"

    /// The role saved on this device, read by the store to decide which alerts to post.
    static var saved: AppRole? { AppRole(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") }

    var title: String {
        switch self {
        case .requester: "Get my food"
        case .darter: "Deliver & earn"
        }
    }

    var pitch: String {
        switch self {
        case .requester: "A student already nearby brings your Grubhub order to you."
        case .darter: "Grab orders from eateries you’re already passing and get paid."
        }
    }

    var symbol: String {
        switch self {
        case .requester: "bag.fill"
        case .darter: "figure.walk"
        }
    }

    var other: AppRole { self == .requester ? .darter : .requester }
}

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

enum DartStatus: String, Codable, CaseIterable {
    case waiting = "Finding a darter"
    case accepted = "Accepted"
    case pickingUp = "Picking up"
    case onTheWay = "On the way"
    case delivered = "Delivered"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case expired = "Expired"

    /// The delivery stages shown on a timeline; cancelled and expired are end states, not stages.
    static let timeline: [DartStatus] = [.waiting, .accepted, .pickingUp, .onTheWay, .delivered, .completed]

    /// Still in progress: shown in feeds and the active card.
    static let active: [DartStatus] = [.waiting, .accepted, .pickingUp, .onTheWay, .delivered]

    var icon: String {
        switch self {
        case .waiting: "clock"
        case .accepted: "person.crop.circle.badge.checkmark"
        case .pickingUp: "bag"
        case .onTheWay: "figure.walk"
        case .delivered: "shippingbox.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        case .expired: "clock.badge.xmark"
        }
    }
}

/// Where a v1 request can come from: four campus eateries where a Grubhub order waits for pickup.
/// The place IDs match rows seeded in supabase/migrations (Golden Bear Cafe in the Berkeley places
/// expansion, the other three in the Grubhub pickup spots migration).
enum PickupSpot: String, CaseIterable, Codable, Identifiable {
    case monsoonKitchens
    case ladleAndLeaf
    case goldenBearCafe
    case gatewayCafe

    var id: String { rawValue }

    var name: String {
        switch self {
        case .monsoonKitchens: "Monsoon Kitchens"
        case .ladleAndLeaf: "Ladle & Leaf"
        case .goldenBearCafe: "Golden Bear Cafe"
        case .gatewayCafe: "Gateway Cafe"
        }
    }

    /// Short name for filters and chips.
    var shortName: String {
        switch self {
        case .monsoonKitchens: "Monsoon"
        case .ladleAndLeaf: "Ladle & Leaf"
        case .goldenBearCafe: "Golden Bear"
        case .gatewayCafe: "Gateway"
        }
    }

    var area: String {
        switch self {
        case .monsoonKitchens, .ladleAndLeaf: "MLK Student Union"
        case .goldenBearCafe: "Lower Sproul Plaza"
        case .gatewayCafe: "Gateway · Hearst & Arch"
        }
    }

    /// Official logo in the asset catalog (from Berkeley Dining), or nil when none is published.
    var logoAsset: String? {
        switch self {
        case .monsoonKitchens: "logo-monsoon"
        case .ladleAndLeaf: "logo-ladle-leaf"
        case .goldenBearCafe: "logo-golden-bear"
        case .gatewayCafe: nil
        }
    }

    /// Square mark for small badges, cut from the official logo.
    var badgeAsset: String? {
        switch self {
        case .monsoonKitchens: "badge-monsoon"
        case .ladleAndLeaf: "badge-ladle-leaf"
        case .goldenBearCafe: "logo-golden-bear"
        case .gatewayCafe: nil
        }
    }

    var symbol: String {
        switch self {
        case .monsoonKitchens: "flame.fill"
        case .ladleAndLeaf: "leaf.fill"
        case .goldenBearCafe: "cup.and.saucer.fill"
        case .gatewayCafe: "building.columns.fill"
        }
    }

    var placeID: UUID {
        switch self {
        case .monsoonKitchens: UUID(uuidString: "a2000000-0000-0000-0000-000000000001")!
        case .ladleAndLeaf: UUID(uuidString: "a2000000-0000-0000-0000-000000000002")!
        case .goldenBearCafe: UUID(uuidString: "a1000000-0000-0000-0000-000000000101")!
        case .gatewayCafe: UUID(uuidString: "a2000000-0000-0000-0000-000000000003")!
        }
    }

    var location: GeoPoint {
        switch self {
        case .monsoonKitchens: GeoPoint(lat: 37.86882, lng: -122.25960)
        case .ladleAndLeaf: GeoPoint(lat: 37.86885, lng: -122.25952)
        case .goldenBearCafe: GeoPoint(lat: 37.86983, lng: -122.25970)
        case .gatewayCafe: GeoPoint(lat: 37.87414, lng: -122.26348)
        }
    }

    /// The label stored on a request, e.g. "Monsoon Kitchens · MLK Student Union".
    var pickupLabel: String { "\(name) · \(area)" }

    var requestTitle: String { "Grubhub order from \(name)" }

    /// The spot a pickup label or place name refers to, if it is one of the four.
    static func matching(_ label: String) -> PickupSpot? {
        allCases.first { label.localizedCaseInsensitiveContains($0.name) }
    }
}

struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let initials: String
}

/// A latitude/longitude pair. MapKit conversions live with the map views.
struct GeoPoint: Hashable, Codable {
    let lat: Double
    let lng: Double
}

/// Links a displayed item to its backend row. Absent on preview fixtures.
struct BackendRef: Hashable, Codable {
    enum Source: String, Codable { case request, run }
    enum Role: String, Codable {
        case owner   // you posted the request or are running the trip
        case helper  // you accepted the request
        case viewer
    }

    let source: Source
    let id: UUID
    var groupID: UUID? = nil
    var role: Role = .viewer
    /// The database status (`run_status` / `request_status`), finer-grained than DartStatus.
    var rawStatus: String? = nil
}

struct DartItem: Identifiable, Hashable, Codable {
    enum Kind: String, Codable {
        case campusRequest
        case friendRun
        case buildingRun
        case campusRun
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
    let status: DartStatus
    let detail: String
    var backend: BackendRef? = nil
    /// Nil when unknown, e.g. an "any store" request has no pickup point.
    var pickupLocation: GeoPoint? = nil
    var destinationLocation: GeoPoint? = nil

    /// Where to pin the item on a map: the pickup, else the drop-off.
    var mapLocation: GeoPoint? { pickupLocation ?? destinationLocation }

    var pickupSpot: PickupSpot? { PickupSpot.matching(pickup) }

    var kindLabel: String {
        switch kind {
        case .campusRequest: pickupSpot == nil ? "Campus request" : "Grubhub pickup"
        case .friendRun: "Free friend run"
        case .buildingRun: "Paid building run"
        case .campusRun: "Campus store run"
        }
    }
}

struct DartGroup: Identifiable, Hashable, Codable {
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
    let run: DartItem?
    let shoppingList: [ShoppingItem]
    var inviteCode: String? = nil
    var isMember = true
}

struct ShoppingItem: Identifiable, Hashable, Codable {
    let id: UUID
    let body: String
    var quantity = 1
    var isPicked = false
    var addedBy: String? = nil

    static func sample(_ body: String) -> ShoppingItem {
        ShoppingItem(id: UUID(), body: body)
    }
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
    let item: DartItem
    let mode: ActivityMode
    let currentStatus: DartStatus
    let lastUpdate: String
}

enum PreviewData {
    static let maya = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Maya Chen", initials: "MC")
    static let jordan = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Jordan Lee", initials: "JL")
    static let devon = Person(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Devon Park", initials: "DP")

    static let charger = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        title: PickupSpot.monsoonKitchens.requestTitle,
        subtitle: "Ready for pickup",
        person: jordan,
        pickup: PickupSpot.monsoonKitchens.pickupLabel,
        destination: "Unit 4 · Ida Sproul Hall",
        timing: "By 6:30 PM",
        reward: 3,
        merchandiseBudget: nil,
        effort: "8–12 min",
        kind: .campusRequest,
        status: .waiting,
        detail: "Pick up Jordan’s Grubhub order at Monsoon Kitchens in the MLK Student Union and bring it to Ida Sproul Hall.",
        pickupLocation: PickupSpot.monsoonKitchens.location,
        destinationLocation: GeoPoint(lat: 37.86693, lng: -122.26093)
    )

    static let shampoo = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        title: PickupSpot.ladleAndLeaf.requestTitle,
        subtitle: "Ready for pickup",
        person: devon,
        pickup: PickupSpot.ladleAndLeaf.pickupLabel,
        destination: "Blackwell Hall",
        timing: "Before 8:00 PM",
        reward: 3,
        merchandiseBudget: nil,
        effort: "6–10 min",
        kind: .campusRequest,
        status: .accepted,
        detail: "Pick up Devon’s Grubhub order at Ladle & Leaf in the MLK Student Union and bring it to Blackwell Hall.",
        pickupLocation: PickupSpot.ladleAndLeaf.location,
        destinationLocation: GeoPoint(lat: 37.86770, lng: -122.26109)
    )

    static let traderJoes = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        title: "Maya is at Golden Bear Cafe",
        subtitle: "Ask Maya to grab your order on the way back",
        person: maya,
        pickup: PickupSpot.goldenBearCafe.pickupLabel,
        destination: "Friends: Sunday Dinner",
        timing: "List closes in 18 min",
        reward: nil,
        merchandiseBudget: nil,
        effort: nil,
        kind: .friendRun,
        status: .pickingUp,
        detail: "Maya shared this free run with friends.",
        pickupLocation: PickupSpot.goldenBearCafe.location,
        destinationLocation: GeoPoint(lat: 37.86766, lng: -122.25866)
    )

    static let buildingRun = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
        title: "Gateway Cafe run back to your building",
        subtitle: "One more order fits",
        person: maya,
        pickup: PickupSpot.gatewayCafe.pickupLabel,
        destination: "The Durant · Lobby",
        timing: "Requests close at 7:15 PM",
        reward: 3,
        merchandiseBudget: nil,
        effort: "10 min added",
        kind: .buildingRun,
        status: .onTheWay,
        detail: "A paid building run approved by the darter. Building broadcasts are never automatic in this preview.",
        pickupLocation: PickupSpot.gatewayCafe.location,
        destinationLocation: GeoPoint(lat: 37.86766, lng: -122.25866)
    )

    static let friendMessages = [
        Message(id: UUID(), sender: "Maya", body: "At Golden Bear Cafe — want me to grab your order?", time: "5:42 PM", isCurrentUser: false),
        Message(id: UUID(), sender: "You", body: "Yes please, it’s under my name!", time: "5:44 PM", isCurrentUser: true)
    ]

    static let groups = [
        DartGroup(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "Sunday Dinner", kind: .friends, memberCount: 6, memberInitials: ["MC", "NV", "JL"], latestMessage: "Maya is grabbing orders at Golden Bear Cafe", conversation: friendMessages, run: traderJoes, shoppingList: ["Sparkling water", "Pasta", "Basil"].map(ShoppingItem.sample)),
        DartGroup(id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!, name: "Design Studio", kind: .friends, memberCount: 9, memberInitials: ["DP", "AK", "NV"], latestMessage: "Anyone going near the art store?", conversation: [Message(id: UUID(), sender: "Devon", body: "Anyone going near the art store tonight?", time: "4:18 PM", isCurrentUser: false)], run: traderJoes, shoppingList: ["Tracing paper", "Black markers"].map(ShoppingItem.sample)),
        DartGroup(id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!, name: "The Durant", kind: .building, memberCount: 84, memberInitials: ["MC", "DP", "JL"], latestMessage: "Gateway Cafe run · requests close at 7:15 PM", conversation: [Message(id: UUID(), sender: "Maya", body: "I approved a Gateway Cafe run for the building.", time: "5:31 PM", isCurrentUser: false)], run: buildingRun, shoppingList: ["Laundry detergent", "Paper towels", "Shampoo"].map(ShoppingItem.sample))
    ]

    // Darter-side samples: other students' orders, never the requester's own samples above.

    static let openGateway = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000011")!,
        title: PickupSpot.gatewayCafe.requestTitle,
        subtitle: "Ready for pickup",
        person: maya,
        pickup: PickupSpot.gatewayCafe.pickupLabel,
        destination: "Unit 2 · Cunningham Hall",
        timing: "By 7:00 PM",
        reward: 3,
        merchandiseBudget: nil,
        effort: "10–14 min",
        kind: .campusRequest,
        status: .waiting,
        detail: "Pick up Maya’s Grubhub order at Gateway Cafe and bring it to Cunningham Hall.",
        pickupLocation: PickupSpot.gatewayCafe.location,
        destinationLocation: GeoPoint(lat: 37.86669, lng: -122.25486)
    )

    static let openMonsoon = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000012")!,
        title: PickupSpot.monsoonKitchens.requestTitle,
        subtitle: "Ready for pickup",
        person: devon,
        pickup: PickupSpot.monsoonKitchens.pickupLabel,
        destination: "Foothill · Stern Hall",
        timing: "By 7:15 PM",
        reward: 5,
        merchandiseBudget: nil,
        effort: "15–20 min",
        kind: .campusRequest,
        status: .waiting,
        detail: "Pick up Devon’s Grubhub order at Monsoon Kitchens and bring it to Stern Hall.",
        pickupLocation: PickupSpot.monsoonKitchens.location,
        destinationLocation: GeoPoint(lat: 37.87563, lng: -122.25570)
    )

    static let carryingGoldenBear = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000013")!,
        title: PickupSpot.goldenBearCafe.requestTitle,
        subtitle: "Ready for pickup",
        person: jordan,
        pickup: PickupSpot.goldenBearCafe.pickupLabel,
        destination: "Unit 3 · Spens-Black Hall",
        timing: "By 6:45 PM",
        reward: 3,
        merchandiseBudget: nil,
        effort: "9–12 min",
        kind: .campusRequest,
        status: .accepted,
        detail: "Pick up Jordan’s Grubhub order at Golden Bear Cafe and bring it to Spens-Black Hall.",
        pickupLocation: PickupSpot.goldenBearCafe.location,
        destinationLocation: GeoPoint(lat: 37.86743, lng: -122.25535)
    )

    static let deliveredLadle = DartItem(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000014")!,
        title: PickupSpot.ladleAndLeaf.requestTitle,
        subtitle: "Delivered",
        person: maya,
        pickup: PickupSpot.ladleAndLeaf.pickupLabel,
        destination: "Blackwell Hall",
        timing: "Yesterday",
        reward: 3,
        merchandiseBudget: nil,
        effort: nil,
        kind: .campusRequest,
        status: .completed,
        detail: "Delivered Maya’s Grubhub order from Ladle & Leaf to Blackwell Hall.",
        pickupLocation: PickupSpot.ladleAndLeaf.location,
        destinationLocation: GeoPoint(lat: 37.86640, lng: -122.25930)
    )

    static let activities = [
        ActivityRecord(id: UUID(), item: charger, mode: .requesting, currentStatus: .waiting, lastUpdate: "Posted 8 min ago"),
        ActivityRecord(id: UUID(), item: shampoo, mode: .requesting, currentStatus: .accepted, lastUpdate: "Accepted by Maya"),
        ActivityRecord(id: UUID(), item: carryingGoldenBear, mode: .helping, currentStatus: .accepted, lastUpdate: "You accepted 4 min ago"),
        ActivityRecord(id: UUID(), item: deliveredLadle, mode: .helping, currentStatus: .completed, lastUpdate: "Completed yesterday")
    ]
}
