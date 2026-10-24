import SwiftUI

/// Shown on Home when Supabase is configured but nobody is signed in.
struct SignInBanner: View {
    @State private var showSignIn = false

    var body: some View {
        Button { showSignIn = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .foregroundStyle(DartTheme.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in or create an account").font(.headline).foregroundStyle(.primary)
                    Text("Use any email and password to connect to live Dart data.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(18)
            .dartSurface()
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

    @EnvironmentObject private var store: DartStore
    @Environment(\.dismiss) private var dismiss
    let allowsDismiss: Bool
    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var working = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?
    @State private var showPasswordReset = false

    init(allowsDismiss: Bool = true) {
        self.allowsDismiss = allowsDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: mode == .signIn ? "person.crop.circle.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(DartTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 21))

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
                    .dartSurface(radius: 18)

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
                                .background(DartTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 18))
                        } else {
                            PrimaryButtonLabel(
                                title: mode == .signIn ? "Sign in" : "Create account",
                                icon: mode == .signIn ? "arrow.right" : "person.badge.plus"
                            )
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(working || !canSubmit)

                    if mode == .signIn {
                        Button("Forgot password?") { showPasswordReset = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DartTheme.limeSoft)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                }
                .padding(DartTheme.pageInset)
            }
            .background(DartBackdrop())
            .toolbar {
                if allowsDismiss {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showPasswordReset) { PasswordResetRequestView() }
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

private struct PasswordResetRequestView: View {
    @EnvironmentObject private var store: DartStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $email)
                        .textContentType(.emailAddress)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                } header: {
                    Text("Reset your password")
                } footer: {
                    Text("Dart will email a secure recovery link if an account exists for this address.")
                }

                Button {
                    Task { await send() }
                } label: {
                    if isWorking { ProgressView() } else { Text("Send recovery email") }
                }
                .disabled(isWorking || !email.contains("@"))
            }
            .scrollContentBackground(.hidden)
            .background(DartBackdrop())
            .navigationTitle("Password reset")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Check your email", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("Done") { dismiss() }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func send() async {
        isWorking = true
        store.lastError = nil
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sent = await store.requestPasswordReset(email: normalized)
        isWorking = false
        if sent {
            message = "Open the link in the email on this iPhone to choose a new password."
        }
    }
}

struct PasswordUpdateView: View {
    @EnvironmentObject private var store: DartStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Choose a new password").font(.largeTitle.bold())
                Text("Use at least 8 characters. Your new password takes effect on every Dart device.")
                    .foregroundStyle(DartTheme.muted)
                SecureField("New password", text: $password).textContentType(.newPassword)
                    .padding(16).dartSurface(radius: 16)
                SecureField("Confirm new password", text: $confirmation).textContentType(.newPassword)
                    .padding(16).dartSurface(radius: 16)
                Button {
                    Task { await save() }
                } label: {
                    if isWorking {
                        ProgressView().tint(DartTheme.background).frame(maxWidth: .infinity).frame(height: 56)
                            .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: 17))
                    } else {
                        PrimaryButtonLabel(title: "Save new password", icon: "lock.rotation")
                    }
                }
                .disabled(isWorking || password.count < 8 || password != confirmation)
                Spacer()
            }
            .padding(DartTheme.pageInset)
            .background(DartBackdrop())
            .interactiveDismissDisabled()
            .alert("Couldn’t update password", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func save() async {
        guard password == confirmation else {
            errorMessage = "The passwords don’t match."
            return
        }
        isWorking = true
        store.lastError = nil
        if !(await store.updatePassword(password)) {
            errorMessage = store.lastError ?? "Please try again."
            store.lastError = nil
        }
        isWorking = false
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: DartStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var name = ""
    @State private var selectedAgeBand: String?
    @State private var selectedHomeID: UUID?
    @State private var choosingHome = false
    @State private var isWorking = false

    private let stepCount = 5

    var body: some View {
        NavigationStack {
            ZStack {
                DartBackdrop()
                VStack(alignment: .leading, spacing: 24) {
                    ProgressView(value: Double(step + 1), total: Double(stepCount))
                        .tint(DartTheme.lime)
                    Text("SET UP DART").font(.caption.bold()).tracking(1.6).foregroundStyle(DartTheme.lime)
                    Group {
                        switch step {
                        case 0: identityStep
                        case 1: ageStep
                        case 2: homeStep
                        case 3: notificationStep
                        default: safetyStep
                        }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    Spacer()
                    if step < stepCount - 1 {
                        Button { Task { await advance() } } label: {
                            PrimaryButtonLabel(title: "Continue", icon: "arrow.right")
                        }
                        .disabled(isWorking || !canAdvance)
                    } else {
                        Button { Task { await finish() } } label: {
                            if isWorking {
                                ProgressView().tint(DartTheme.background).frame(maxWidth: .infinity).frame(height: 56)
                                    .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: 17))
                            } else {
                                PrimaryButtonLabel(title: "Agree and enter Dart", icon: "checkmark.shield.fill")
                            }
                        }
                        .disabled(isWorking)
                    }
                }
                .padding(DartTheme.pageInset)
            }
            .interactiveDismissDisabled()
            .sheet(isPresented: $choosingHome) {
                PlaceSearchView(title: "Where you live", selection: $selectedHomeID, filter: .destinations, allowsAnyStore: false)
            }
            .onAppear {
                name = store.profile?.displayName ?? ""
                selectedAgeBand = store.profile?.ageBand == "not_set" ? nil : store.profile?.ageBand
                selectedHomeID = store.profile?.homePlaceID
            }
            .onChange(of: selectedHomeID) { _, id in
                guard let id, id != store.profile?.homePlaceID else { return }
                Task {
                    isWorking = true
                    _ = await store.setHome(id)
                    isWorking = false
                }
            }
        }
    }

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Dart").font(.largeTitle.bold())
            Text("Built for useful handoffs between students—not anonymous delivery.")
                .foregroundStyle(DartTheme.muted)
            TextField("Display name", text: $name)
                .textContentType(.name).padding(16).dartSurface(radius: 16)
            Label(store.campusName ?? "UC Berkeley", systemImage: "graduationcap.fill")
                .foregroundStyle(DartTheme.lime).padding(16).dartSurface(radius: 16)
            Text("Your account is campus-scoped, but Dart does not claim your identity is institution-verified.")
                .font(.footnote).foregroundStyle(DartTheme.muted)
        }
    }

    private var ageStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your age band").font(.largeTitle.bold())
            Text("We do not store your birth date. This controls money-related eligibility on the server.")
                .foregroundStyle(DartTheme.muted)
            ageChoice("Under 18", value: "under_18", detail: "Free requests and runs remain available; paid features stay disabled.")
            ageChoice("18 or older", value: "18_or_over", detail: "Paid features remain off until Dart enables them and eligibility checks pass.")
        }
    }

    private var homeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where do you live?").font(.largeTitle.bold())
            Text("Your home building helps Dart suggest safer, lower-detour handoffs. Other users never receive your precise live location.")
                .foregroundStyle(DartTheme.muted)
            Button { choosingHome = true } label: {
                HStack {
                    Image(systemName: "building.2.fill").foregroundStyle(DartTheme.lime)
                    Text(store.buildingName ?? "Choose a residence").foregroundStyle(DartTheme.text)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(DartTheme.muted)
                }
                .padding(18).dartSurface()
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stay in sync").font(.largeTitle.bold())
            Text("Notifications and Live Activities can show request status without exposing another student’s exact location.")
                .foregroundStyle(DartTheme.muted)
            Label("Accepted, pickup, on-the-way, and delivered updates", systemImage: "bell.badge.fill")
                .padding(18).dartSurface()
            Button("Allow notifications") { store.requestNotificationPermission() }
                .buttonStyle(.borderedProminent).tint(DartTheme.lime).foregroundStyle(DartTheme.background)
                .frame(minHeight: 44)
            Text("You can also continue and enable them later in Settings.")
                .font(.footnote).foregroundStyle(DartTheme.muted)
        }
    }

    private var safetyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keep handoffs safe").font(.largeTitle.bold())
            safetyRule("Meet in a staffed or public place whenever possible.", icon: "person.2.fill")
            safetyRule("Never request prohibited, age-restricted, or dangerous items.", icon: "hand.raised.fill")
            safetyRule("Use report and block tools if a student makes you uncomfortable.", icon: "exclamationmark.bubble.fill")
            safetyRule("Call local emergency services for immediate danger; Dart is not an emergency service.", icon: "phone.fill")
            Text("Continuing records acceptance of these in-app rules. Formal Terms, Privacy, and minor-safety policies still require counsel approval before public launch.")
                .font(.footnote).foregroundStyle(DartTheme.muted)
        }
    }

    private func ageChoice(_ title: String, value: String, detail: String) -> some View {
        Button { selectedAgeBand = value } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: selectedAgeBand == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(DartTheme.lime)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(DartTheme.text)
                    Text(detail).font(.footnote).foregroundStyle(DartTheme.muted).multilineTextAlignment(.leading)
                }
            }
            .padding(18).dartSurface()
        }
        .buttonStyle(PressableStyle())
    }

    private func safetyRule(_ text: String, icon: String) -> some View {
        Label {
            Text(text).foregroundStyle(DartTheme.text)
        } icon: {
            Image(systemName: icon).foregroundStyle(DartTheme.lime)
        }
        .font(.subheadline)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case 1: selectedAgeBand != nil
        case 2: store.profile?.homePlaceID != nil
        default: true
        }
    }

    private func advance() async {
        isWorking = true
        if step == 0 {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != store.profile?.displayName { await store.updateDisplayName(trimmed) }
        } else if step == 1, store.profile?.ageBand == "not_set", let selectedAgeBand {
            _ = await store.setAgeBand(selectedAgeBand)
        }
        isWorking = false
        guard store.lastError == nil else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step += 1 }
    }

    private func finish() async {
        isWorking = true
        _ = await store.acceptSafetyRules()
        isWorking = false
    }
}
