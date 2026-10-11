import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private enum Key {
        static let appearance = "grab.restart.appearance"
        static let homeMode = "grab.restart.homeMode"
        static let activityMode = "grab.restart.activityMode"
        static let selectedTab = "grab.restart.selectedTab"
    }

    @Published var appearance: AppearanceChoice { didSet { save(appearance.rawValue, key: Key.appearance) } }
    @Published var homeMode: HomeMode { didSet { save(homeMode.rawValue, key: Key.homeMode) } }
    @Published var activityMode: ActivityMode { didSet { save(activityMode.rawValue, key: Key.activityMode) } }
    @Published var selectedTab: Int { didSet { save(selectedTab, key: Key.selectedTab) } }
    @Published var resetConfirmation = false

    let campus = "UC Berkeley"
    let profileName = "Nikhil"
    let building = "The Durant"

    init(defaults: UserDefaults = .standard) {
        self.appearance = AppearanceChoice(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        self.homeMode = HomeMode(rawValue: defaults.string(forKey: Key.homeMode) ?? "") ?? .request
        self.activityMode = ActivityMode(rawValue: defaults.string(forKey: Key.activityMode) ?? "") ?? .requesting
        self.selectedTab = defaults.object(forKey: Key.selectedTab) as? Int ?? 0
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resetDemo() {
        appearance = .system
        homeMode = .request
        activityMode = .requesting
        selectedTab = 0
        resetConfirmation = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            resetConfirmation = false
        }
    }

    private func save(_ value: Any, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
