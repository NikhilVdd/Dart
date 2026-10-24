import SwiftUI

struct RootShellView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch store.phase {
            case .launching:
                LaunchLoadingView()
            case .signedOut:
                SignInView(allowsDismiss: false)
            case .unconfigured:
                ConfigurationRequiredView()
            case .preview, .live:
                appShell
            }
        }
        .sheet(isPresented: Binding(
            get: { store.requiresPasswordUpdate },
            set: { if !$0 { store.dismissPasswordUpdate() } }
        )) {
            PasswordUpdateView()
        }
        .dartOnboardingCover(isPresented: Binding(
            get: { store.needsOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    private var appShell: some View {
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

private extension View {
    @ViewBuilder
    func dartOnboardingCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            DartBackdrop()
            VStack(spacing: 16) {
                Text("D")
                    .font(.title.bold())
                    .foregroundStyle(DartTheme.background)
                    .frame(width: 58, height: 58)
                    .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: 18))
                ProgressView().tint(DartTheme.lime)
                Text("Opening Dart").font(.headline).foregroundStyle(DartTheme.text)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Opening Dart")
    }
}

private struct ConfigurationRequiredView: View {
    var body: some View {
        ZStack {
            DartBackdrop()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 42)).foregroundStyle(DartTheme.warning)
                Text("Dart isn’t configured").font(.title2.bold())
                Text("This release is missing its Supabase environment. Install a correctly signed staging or production build.")
                    .font(.body).foregroundStyle(DartTheme.muted).multilineTextAlignment(.center)
            }
            .padding(28)
            .dartSurface()
            .padding(24)
        }
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
                    .foregroundStyle(selection == index ? DartTheme.background : DartTheme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selection == index {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DartTheme.lime)
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
        .dartSurface(radius: 22)
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
                .foregroundStyle(DartTheme.gold)
                .scaleEffect(draw ? 1 : 0.55)
            Text("Demo reset").font(.headline)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .dartSurface()
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65)) { draw = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo reset successfully")
    }
}
