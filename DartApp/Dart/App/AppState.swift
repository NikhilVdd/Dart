import SwiftUI

@MainActor
final class AppState: ObservableObject {
    private enum Key {
        static let appearance = "dart.appearance.v1"
        static let homeMode = "dart.homeMode.v1"
        static let activityMode = "dart.activityMode.v1"
        static let selectedTab = "dart.selectedTab.v1"
    }

    @Published var appearance: AppearanceChoice { didSet { save(appearance.rawValue, key: Key.appearance) } }
    @Published var homeMode: HomeMode { didSet { save(homeMode.rawValue, key: Key.homeMode) } }
    @Published var activityMode: ActivityMode { didSet { save(activityMode.rawValue, key: Key.activityMode) } }
    @Published var selectedTab: Int { didSet { save(selectedTab, key: Key.selectedTab) } }
    @Published var resetConfirmation = false
    /// The create sheet, presented by the root shell so it sits above the tab bar.
    @Published var creating: CreateSheet.Destination?
    /// The order or run whose details are open, presented by the root shell above the tab bar.
    @Published var openItem: DartItem?

    /// Optional development-only override used to capture deterministic simulator screenshots.
    let screenshotScenario: String?

    let campus = "UC Berkeley"
    let profileName = "Nikhil"
    let building = "The Durant"

    init(defaults: UserDefaults = .standard) {
        let scenario = ProcessInfo.processInfo.environment["DART_SCREENSHOT_SCENARIO"]
        self.screenshotScenario = scenario

        switch scenario {
        case "home-request":
            self.appearance = .light
            self.homeMode = .request
            self.activityMode = .requesting
            self.selectedTab = 0
        case "home-earn":
            self.appearance = .light
            self.homeMode = .earn
            self.activityMode = .helping
            self.selectedTab = 0
        case "groups":
            self.appearance = .light
            self.homeMode = .request
            self.activityMode = .requesting
            self.selectedTab = 1
        case "activity":
            self.appearance = .light
            self.homeMode = .request
            self.activityMode = .helping
            self.selectedTab = 2
        case "profile":
            self.appearance = .light
            self.homeMode = .request
            self.activityMode = .requesting
            self.selectedTab = 3
        case "dark-home":
            self.appearance = .dark
            self.homeMode = .earn
            self.activityMode = .helping
            self.selectedTab = 0
        default:
            self.appearance = AppearanceChoice(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
            self.homeMode = HomeMode(rawValue: defaults.string(forKey: Key.homeMode) ?? "") ?? .request
            self.activityMode = ActivityMode(rawValue: defaults.string(forKey: Key.activityMode) ?? "") ?? .requesting
            self.selectedTab = defaults.object(forKey: Key.selectedTab) as? Int ?? 0
        }
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
