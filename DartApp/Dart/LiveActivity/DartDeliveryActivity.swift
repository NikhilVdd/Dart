import ActivityKit
import Foundation

/// Shared wire model compiled into Grab, the App Clip, and both Live Activity extensions.
/// Keep this payload compact: ActivityKit limits combined static and dynamic data to 4 KB.
struct GrabDeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var headline: String
        var progress: Double
        var updatedAt: Double
        var isComplete: Bool
    }

    let requestID: String
    let title: String
    let pickup: String
    let destination: String
    let role: String
}

extension GrabDeliveryAttributes.ContentState {
    static func grab(status: String, headline: String, updatedAt: Date = Date()) -> Self {
        let normalized = status.lowercased()
        let progress: Double = switch normalized {
        case "accepted": 0.18
        case "picking_up": 0.42
        case "on_the_way": 0.72
        case "delivered": 0.92
        case "completed": 1
        default: 0.08
        }
        return Self(
            status: normalized,
            headline: headline,
            progress: progress,
            updatedAt: updatedAt.timeIntervalSince1970,
            isComplete: ["completed", "cancelled", "expired"].contains(normalized)
        )
    }
}
