import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum DartTheme {
    // Dart's palette follows dartme.org: white paper, near-black ink, electric lime for actions,
    // a pale lime wash for selection, and a deep olive for lime-toned text and icons on white.
    // The app runs in light appearance; the dark values only keep system-forced contexts legible.
    static let background = adaptive(light: (0.961, 0.965, 0.945), dark: (0.031, 0.039, 0.031))   // #F5F6F1 paper
    static let surface = adaptive(light: (1, 1, 1), dark: (0.067, 0.078, 0.067))
    static let surfaceRaised = adaptive(light: (0.949, 0.953, 0.922), dark: (0.090, 0.106, 0.090)) // #F2F3EB
    static let line = adaptive(light: (0.875, 0.890, 0.843), dark: (0.165, 0.188, 0.165))          // #DFE3D7
    static let text = adaptive(light: (0.031, 0.043, 0.035), dark: (0.969, 0.976, 0.961))          // #080B09 ink
    static let muted = adaptive(light: (0.376, 0.404, 0.376), dark: (0.576, 0.608, 0.576))         // #606760
    static let lime = Color(red: 0.776, green: 1.0, blue: 0.0)           // #C6FF00
    static let limeSoft = Color(red: 0.659, green: 0.902, blue: 0.0)     // #A8E600
    static let limeWash = Color(red: 0.949, green: 1.0, blue: 0.816)     // #F2FFD0
    static let limeDeep = Color(red: 0.345, green: 0.463, blue: 0.0)     // #587600
    static let limeInk = Color(red: 0.031, green: 0.043, blue: 0.035)    // #080B09
    static let warning = Color(red: 0.86, green: 0.50, blue: 0.02)
    static let danger = Color(red: 0.651, green: 0.212, blue: 0.247)     // #A6363F

    static let blue = limeDeep
    static let brightBlue = limeSoft
    static let paleBlue = lime
    static let gold = limeDeep
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

/// Dart's mark from dartme.org: a D with a forward arrow cut into its counter.
struct DartMark: View {
    var size: CGFloat = 58
    /// Draw on an ink rounded square (app-icon style) instead of bare.
    var tiled = true

    var body: some View {
        ZStack {
            if tiled {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(DartTheme.limeInk)
            }
            DartMarkShape(part: .outer).fill(DartTheme.lime)
            DartMarkShape(part: .counter).fill(tiled ? DartTheme.limeInk : DartTheme.surface)
            DartMarkShape(part: .arrow).fill(DartTheme.lime)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Dart")
    }
}

private struct DartMarkShape: Shape {
    enum Part { case outer, counter, arrow }
    let part: Part

    func path(in rect: CGRect) -> Path {
        // The mark spans 29×28 units of the original viewBox; scale it to ~60% of the frame.
        let s = min(rect.width, rect.height) * 0.6 / 29
        let ox = rect.midX - 21.5 * s, oy = rect.midY - 21 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path()
        switch part {
        case .outer:
            path.move(to: p(7, 7)); path.addLine(to: p(18.2, 7))
            path.addCurve(to: p(36, 21), control1: p(28.7, 7), control2: p(36, 12.2))
            path.addCurve(to: p(18.2, 35), control1: p(36, 29.8), control2: p(28.7, 35))
            path.addLine(to: p(7, 35))
        case .counter:
            path.move(to: p(13.5, 13.2)); path.addLine(to: p(18.4, 13.2))
            path.addCurve(to: p(29.2, 21), control1: p(25.1, 13.2), control2: p(29.2, 15.8))
            path.addCurve(to: p(18.4, 28.8), control1: p(29.2, 26.2), control2: p(25.1, 28.8))
            path.addLine(to: p(13.5, 28.8))
        case .arrow:
            path.move(to: p(19.2, 16.5)); path.addLine(to: p(28.4, 21)); path.addLine(to: p(19.2, 25.5))
        }
        path.closeSubpath()
        return path
    }
}

struct DartBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shifted = false

    var body: some View {
        ZStack {
            DartTheme.background
            Circle()
                .fill(DartTheme.lime.opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: shifted ? 130 : -110, y: shifted ? -240 : -120)
            Circle()
                .fill(DartTheme.limeWash.opacity(0.9))
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
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DartTheme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(DartTheme.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 20, y: 10)
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
            .shadow(color: DartTheme.limeDeep.opacity(0.16), radius: 16, y: 8)
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
                .fill(highlighted ? DartTheme.lime : DartTheme.limeWash)
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

struct DartNumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 8) {
            stepButton(symbol: "minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - 1)
            }
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(DartTheme.text)
                .frame(minWidth: 30)
                .accessibilityHidden(true)
            stepButton(symbol: "plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + 1)
            }
        }
        .padding(5)
        .background(DartTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(DartTheme.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + 1)
            case .decrement: value = max(range.lowerBound, value - 1)
            @unknown default: break
            }
        }
    }

    private func stepButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.heavy))
                .foregroundStyle(enabled ? DartTheme.limeInk : DartTheme.muted)
                .frame(width: 34, height: 34)
                .background(enabled ? DartTheme.lime : DartTheme.surfaceRaised, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
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
                        .foregroundStyle(selection == item ? DartTheme.limeInk : DartTheme.muted)
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
            .foregroundStyle(status == .completed ? DartTheme.limeDeep : DartTheme.limeInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(status == .completed ? DartTheme.limeWash : DartTheme.lime.opacity(0.35), in: Capsule())
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

    /// Dart's own bottom presentation. It keeps native SwiftUI focus and accessibility behavior,
    /// but replaces the system sheet chrome, detents, dimming, and motion with our visual language.
    func dartModal<Modal: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Modal) -> some View {
        modifier(DartModalModifier(isPresented: isPresented, modal: content))
    }

    func dartModal<Item: Identifiable, Modal: View>(item: Binding<Item?>,
                                                     @ViewBuilder content: @escaping (Item) -> Modal) -> some View {
        modifier(DartItemModalModifier(item: item, modal: content))
    }

    /// Centered branded dialog for confirmations, errors, and compact input prompts.
    func dartDialog<Dialog: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Dialog) -> some View {
        modifier(DartDialogModifier(isPresented: isPresented, dialog: content))
    }
}

private struct DartModalModifier<Modal: View>: ViewModifier {
    @Binding var isPresented: Bool
    let modal: () -> Modal

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                DartModalChrome(isPresented: $isPresented, content: modal)
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: isPresented)
    }
}

private struct DartItemModalModifier<Item: Identifiable, Modal: View>: ViewModifier {
    @Binding var item: Item?
    let modal: (Item) -> Modal

    func body(content: Content) -> some View {
        content.overlay {
            if let value = item {
                DartModalChrome(isPresented: Binding(
                    get: { item != nil },
                    set: { if !$0 { item = nil } }
                )) {
                    modal(value)
                }
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: item?.id)
    }
}

private struct DartModalChrome<Content: View>: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragY: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .transition(.opacity)
                VStack(spacing: 0) {
                    Capsule()
                        .fill(DartTheme.line)
                        .frame(width: 42, height: 5)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .updating($dragY) { value, state, _ in state = max(0, value.translation.height) }
                                .onEnded { value in if value.translation.height > 120 { isPresented = false } }
                        )
                        .accessibilityLabel("Dismiss")
                        .accessibilityAddTraits(.isButton)
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .environment(\.dartDismiss, DartDismissAction { isPresented = false })
                }
                .frame(maxWidth: 620)
                .frame(height: max(360, proxy.size.height * 0.92))
                .background(DartTheme.surface)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30).stroke(DartTheme.line))
                .shadow(color: .black.opacity(0.12), radius: 30, y: -6)
                .offset(y: max(0, dragY))
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityAddTraits(.isModal)
    }
}

struct DartDismissAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct DartDismissActionKey: EnvironmentKey {
    static let defaultValue = DartDismissAction(action: {})
}

extension EnvironmentValues {
    var dartDismiss: DartDismissAction {
        get { self[DartDismissActionKey.self] }
        set { self[DartDismissActionKey.self] = newValue }
    }
}

private struct DartDialogModifier<Dialog: View>: ViewModifier {
    @Binding var isPresented: Bool
    let dialog: () -> Dialog

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.30).ignoresSafeArea()
                    dialog()
                        .frame(maxWidth: 440)
                        .padding(20)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(200)
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPresented)
    }
}

struct DartAlertCard: View {
    let symbol: String
    let title: String
    let message: String
    let primaryTitle: String
    var primaryIsDestructive = false
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DartIconTile(symbol: symbol, size: 58, highlighted: !primaryIsDestructive)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                Text(message).font(.subheadline).foregroundStyle(DartTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Text(primaryTitle).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .foregroundStyle(primaryIsDestructive ? Color.white : DartTheme.limeInk)
                        .background(primaryIsDestructive ? DartTheme.danger : DartTheme.lime,
                                    in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                }
                .buttonStyle(PressableStyle())
                if let secondaryTitle {
                    Button(secondaryTitle) { secondaryAction?() }
                        .font(.headline)
                        .foregroundStyle(DartTheme.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                        .buttonStyle(PressableStyle())
                }
            }
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.12), radius: 26, y: 12)
    }
}
