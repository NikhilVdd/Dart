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

/// Passwordless sign-in: email → one-time code (6 digits per supabase/config.toml).
struct SignInView: View {
    @EnvironmentObject private var store: GrabStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var working = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: codeSent ? "envelope.open.fill" : "graduationcap.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 66, height: 66)
                        .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 21))
                    Text(codeSent ? "Check your email" : "Sign in to Grab").font(.largeTitle.bold())
                    Text(codeSent
                         ? "Enter the code we sent to \(email)."
                         : "Use your campus email so we can connect you with your campus and building.")
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        if codeSent {
                            TextField("Code", text: $code)
                                .textContentType(.oneTimeCode)
                                .font(.title2.monospacedDigit())
                                .padding(16)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        } else {
                            TextField("you@berkeley.edu", text: $email)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .padding(16)
                                #if os(iOS)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                #endif
                        }
                    }
                    .grabGlass(radius: 18)

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

                    if codeSent {
                        Button("Use a different email") { codeSent = false; code = "" }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(GrabTheme.pageInset)
            }
            .background(GrabBackdrop())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
        .onChange(of: store.isLive) { _, live in if live { dismiss() } }
    }

    private var canSubmit: Bool {
        codeSent ? (6...8).contains(code.filter(\.isNumber).count) : email.contains("@")
    }

    private func submit() async {
        working = true
        defer { working = false }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        if codeSent {
            _ = await store.verify(email: address, code: code.filter(\.isNumber))
        } else if await store.sendCode(to: address) {
            email = address
            codeSent = true
        }
    }
}
