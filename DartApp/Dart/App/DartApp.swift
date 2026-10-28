import SwiftUI

@main
struct DartApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(DartAppDelegate.self) private var appDelegate
    #endif
    @StateObject private var state = AppState()
    @StateObject private var store = DartStore()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(state)
                .environmentObject(store)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    store.handleDeepLink(url)
                    if url.scheme == "dart", url.host == "request" { state.selectedTab = state.ordersTab }
                }
        }
        #if os(macOS)
        .defaultSize(width: 430, height: 860)
        #endif
    }
}
