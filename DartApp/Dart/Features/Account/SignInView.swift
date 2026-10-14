import SwiftUI

/// Shown on Home when Supabase is configured but nobody is signed in.
struct SignInBanner: View {
    @State private var showSignIn = false

    var body: some View {
        Button { showSignIn = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(GrabTheme.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in or create an account").font(.headline).foregroundStyle(.primary)
                    Text("Use any email and password to connect to live Dart data.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(18)
            .grabGlass()
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $showSignIn) { SignInView() }
    }
}

/// Standard Supabase email/password authentication. Campus assignment happens in the backend,
/// so account creation accepts any valid email address.
struct SignInView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case createAccount = "Create account"

        var id: Self { self }
    }

    @EnvironmentObject private var store: GrabStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: mode == .signIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 21))

                    VStack(alignment: .leading, spacing: 7) {
                        Text(mode == .signIn ? "Welcome back" : "Create your Dart account")
                            .font(.largeTitle.bold())
                        Text(mode == .signIn
                             ? "Sign in to use live requests, runs, groups, and chat."
                             : "No school email is required. Use any email address and choose a password.")
                            .foregroundStyle(.secondary)
                    }

                    Picker("Account action", selection: $mode) {
                        ForEach(Mode.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(spacing: 0) {
                        if mode == .createAccount {
                            TextField("Your name", text: $displayName)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .padding(16)
                            Divider().opacity(0.45)
                        }

                        TextField("Email address", text: $email)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .padding(16)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif

                        Divider().opacity(0.45)

                        SecureField("Password", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
                            .padding(16)

                        if mode == .createAccount {
                            Divider().opacity(0.45)
                            SecureField("Confirm password", text: $passwordConfirmation)
                                .textContentType(.newPassword)
                                .padding(16)
                        }
                    }
                    .grabGlass(radius: 18)

                    if mode == .createAccount {
                        Label("Use at least 6 characters.", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button { Task { await submit() } } label: {
                        if working {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            PrimaryButtonLabel(
                                title: mode == .signIn ? "Sign in" : "Create account",
                                icon: mode == .signIn ? "arrow.right" : "person.badge.plus"
                            )
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(working || !canSubmit)
                }
                .padding(GrabTheme.pageInset)
            }
            .background(GrabBackdrop())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
        .macSheetSize(minHeight: 620)
        .onChange(of: mode) { _, _ in
            password = ""
            passwordConfirmation = ""
            errorMessage = nil
        }
        .onChange(of: store.isLive) { _, live in if live { dismiss() } }
        .alert("Couldn’t continue", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .alert("Account created", isPresented: Binding(
            get: { confirmationMessage != nil },
            set: { if !$0 { confirmationMessage = nil } }
        )) {
            Button("Continue", role: .cancel) { confirmationMessage = nil }
        } message: {
            Text(confirmationMessage ?? "")
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSubmit: Bool {
        guard normalizedEmail.contains("@"), password.count >= 6 else { return false }
        if mode == .createAccount {
            return displayName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
                && password == passwordConfirmation
        }
        return true
    }

    private func submit() async {
        working = true
        defer { working = false }
        store.lastError = nil

        switch mode {
        case .signIn:
            if !(await store.signIn(email: normalizedEmail, password: password)) {
                showStoreError("Check your email and password, then try again.")
            }

        case .createAccount:
            guard password == passwordConfirmation else {
                errorMessage = "The passwords don’t match."
                return
            }
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            switch await store.createAccount(email: normalizedEmail, password: password, displayName: name) {
            case .signedIn:
                break
            case .confirmationRequired:
                mode = .signIn
                confirmationMessage = "Confirm your email using the message from Dart, then return here and sign in with your password."
            case nil:
                showStoreError("We couldn’t create your account. Please try again.")
            }
        }
    }

    private func showStoreError(_ fallback: String) {
        errorMessage = store.lastError ?? fallback
        store.lastError = nil
    }
}
