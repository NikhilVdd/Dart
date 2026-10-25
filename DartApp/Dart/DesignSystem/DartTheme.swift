import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum DartTheme {
    // Dart stays lime-led and white-first while retaining a deliberate dark appearance. These
    // semantic colors keep custom components legible without falling back to generic Form styling.
    static let background = adaptive(light: (0.975, 0.982, 0.969), dark: (0.031, 0.039, 0.031))
    static let surface = adaptive(light: (1, 1, 1), dark: (0.067, 0.078, 0.067))
    static let surfaceRaised = adaptive(light: (0.945, 0.958, 0.936), dark: (0.090, 0.106, 0.090))
    static let line = adaptive(light: (0.845, 0.872, 0.824), dark: (0.165, 0.188, 0.165))
    static let text = adaptive(light: (0.035, 0.047, 0.035), dark: (0.969, 0.976, 0.961))
    static let muted = adaptive(light: (0.34, 0.39, 0.34), dark: (0.576, 0.608, 0.576))
    static let lime = Color(red: 0.776, green: 1.0, blue: 0.0)           // #C6FF00
    static let limeSoft = Color(red: 0.659, green: 0.902, blue: 0.0)     // #A8E600
    static let limeInk = Color(red: 0.08, green: 0.12, blue: 0.02)
    static let warning = Color(red: 1.0, green: 0.64, blue: 0.12)
    static let danger = Color(red: 0.92, green: 0.20, blue: 0.22)

    static let blue = lime
    static let brightBlue = limeSoft
    static let paleBlue = lime
    static let gold = warning
    static let navy = background
    static let pearl = background

    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 17

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

struct DartBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shifted = false

    var body: some View {
        ZStack {
            DartTheme.background
            Circle()
                .fill(DartTheme.lime.opacity(0.12))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: shifted ? 130 : -110, y: shifted ? -240 : -120)
            Circle()
                .fill(DartTheme.limeSoft.opacity(0.035))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: shifted ? -120 : 100, y: shifted ? 340 : 220)
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { shifted = true }
        }
    }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(reduceTransparency ? DartTheme.surface : DartTheme.surface.opacity(0.94))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DartTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
    }
}

extension View {
    func dartSurface(radius: CGFloat = DartTheme.cardRadius) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct PrimaryButtonLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(DartTheme.limeInk)
            .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius, style: .continuous))
            .shadow(color: DartTheme.lime.opacity(0.16), radius: 18, y: 10)
    }
}

struct SecondaryButtonLabel: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(DartTheme.text)
            .dartSurface(radius: DartTheme.controlRadius)
    }
}

struct DartIconTile: View {
    let symbol: String
    var size: CGFloat = 48
    var highlighted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(highlighted ? DartTheme.lime : DartTheme.lime.opacity(0.15))
            Circle()
                .fill(Color.white.opacity(highlighted ? 0.32 : 0.72))
                .frame(width: size * 0.44, height: size * 0.44)
                .offset(x: size * 0.22, y: -size * 0.22)
            Image(systemName: symbol)
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundStyle(DartTheme.limeInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DartSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(DartTheme.muted)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DartTheme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.controlRadius).stroke(DartTheme.line))
    }
}

struct DartField<Content: View>: View {
    let label: String
    var error: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(error == nil ? DartTheme.muted : DartTheme.danger)
            content()
                .padding(.horizontal, 15)
                .frame(minHeight: 52)
                .background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(error == nil ? DartTheme.line : DartTheme.danger, lineWidth: error == nil ? 1 : 1.5))
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(DartTheme.danger)
            }
        }
    }
}

struct DartProgressRail: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? DartTheme.lime : DartTheme.line)
                    .frame(maxWidth: .infinity)
                    .frame(height: 5)
            }
        }
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

struct SlidingSegmentedControl<Selection: Hashable & RawRepresentable & CaseIterable>: View where Selection.RawValue == String, Selection.AllCases: RandomAccessCollection {
    @Binding var selection: Selection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Selection.allCases), id: \.self) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)) { selection = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(selection == item ? DartTheme.background : DartTheme.muted)
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(DartTheme.lime)
                                    .matchedGeometryEffect(id: "segment", in: selectionAnimation)
                            }
                        }
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(4)
        .dartSurface(radius: DartTheme.controlRadius)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct PreviewPill: View {
    var text = "DEVELOPMENT PREVIEW"

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(DartTheme.limeInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DartTheme.lime.opacity(0.72), in: Capsule())
            .accessibilityLabel("Development preview")
    }
}

struct StatusChip: View {
    let status: DartStatus

    var body: some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .completed ? DartTheme.warning : DartTheme.limeInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((status == .completed ? DartTheme.warning : DartTheme.lime).opacity(0.18), in: Capsule())
    }
}

struct AvatarStack: View {
    let initials: [String]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(initials.prefix(3).enumerated()), id: \.offset) { index, initials in
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(index == 0 ? DartTheme.limeInk : Color.white)
                    .frame(width: 34, height: 34)
                    .background([DartTheme.lime, DartTheme.limeInk, DartTheme.warning][index % 3], in: Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Members: \(initials.joined(separator: ", "))")
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.bold())
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title2).foregroundStyle(DartTheme.blue)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .dartSurface()
    }
}

enum ContentState: Equatable {
    case loading
    case empty
    case error

    var title: String {
        switch self {
        case .loading: "Loading nearby activity"
        case .empty: "Nothing here yet"
        case .error: "Couldn’t load activity"
        }
    }

    var message: String {
        switch self {
        case .loading: "This should only take a moment."
        case .empty: "New requests and runs will appear here."
        case .error: "Check your connection and try again."
        }
    }

    var symbol: String {
        switch self {
        case .loading: "arrow.triangle.2.circlepath"
        case .empty: "sparkles"
        case .error: "exclamationmark.triangle"
        }
    }
}

struct ContentStateCard: View {
    let state: ContentState

    var body: some View {
        VStack(spacing: 12) {
            if state == .loading {
                ProgressView().tint(DartTheme.blue)
            } else {
                Image(systemName: state.symbol).font(.title2).foregroundStyle(DartTheme.blue)
            }
            Text(state.title).font(.headline)
            Text(state.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .dartSurface()
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// macOS sizes sheets to their content, and lists, scroll views and maps have none, so sheets
    /// collapse. Give them a phone-like minimum there; no effect on iOS.
    @ViewBuilder
    func macSheetSize(minWidth: CGFloat = 440, minHeight: CGFloat = 620) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: minWidth + 40, minHeight: minHeight, idealHeight: minHeight + 80)
        #else
        self
        #endif
    }
}
