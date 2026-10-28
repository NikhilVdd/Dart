import SwiftUI

/// Features cut from v1. Their code stays so they can be turned back on.
enum DartFeatures {
    static let groups = false
}

@MainActor
final class AppState: ObservableObject {
    private enum Key {
        static let appearance = "dart.appearance.v1"
        static let selectedTab = "dart.selectedTab.v1"
    }

    @Published var appearance: AppearanceChoice { didSet { save(appearance.rawValue, key: Key.appearance) } }
    /// Nil until someone picks a side on the first screen. Changing it opens that role's first tab.
    @Published var role: AppRole? {
        didSet {
            UserDefaults.standard.set(role?.rawValue, forKey: AppRole.defaultsKey)
            if role != oldValue { selectedTab = 0 }
        }
    }
    /// A darter only sees open orders and new-order alerts while online.
    @Published var darterOnline: Bool { didSet { save(darterOnline, key: AppRole.onlineKey) } }
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

    /// Every role shell has three tabs.
    static let tabCount = 3

    init(defaults: UserDefaults = .standard) {
        let scenario = ProcessInfo.processInfo.environment["DART_SCREENSHOT_SCENARIO"]
        self.screenshotScenario = scenario

        switch scenario {
        case "choose-role":
            self.appearance = .light
            self.role = nil
            self.darterOnline = false
            self.selectedTab = 0
        case "home-request":
            self.appearance = .light
            self.role = .requester
            self.darterOnline = false
            self.selectedTab = 0
        case "home-earn":
            self.appearance = .light
            self.role = .darter
            self.darterOnline = true
            self.selectedTab = 0
        case "activity":
            self.appearance = .light
            self.role = .requester
            self.darterOnline = false
            self.selectedTab = 1
        case "profile":
            self.appearance = .light
            self.role = .requester
            self.darterOnline = false
            self.selectedTab = 2
        case "checkout":
            self.appearance = .light
            self.role = .requester
            self.darterOnline = false
            self.selectedTab = 0
            self.creating = .request(.monsoonKitchens)
        case "order-detail":
            self.appearance = .light
            self.role = .requester
            self.darterOnline = false
            self.selectedTab = 0
            self.openItem = PreviewData.shampoo
        case "earn-offline":
            self.appearance = .light
            self.role = .darter
            self.darterOnline = false
            self.selectedTab = 0
        case "earnings":
            self.appearance = .light
            self.role = .darter
            self.darterOnline = true
            self.selectedTab = 1
        case "dark-home":
            self.appearance = .dark
            self.role = .darter
            self.darterOnline = true
            self.selectedTab = 0
        default:
            self.appearance = AppearanceChoice(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
            self.role = AppRole(rawValue: defaults.string(forKey: AppRole.defaultsKey) ?? "")
            self.darterOnline = defaults.bool(forKey: AppRole.onlineKey)
            self.selectedTab = min(defaults.object(forKey: Key.selectedTab) as? Int ?? 0, Self.tabCount - 1)
        }
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// The tab that lists your orders (requester) or current deliveries (darter).
    var ordersTab: Int { role == .darter ? 0 : 1 }

    func resetDemo() {
        appearance = .system
        role = nil
        darterOnline = false
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
