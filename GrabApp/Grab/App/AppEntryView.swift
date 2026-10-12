import SwiftUI

/// Routes a configured build through authentication while preserving the sample-data preview.
struct AppEntryView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: GrabStore
    @State private var isBrowsingPreview = false

    private var showsApp: Bool {
        store.isLive || !store.isConfigured || isBrowsingPreview || state.screenshotScenario != nil
    }

    var body: some View {
        Group {
            if showsApp {
                RootShellView()
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
            } else {
                WelcomeView { isBrowsingPreview = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showsApp)
        .onChange(of: store.isLive) { _, isLive in
            if isLive { isBrowsingPreview = false }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var store: GrabStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSignIn = false
    @State private var animate = false
    let browsePreview: () -> Void

    var body: some View {
        ZStack {
            GrabBackdrop()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 54)

                    ZStack {
                        Circle()
                            .fill(GrabTheme.brightBlue.opacity(0.14))
                            .frame(width: 156, height: 156)
                            .scaleEffect(animate ? 1.06 : 0.94)
                        Image(systemName: "shippingbox.and.arrow.backward.fill")
                            .font(.system(size: 47, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 104)
                            .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .shadow(color: GrabTheme.blue.opacity(0.28), radius: 24, y: 14)
                    }
                    .accessibilityHidden(true)

                    Text("Grab")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .padding(.top, 22)

                    Text("Get what you need from people\nalready heading your way.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 15) {
                        WelcomeBenefit(icon: "location.fill", title: "Nearby by default", detail: "Requests and store runs stay local to your campus.")
                        WelcomeBenefit(icon: "person.2.fill", title: "People you can reach", detail: "Coordinate in groups and chat with your helper.")
                        WelcomeBenefit(icon: "checkmark.seal.fill", title: "Track every handoff", detail: "Follow progress from accepted to confirmed.")
                    }
                    .padding(20)
                    .grabGlass()
                    .padding(.top, 32)

                    Button { showSignIn = true } label: {
                        PrimaryButtonLabel(title: "Continue with campus email", icon: "envelope.fill")
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 24)

                    Button(action: browsePreview) {
                        Text("Explore the sample app")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GrabTheme.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(PressableStyle())

                    Text("By continuing, you agree to use Grab respectfully within your campus community.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    Spacer(minLength: 30)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, GrabTheme.pageInset)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

private struct WelcomeBenefit: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(GrabTheme.blue)
                .frame(width: 42, height: 42)
                .background(GrabTheme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
