import SwiftUI

enum GrabTheme {
    static let blue = Color(red: 0.06, green: 0.32, blue: 0.92)
    static let brightBlue = Color(red: 0.19, green: 0.56, blue: 1.0)
    static let paleBlue = Color(red: 0.80, green: 0.90, blue: 1.0)
    static let gold = Color(red: 0.82, green: 0.61, blue: 0.17)
    static let navy = Color(red: 0.035, green: 0.09, blue: 0.20)
    static let pearl = Color(red: 0.965, green: 0.975, blue: 0.995)

    static let pageInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 17
}

struct GrabBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shifted = false

    var body: some View {
        ZStack {
            (colorScheme == .dark ? GrabTheme.navy : GrabTheme.pearl)
            Circle()
                .fill(GrabTheme.brightBlue.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: shifted ? 130 : -110, y: shifted ? -240 : -120)
            Circle()
                .fill(GrabTheme.paleBlue.opacity(colorScheme == .dark ? 0.09 : 0.42))
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
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(reduceTransparency
                          ? (colorScheme == .dark ? Color(red: 0.08, green: 0.13, blue: 0.23) : .white)
                          : Color.clear)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.13 : 0.72), lineWidth: 0.8)
            }
            .shadow(color: GrabTheme.blue.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 22, y: 12)
    }
}

extension View {
    func grabGlass(radius: CGFloat = GrabTheme.cardRadius) -> some View {
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
            .foregroundStyle(.white)
            .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: GrabTheme.controlRadius, style: .continuous))
            .shadow(color: GrabTheme.blue.opacity(0.25), radius: 16, y: 8)
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
            .foregroundStyle(GrabTheme.blue)
            .grabGlass(radius: GrabTheme.controlRadius)
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
                        .foregroundStyle(selection == item ? Color.white : Color.primary.opacity(0.72))
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(GrabTheme.blue.gradient)
                                    .matchedGeometryEffect(id: "segment", in: selectionAnimation)
                            }
                        }
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(4)
        .grabGlass(radius: GrabTheme.controlRadius)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct PreviewPill: View {
    var text = "DEVELOPMENT PREVIEW"

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1.1)
            .foregroundStyle(GrabTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(GrabTheme.paleBlue.opacity(0.42), in: Capsule())
            .accessibilityLabel("Development preview")
    }
}

struct StatusChip: View {
    let status: GrabStatus

    var body: some View {
        Label(status.rawValue, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status == .completed ? GrabTheme.gold : GrabTheme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((status == .completed ? GrabTheme.gold : GrabTheme.blue).opacity(0.11), in: Capsule())
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
                    .background([GrabTheme.blue, GrabTheme.brightBlue, GrabTheme.gold][index % 3], in: Circle())
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
            Image(systemName: "sparkles").font(.title2).foregroundStyle(GrabTheme.blue)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .grabGlass()
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
                ProgressView().tint(GrabTheme.blue)
            } else {
                Image(systemName: state.symbol).font(.title2).foregroundStyle(GrabTheme.blue)
            }
            Text(state.title).font(.headline)
            Text(state.message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .grabGlass()
        .accessibilityElement(children: .combine)
    }
}
