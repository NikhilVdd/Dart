import SwiftUI

/// Shown once, right after a new account's first sign-in: confirm the name other people will see.
/// The account itself already exists (the verified code created it, linked to the email's campus).
struct RegistrationView: View {
    @EnvironmentObject private var store: GrabStore
    @State private var name = ""
    @State private var working = false
    @State private var errorMessage: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 21))
                    .accessibilityHidden(true)
                Text("Welcome to Grab").font(.largeTitle.bold())
                Text("What should people call you? Your name appears on your requests, runs and messages.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let campus = store.campusName {
                    Label("\(campus) · verified by your campus email", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GrabTheme.blue)
                }

                TextField("Full name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .font(.title3)
                    .padding(16)
                    .grabGlass(radius: 18)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await submit() } }
                    .onChange(of: name) { _, _ in if errorMessage != nil { errorMessage = nil } }
                    .accessibilityLabel("Your name")
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { Task { await submit() } } label: {
                    if working {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).frame(height: 56)
                            .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        PrimaryButtonLabel(title: "Continue", icon: "arrow.right")
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(working || validationMessage != nil)
                .opacity(validationMessage == nil || working ? 1 : 0.55)

                Button("Not you? Sign out") { Task { await store.signOut() } }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .disabled(working)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(GrabTheme.pageInset)
            .frame(maxWidth: .infinity)
        }
        .background(GrabBackdrop())
        .onAppear { nameFocused = true }
    }

    private var trimmed: String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Mirrors complete_registration() in migration 20261011000010, which has the final say.
    private var validationMessage: String? {
        if trimmed.isEmpty || trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isSymbol || $0.isWhitespace }) {
            return "Enter your name"
        }
        if trimmed.count > 60 { return "Names can be up to 60 characters" }
        return nil
    }

    private func submit() async {
        guard !working else { return }
        if let validationMessage {
            errorMessage = validationMessage
            return
        }
        working = true
        defer { working = false }
        errorMessage = await store.completeRegistration(name: trimmed)
    }
}

/// Shown while a signed-in account loads, or when it couldn't be loaded.
struct AccountStatusView: View {
    @EnvironmentObject private var store: GrabStore
    let failed: Bool
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 18) {
            if failed {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Couldn’t load your account").font(.title2.bold())
                Text("Check your connection and try again.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task {
                        retrying = true
                        await store.retryProfile()
                        retrying = false
                    }
                } label: {
                    if retrying {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).frame(height: 56)
                            .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 18))
                    } else {
                        PrimaryButtonLabel(title: "Try again", icon: "arrow.clockwise")
                    }
                }
                .buttonStyle(PressableStyle())
                .disabled(retrying)
                .frame(maxWidth: 360)
                Button("Sign out") { Task { await store.signOut() } }
                    .font(.subheadline.weight(.semibold))
                    .disabled(retrying)
            } else {
                ProgressView().controlSize(.large)
                Text("Loading your account…").foregroundStyle(.secondary)
            }
        }
        .padding(GrabTheme.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GrabBackdrop())
    }
}
