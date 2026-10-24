import SwiftUI

enum DartTheme {
    // Canonical values mirror web-preview/src/styles.css. The legacy names remain as aliases
    // while feature views are migrated so this checkpoint stays buildable.
    static let background = Color(red: 0.031, green: 0.039, blue: 0.031) // #080A08
    static let surface = Color(red: 0.067, green: 0.078, blue: 0.067)    // #111411
    static let surfaceRaised = Color(red: 0.090, green: 0.106, blue: 0.090)
    static let line = Color(red: 0.165, green: 0.188, blue: 0.165)       // #2A302A
    static let text = Color(red: 0.969, green: 0.976, blue: 0.961)       // #F7F9F5
    static let muted = Color(red: 0.576, green: 0.608, blue: 0.576)      // #939B93
    static let lime = Color(red: 0.776, green: 1.0, blue: 0.0)           // #C6FF00
    static let limeSoft = Color(red: 0.659, green: 0.902, blue: 0.0)     // #A8E600
    static let warning = Color(red: 1.0, green: 0.745, blue: 0.333)

    static let blue = lime
    static let brightBlue = limeSoft
    static let paleBlue = lime
    static let gold = warning
    static let navy = background
    static let pearl = background

    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 17
}

struct DartBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shifted = false

    var body: some View {
        ZStack {
            DartTheme.background
            Circle()
                .fill(DartTheme.lime.opacity(0.07))
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
            .shadow(color: .black.opacity(0.30), radius: 24, y: 14)
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
            .foregroundStyle(DartTheme.background)
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
            .foregroundStyle(DartTheme.lime)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DartTheme.lime.opacity(0.10), in: Capsule())
            .accessibilityLabel("Development preview")
    }
}

struct StatusChip: View {
    let status: DartStatus

    var body: some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .completed ? DartTheme.gold : DartTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((status == .completed ? DartTheme.gold : DartTheme.blue).opacity(0.11), in: Capsule())
    }
}

struct AvatarStack: View {
    let initials: [String]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(initials.prefix(3).enumerated()), id: \.offset) { index, initials in
                Text(initials)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background([DartTheme.blue, DartTheme.brightBlue, DartTheme.gold][index % 3], in: Circle())
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
