import ActivityKit
import Foundation

extension Notification.Name {
    static let grabLiveActivityPushToken = Notification.Name("grab.live-activity-push-token")
}

/// Keeps one DoorDash-style Live Activity in sync with the most relevant active Grab request.
/// Foreground realtime changes update it immediately; APNs uses the emitted token when the app is closed.
@MainActor
final class LiveActivityCoordinator {
    private var tokenTasks: [String: Task<Void, Never>] = [:]

    func sync(records: [ActivityRecord]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let trackable = records.filter {
            [.accepted, .pickingUp, .onTheWay, .delivered].contains($0.currentStatus)
        }
        guard let current = trackable.first else {
            await endOrphanedActivities(keeping: nil)
            return
        }

        let requestID = current.id.uuidString
        await endOrphanedActivities(keeping: requestID)
        let state = contentState(for: current)

        if let activity = Activity<GrabDeliveryAttributes>.activities.first(where: { $0.attributes.requestID == requestID }) {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60)))
            return
        }

        let attributes = GrabDeliveryAttributes(
            requestID: requestID,
            title: current.item.title,
            pickup: current.item.pickup,
            destination: current.item.destination,
            role: current.mode == .requesting ? "requester" : "helper"
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: .token
            )
            observePushTokens(for: activity)
        } catch {
            // Live Activities can be disabled per device; ordinary in-app status remains available.
        }
    }

    func endAll() async {
        await endOrphanedActivities(keeping: nil)
    }

    private func contentState(for record: ActivityRecord) -> GrabDeliveryAttributes.ContentState {
        let rawStatus = record.item.backend?.rawStatus ?? record.currentStatus.activityStatus
        return .grab(status: rawStatus, headline: record.lastUpdate)
    }

    private func observePushTokens(for activity: Activity<GrabDeliveryAttributes>) {
        let requestID = activity.attributes.requestID
        tokenTasks[requestID]?.cancel()
        tokenTasks[requestID] = Task {
            for await tokenData in activity.pushTokenUpdates {
                guard !Task.isCancelled else { return }
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                NotificationCenter.default.post(
                    name: .grabLiveActivityPushToken,
                    object: nil,
                    userInfo: ["requestID": requestID, "token": token]
                )
            }
        }
    }

    private func endOrphanedActivities(keeping requestID: String?) async {
        for activity in Activity<GrabDeliveryAttributes>.activities where activity.attributes.requestID != requestID {
            let final = GrabDeliveryAttributes.ContentState.grab(status: "completed", headline: "Grab complete")
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
            tokenTasks[activity.attributes.requestID]?.cancel()
            tokenTasks[activity.attributes.requestID] = nil
        }
    }
}

private extension GrabStatus {
    var activityStatus: String {
        switch self {
        case .waiting: "open"
        case .accepted: "accepted"
        case .pickingUp: "picking_up"
        case .onTheWay: "on_the_way"
        case .delivered: "delivered"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .expired: "expired"
        }
    }
}
