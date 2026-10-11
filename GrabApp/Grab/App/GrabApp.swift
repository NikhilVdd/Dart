import SwiftUI

@main
struct GrabApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
        }
    }
}
