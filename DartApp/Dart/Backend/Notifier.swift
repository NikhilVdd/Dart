import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

/// Presents local notifications while Dart is open and registers the app with APNs for background
/// delivery. The APNs callback is forwarded to DartStore, which persists the token in Supabase.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var center: UNUserNotificationCenter? {
        // UNUserNotificationCenter traps outside an app bundle (e.g. unit tests or `swift run`).
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            #if canImport(UIKit)
            Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() }
            #endif
        }
    }

    func post(_ title: String, _ body: String, id: String = UUID().uuidString, route: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let route { content.userInfo["deep_link"] = route }
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Show banners while the app is open too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let route = (info["deep_link"] ?? info["url"]) as? String {
            Task { @MainActor in
                NotificationCenter.default.post(name: .dartNotificationRoute, object: nil, userInfo: ["route": route])
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let dartNotificationRoute = Notification.Name("dart.notification.route")
}
