import SwiftUI

struct RootShellView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var quickCreate = false
    @State private var creating: CreateSheet.Destination?

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
                case 1: ExploreView()
                case 2: ActivityView()
                case 3: ProfileView()
                default: HomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $state.selectedTab) { quickCreate = true }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $quickCreate) {
            QuickCreateSheet { destination in
                quickCreate = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    creating = destination
                }
            }
        }
        .sheet(item: $creating) { CreateSheet(destination: $0) }
        .sheet(item: Binding(
            get: { store.routedItem },
            set: { if $0 == nil { store.consumeRoutedItem() } }
        )) { ItemDetailView(item: $0) }
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
                    .foregroundStyle(DartTheme.limeInk)
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
    let onCreate: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    private let tabs = [
        ("Home", "house.fill"),
        ("Explore", "safari.fill"),
        ("Activity", "clock.fill"),
        ("You", "person.crop.circle.fill")
    ]

    var body: some View {
        HStack(spacing: 3) {
            tabButton(0)
            tabButton(1)
            Button(action: onCreate) {
                VStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .heavy))
                        .frame(width: 48, height: 42)
                        .foregroundStyle(DartTheme.limeInk)
                        .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: DartTheme.lime.opacity(0.30), radius: 12, y: 5)
                    Text("Create").font(.caption2.weight(.bold)).foregroundStyle(DartTheme.text)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Create a Dart")
            tabButton(2)
            tabButton(3)
        }
        .padding(5)
        .dartSurface(radius: 22)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabButton(_ index: Int) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) { selection = index }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tabs[index].1).font(.system(size: 17, weight: .semibold))
                Text(tabs[index].0).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(selection == index ? DartTheme.limeInk : DartTheme.muted)
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

private struct QuickCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let choose: (CreateSheet.Destination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Capsule().fill(DartTheme.line).frame(width: 38, height: 5).frame(maxWidth: .infinity)
            Text("What’s happening?")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(DartTheme.text)
            Text("Post what you need or let campus know you’re already heading somewhere.")
                .font(.subheadline)
                .foregroundStyle(DartTheme.muted)

            createCard(title: "Request something", subtitle: "Food, groceries, pickups, and campus errands", icon: "bag.fill") {
                choose(.request)
            }
            createCard(title: "I’m heading out", subtitle: "Share a store run with friends, your building, or campus", icon: "figure.walk.motion") {
                choose(.run)
            }

            Button("Not now") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .padding(24)
        .background(DartBackdrop())
        .presentationDetents([.height(455)])
        .presentationDragIndicator(.hidden)
        .macSheetSize(minHeight: 455)
    }

    private func createCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                DartIconTile(symbol: icon, size: 60, highlighted: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.weight(.bold)).foregroundStyle(DartTheme.text)
                    Text(subtitle).font(.subheadline).foregroundStyle(DartTheme.muted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "arrow.right").font(.headline.bold()).foregroundStyle(DartTheme.limeInk)
            }
            .padding(18)
            .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(DartTheme.line))
        }
        .buttonStyle(PressableStyle())
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
