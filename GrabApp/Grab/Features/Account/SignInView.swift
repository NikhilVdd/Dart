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
                    Text("Sign in with your campus email").font(.headline).foregroundStyle(.primary)
                    Text("You’re viewing sample data until you sign in.").font(.subheadline).foregroundStyle(.secondary)
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

/// Passwordless sign-in and sign-up in one flow: campus email → 6-digit code.
/// A first-time code creates the account; RootShellView then asks for a name (RegistrationView).
struct SignInView: View {
    @EnvironmentObject private var store: GrabStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false
    @State private var errorMessage: String?
    @State private var resendAvailableAt = Date.distantPast
    @FocusState private var fieldFocused: Bool

    /// Matches `otp_length` in supabase/config.toml; a few extra digits are tolerated.
    private static let codeLengths = 6...8
    /// Matches Supabase Auth's `max_frequency` between emails to the same address.
    private static let resendInterval: TimeInterval = 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: codeSent ? "envelope.open.fill" : "graduationcap.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 21))
                        .accessibilityHidden(true)
                    Text(codeSent ? "Check your email" : "Sign in to Grab").font(.largeTitle.bold())
                    Text(codeSent
                         ? "Enter the 6-digit code we sent to \(email). It can take a minute to arrive, so check your spam folder too."
                         : "Use your campus email. New here? The same code creates your account.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        if codeSent {
                            TextField("123456", text: $code)
                                .textContentType(.oneTimeCode)
                                .font(.title2.monospacedDigit())
                                .padding(16)
                                .focused($fieldFocused)
                                .onSubmit { Task { await submit() } }
                                .onChange(of: code) { _, value in
                                    let digits = String(value.filter(\.isNumber).prefix(Self.codeLengths.upperBound))
                                    if digits != value { code = digits }
                                    if errorMessage != nil { errorMessage = nil }
                                }
                                .accessibilityLabel("Sign-in code")
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        } else {
                            TextField("you@berkeley.edu", text: $email)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .padding(16)
                                .focused($fieldFocused)
                                .submitLabel(.continue)
                                .onSubmit { Task { await submit() } }
                                .onChange(of: email) { _, _ in if errorMessage != nil { errorMessage = nil } }
                                .accessibilityLabel("Campus email")
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                    .grabGlass(radius: 18)

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
                            PrimaryButtonLabel(title: codeSent ? "Verify code" : "Email me a code", icon: "arrow.right")
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(working || !canSubmit)
                    .opacity(canSubmit || working ? 1 : 0.55)

                    if codeSent {
                        resendButton
                        Button("Use a different email") {
                            codeSent = false
                            code = ""
                            errorMessage = nil
                            fieldFocused = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(working)
                    } else {
                        // For a code already in hand: an earlier email, or one minted with supabase/dev/accounts.mjs.
                        Button("I already have a code") {
                            email = EmailAddress.normalized(email)
                            errorMessage = nil
                            codeSent = true
                            fieldFocused = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(working || !EmailAddress.isValid(EmailAddress.normalized(email)))
                    }
                }
                .padding(GrabTheme.pageInset)
            }
            .background(GrabBackdrop())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { fieldFocused = true }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(working)
        .macSheetSize(minHeight: 560)
        .onChange(of: store.isLive) { _, live in if live { dismiss() } }
    }

    private var resendButton: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let wait = Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up))
            Button(wait > 0 ? "Resend code in \(wait)s" : "Resend code") {
                Task { await resend() }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .disabled(working || wait > 0)
        }
    }

    private var canSubmit: Bool {
        codeSent
            ? Self.codeLengths.contains(code.count)
            : EmailAddress.isValid(EmailAddress.normalized(email))
    }

    private func submit() async {
        guard canSubmit, !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        if codeSent {
            if let error = await store.verify(email: email, code: code) {
                errorMessage = error
                code = ""
            }
            // On success the session arrives through the auth listener and `isLive` dismisses this sheet.
        } else {
            let address = EmailAddress.normalized(email)
            email = address
            if let error = await store.sendCode(to: address) {
                errorMessage = error
            } else {
                code = ""
                codeSent = true
                resendAvailableAt = Date().addingTimeInterval(Self.resendInterval)
                fieldFocused = true
            }
        }
    }

    private func resend() async {
        guard !working else { return }
        working = true
        defer { working = false }
        errorMessage = nil
        if let error = await store.sendCode(to: email) {
            errorMessage = error
        } else {
            code = ""
            resendAvailableAt = Date().addingTimeInterval(Self.resendInterval)
        }
    }
}
