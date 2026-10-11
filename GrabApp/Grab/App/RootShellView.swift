import SwiftUI

struct RootShellView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch state.selectedTab {
                case 1: GroupsView()
                case 2: ActivityView()
                case 3: ProfileView()
                default: HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $state.selectedTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .overlay {
            if state.resetConfirmation {
                ResetSuccessView()
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85), value: state.resetConfirmation)
    }
}

private struct FloatingTabBar: View {
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    private let tabs = [
        ("Home", "house.fill"),
        ("Groups", "person.2.fill"),
        ("Activity", "clock.arrow.circlepath"),
        ("Profile", "person.crop.circle.fill")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.indices, id: \.self) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) { selection = index }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].1).font(.system(size: 18, weight: .semibold))
                        Text(tabs[index].0).font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(selection == index ? Color.white : Color.primary.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selection == index {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(GrabTheme.blue.gradient)
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tabs[index].0)
                .accessibilityAddTraits(selection == index ? .isSelected : [])
            }
        }
        .padding(5)
        .grabGlass(radius: 22)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct ResetSuccessView: View {
    @State private var draw = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(GrabTheme.gold)
                .scaleEffect(draw ? 1 : 0.55)
            Text("Demo reset").font(.headline)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .grabGlass()
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65)) { draw = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo reset successfully")
    }
}
