import SwiftUI

@main
struct GrabApp: App {
    @StateObject private var state = AppState()
    @StateObject private var store = GrabStore()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(state)
                .environmentObject(store)
                .preferredColorScheme(state.colorScheme)
        }
    }
}
