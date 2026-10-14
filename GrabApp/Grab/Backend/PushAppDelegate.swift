import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let grabAPNSDeviceToken = Notification.Name("grab.apns-device-token")
}

@MainActor
final class PushTokenCenter {
    static let shared = PushTokenCenter()
    private(set) var currentToken: String?

    private init() {}

    func receive(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        NotificationCenter.default.post(name: .grabAPNSDeviceToken, object: nil, userInfo: ["token": token])
    }
}

final class GrabAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushTokenCenter.shared.receive(deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator and unsigned builds commonly land here. Local notifications and Live Activity
        // foreground updates continue to work without an APNs device token.
    }
}
