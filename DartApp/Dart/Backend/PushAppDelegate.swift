import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

extension Notification.Name {
    static let dartAPNSDeviceToken = Notification.Name("dart.apns-device-token")
}

@MainActor
final class PushTokenCenter {
    static let shared = PushTokenCenter()
    private(set) var currentToken: String?

    private init() {}

    func receive(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        NotificationCenter.default.post(name: .dartAPNSDeviceToken, object: nil, userInfo: ["token": token])
    }
}

#if canImport(UIKit)
final class DartAppDelegate: NSObject, UIApplicationDelegate {
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
#else
final class DartAppDelegate: NSObject {}
#endif
