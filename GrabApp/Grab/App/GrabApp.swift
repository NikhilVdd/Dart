import SwiftUI

@main
struct GrabApp: App {
    @StateObject private var state = AppState()
    @StateObject private var store = GrabStore()

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(state)
                .environmentObject(store)
                .preferredColorScheme(state.colorScheme)
        }
    }
}
