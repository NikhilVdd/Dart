import ActivityKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct DartClipApp: App {
    @UIApplicationDelegateAdaptor(DartClipDelegate.self) private var appDelegate
    @State private var invocation = ClipInvocation.fallback

    var body: some Scene {
        WindowGroup {
            DartClipView(invocation: invocation)
                .preferredColorScheme(.light)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { invocation = ClipInvocation(url: url) }
                }
        }
    }
}

final class DartClipDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        ClipPushTokenCenter.shared.currentToken = token
        NotificationCenter.default.post(name: .dartClipAPNSToken, object: nil, userInfo: ["token": token])
    }
}

extension DartClipDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

private extension Notification.Name {
    static let dartClipAPNSToken = Notification.Name("dart.clip-apns-token")
}

@MainActor
private final class ClipPushTokenCenter {
    static let shared = ClipPushTokenCenter()
    var currentToken: String?
}

struct ClipInvocation: Equatable {
    let requestID: String
    let title: String
    let pickup: String
    let destination: String
    let status: String
    let trackingSecret: String?

    static let fallback = ClipInvocation(
        requestID: "preview",
        title: "Your Dart delivery",
        pickup: "Pickup",
        destination: "Drop-off",
        status: "accepted",
        trackingSecret: nil
    )

    init(requestID: String, title: String, pickup: String, destination: String, status: String, trackingSecret: String?) {
        self.requestID = requestID
        self.title = title
        self.pickup = pickup
        self.destination = destination
        self.status = status
        self.trackingSecret = trackingSecret
    }

    init(url: URL) {
        let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { values.first(where: { $0.name == name })?.value }
        self.init(
            requestID: value("request") ?? "preview",
            title: value("title") ?? "Your Dart delivery",
            pickup: value("pickup") ?? "Pickup",
            destination: value("destination") ?? "Drop-off",
            status: value("status") ?? "accepted",
            trackingSecret: value("tracking")
        )
    }
}

private struct DartClipView: View {
    let invocation: ClipInvocation
    @State private var tracking = false
    @State private var message: String?

    var body: some View {
        ZStack {
            Color(red: 0.961, green: 0.965, blue: 0.945).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                Text("D").font(.title.bold()).foregroundStyle(.black).frame(width: 54, height: 54)
                    .background(Color.dartLime, in: RoundedRectangle(cornerRadius: 16))
                Text("Track your Dart").font(.largeTitle.bold())
                Text(invocation.title).font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 12) {
                    Label(invocation.pickup, systemImage: "bag")
                    Label(invocation.destination, systemImage: "mappin.and.ellipse")
                }
                .foregroundStyle(.secondary)
                Button { Task { await startTracking() } } label: {
                    Label(tracking ? "Live status added" : "Add live status", systemImage: tracking ? "checkmark" : "wave.3.right")
                        .font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Color.dartLime, in: RoundedRectangle(cornerRadius: 18))
                }
                .disabled(tracking)
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                Link("Open the full Dart app", destination: URL(string: "dart://request/\(invocation.requestID)")!)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.dartLimeDeep)
            }
            .padding(24)
        }
        .task { await registerAlertTokenIfAvailable() }
        .onReceive(NotificationCenter.default.publisher(for: .dartClipAPNSToken)) { note in
            guard let token = note.userInfo?["token"] as? String else { return }
            Task { await register(token: token, kind: "alert") }
        }
    }

    private func startTracking() async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            message = "Live Activities are disabled in Settings."
            return
        }
        do {
            let attributes = DartDeliveryAttributes(
                requestID: invocation.requestID,
                title: invocation.title,
                pickup: invocation.pickup,
                destination: invocation.destination,
                role: "viewer"
            )
            let state = DartDeliveryAttributes.ContentState.make(status: invocation.status, headline: "Your Dart is active")
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60)),
                pushType: .token
            )
            observePushToken(for: activity)
            tracking = true
            message = invocation.trackingSecret == nil
                ? "Live status was added. Open a real Dart tracking link for remote updates."
                : "Updates can appear on your Lock Screen and Dynamic Island."
        } catch {
            message = "Dart couldn’t add the Live Activity. Please try again."
        }
    }

    private func observePushToken(for activity: Activity<DartDeliveryAttributes>) {
        Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                await register(token: token, kind: "liveactivity")
            }
        }
    }

    private func registerAlertTokenIfAvailable() async {
        if let token = ClipPushTokenCenter.shared.currentToken {
            await register(token: token, kind: "alert")
        }
    }

    private func register(token: String, kind: String) async {
        guard let secret = invocation.trackingSecret else { return }
        do {
            try await DartClipPushRegistrar.register(
                token: token,
                kind: kind,
                requestID: invocation.requestID,
                trackingSecret: secret
            )
        } catch {
            message = "Live status is on, but background updates could not be connected yet."
        }
    }
}

private enum DartClipPushRegistrar {
    static func register(token: String, kind: String, requestID: String, trackingSecret: String) async throws {
        guard let plistURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
              let values = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let base = values["SUPABASE_URL"] as? String,
              let baseURL = URL(string: base),
              let anonKey = values["SUPABASE_ANON_KEY"] as? String else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/register-clip-push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "request_id": requestID,
            "tracking_secret": trackingSecret,
            "token": token,
            "token_kind": kind,
            "bundle_id": Bundle.main.bundleIdentifier ?? "org.example.dart.Clip",
            "environment": pushEnvironment,
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    private static var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

private extension Color {
    static let dartLime = Color(red: 0.776, green: 1, blue: 0)
    static let dartLimeDeep = Color(red: 0.345, green: 0.463, blue: 0)
}
