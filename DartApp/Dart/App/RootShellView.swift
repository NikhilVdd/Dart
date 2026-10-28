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
            case .unconfigured:
                ConfigurationRequiredView()
            case _ where state.role == nil:
                RoleChooserView()
            case .signedOut:
                SignInView(allowsDismiss: false)
            case .live where state.role.map { store.profile?.has($0) == false } ?? false:
                RoleGateView(role: state.role!)
            case .preview, .live:
                appShell
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: state.role)
        .dartModal(isPresented: Binding(
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
        .dartDialog(isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            DartAlertCard(symbol: "exclamationmark.triangle.fill", title: "Something went wrong",
                          message: store.lastError ?? "Please try again.", primaryTitle: "Got it") {
                store.lastError = nil
            }
        }
    }

    private var appShell: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch (state.role ?? .requester, state.selectedTab) {
                case (.requester, 1): OrdersView()
                case (.darter, 1): EarningsView()
                case (_, 2): ProfileView()
                case (.requester, _): RequestView()
                case (.darter, _): DeliverView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selection: $state.selectedTab, tabs: tabs)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .dartModal(item: $state.creating) { CreateSheet(destination: $0) }
        .dartModal(item: $state.openItem) { ItemDetailView(item: $0) }
        .dartModal(item: Binding(
            get: { store.routedItem },
            set: { if $0 == nil { store.consumeRoutedItem() } }
        )) { ItemDetailView(item: $0) }
        .onChange(of: store.routedItem?.id) { _, _ in
            // A notification opens its order on the side it belongs to: your own order in the
            // requester app, one you're delivering in the darter app.
            switch store.routedItem?.backend?.role {
            case .owner: state.role = .requester
            case .helper: state.role = .darter
            default: break
            }
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

    private var tabs: [(String, String)] {
        switch state.role ?? .requester {
        case .requester: [("Home", "house.fill"), ("Orders", "bag.fill"), ("Account", "person.crop.circle.fill")]
        case .darter: [("Deliver", "figure.walk"), ("Earnings", "dollarsign.circle.fill"), ("Account", "person.crop.circle.fill")]
        }
    }
}

private extension View {
    @ViewBuilder
    func dartOnboardingCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        dartModal(isPresented: isPresented, content: content)
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            DartBackdrop()
            VStack(spacing: 16) {
                DartMark(size: 64)
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
    /// Title and SF Symbol for each tab.
    let tabs: [(String, String)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 3) {
            ForEach(tabs.indices, id: \.self) { tabButton($0) }
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
