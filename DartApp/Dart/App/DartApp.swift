import SwiftUI

@main
struct GrabApp: App {
    @UIApplicationDelegateAdaptor(GrabAppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var store = GrabStore()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(state)
                .environmentObject(store)
                .preferredColorScheme(state.colorScheme)
                .onOpenURL { url in
                    guard url.scheme == "grab", url.host == "request" else { return }
                    state.selectedTab = 2
                }
        }
    }
}
