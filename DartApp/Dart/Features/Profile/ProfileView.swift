import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: DartStore
    @State private var confirmReset = false
    @State private var showSignIn = false
    @State private var editingName = false
    @State private var confirmDelete = false
    @State private var nameDraft = ""
    @State private var choosingHome = false
    @State private var homeID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !store.isLive { PreviewPill() }
                    profileHeader
                    accountCard
                    infoCard
                    blockedAccountsCard
                    appearanceCard
                    earningsCard
                    previewExplanation
                    if !store.isLive {
                        NavigationLink {
                            ComponentGalleryView()
                        } label: {
                            Label("Open component gallery", systemImage: "square.grid.2x2.fill")
                                .font(.headline).foregroundStyle(DartTheme.blue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .dartSurface()
                        }
                        .buttonStyle(PressableStyle())
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Reset demo", systemImage: "arrow.counterclockwise")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                                .foregroundStyle(DartTheme.danger)
                                .background(DartTheme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                                .overlay(RoundedRectangle(cornerRadius: DartTheme.controlRadius).stroke(DartTheme.danger.opacity(0.35)))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .dartModal(isPresented: $showSignIn) { SignInView() }
            .dartModal(isPresented: $choosingHome) {
                PlaceSearchView(title: "Where you live", selection: $homeID, filter: .destinations, allowsAnyStore: false)
            }
            .onChange(of: homeID) { _, id in
                guard let id, id != store.profile?.homePlaceID else { return }
                Task { _ = await store.setHome(id) }
            }
            .dartDialog(isPresented: $editingName) {
                DartTextPromptCard(symbol: "person.fill", title: "Display name", message: "This is how other students see you.",
                                   placeholder: "Your name", text: $nameDraft, actionTitle: "Save") {
                    let value = nameDraft.trimmingCharacters(in: .whitespaces)
                    guard !value.isEmpty else { return }
                    editingName = false
                    Task { await store.updateDisplayName(value) }
                } onCancel: {
                    editingName = false
                }
            }
            .dartDialog(isPresented: $confirmDelete) {
                DartAlertCard(symbol: "trash.fill", title: "Delete your account?",
                              message: "This permanently deletes your profile, requests, runs, and group memberships. Deliveries you’re making return to open. This cannot be undone.",
                              primaryTitle: "Delete account", primaryIsDestructive: true,
                              primaryAction: {
                                  confirmDelete = false
                                  Task { _ = await store.deleteAccount() }
                              }, secondaryTitle: "Keep my account", secondaryAction: { confirmDelete = false })
            }
            .dartDialog(isPresented: $confirmReset) {
                DartAlertCard(symbol: "arrow.counterclockwise", title: "Reset preview?",
                              message: "This restores the original preview mode, activity segment, tab, and System appearance.",
                              primaryTitle: "Reset preview", primaryIsDestructive: true,
                              primaryAction: {
                                  confirmReset = false
                                  state.resetDemo()
                              }, secondaryTitle: "Cancel", secondaryAction: { confirmReset = false })
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Text(store.isLive ? (store.profile?.initials ?? "?") : "NV")
                .font(.title.bold()).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(DartTheme.blue.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(store.profile?.displayName ?? state.profileName).font(.largeTitle.bold())
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text(store.isLive ? "Signed in" : "Preview profile").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            ProfileRow(icon: "graduationcap.fill", title: "Campus", value: store.isLive ? (store.campusName ?? "Not linked") : state.campus)
            Divider().padding(.leading, 48)
            if store.isLive {
                Button { homeID = store.profile?.homePlaceID; choosingHome = true } label: {
                    ProfileRow(icon: "building.2.fill", title: "Home", value: store.buildingName ?? "Choose where you live", showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ProfileRow(icon: "building.2.fill", title: "Building", value: state.building)
            }
        }
        .padding(.horizontal, 16)
        .dartSurface()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Appearance", subtitle: "Changes immediately and persists")
            SlidingSegmentedControl(selection: $state.appearance)
        }
        .padding(18)
        .dartSurface()
    }

    @ViewBuilder private var blockedAccountsCard: some View {
        if store.isLive {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Blocked accounts", subtitle: "Blocked students cannot discover or accept your requests")
                if store.blockedUsers.isEmpty {
                    Text("No blocked accounts").font(.subheadline).foregroundStyle(DartTheme.muted)
                } else {
                    ForEach(store.blockedUsers) { row in
                        HStack {
                            Text(row.blocked?.displayName ?? "Blocked account")
                            Spacer()
                            Button { Task { _ = await store.unblockUser(row.blockedID) } } label: {
                                Text("Unblock").font(.caption.weight(.bold))
                                    .foregroundStyle(DartTheme.limeInk)
                                    .padding(.horizontal, 14).frame(minHeight: 38)
                                    .background(DartTheme.lime, in: Capsule())
                            }
                            .buttonStyle(PressableStyle())
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .padding(18)
            .dartSurface()
        }
    }

    private var earningsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.isLive ? "Earnings" : "Sample earnings", systemImage: "sparkles").font(.headline)
                Spacer()
                if !store.isLive { PreviewPill(text: "SAMPLE") }
            }
            Text("$\(store.earnings.map { DartStore.dollars($0.earnedCents) } ?? 46)")
                .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(DartTheme.gold)
            Text(earningsCaption)
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(DartTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: DartTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.cardRadius).stroke(DartTheme.gold.opacity(0.2)))
    }

    private var earningsCaption: String {
        guard store.isLive, let earnings = store.earnings else {
            return "Illustrative local data only — not available funds or a payment balance."
        }
        return "\(earnings.completedCount) completed · \(earnings.activeCount) in progress. Rewards are tracked, not yet paid out — payments arrive in a later section."
    }

    private var aboutText: String {
        switch store.phase {
        case .launching: "Connecting securely to Dart."
        case .live: "Connected to the Dart backend. Requests, runs, chat, shopping lists, push notifications, and Live Activity status tracking are enabled. Card payments are not part of this build."
        case .signedOut: "Connected to the Dart backend. Sign in or create an account with any email address to load live requests, runs, groups, and chat."
        case .preview: "This is a development-only product preview. Sample tasks, people, messages, rewards, notifications, and earnings are not real. Add Supabase settings to connect a backend."
        case .unconfigured: "This release is missing its backend environment configuration."
        }
    }

    @ViewBuilder private var accountCard: some View {
        if store.isLive {
            HStack(spacing: 12) {
                Button { nameDraft = store.profile?.displayName ?? ""; editingName = true } label: {
                    Label("Edit name", systemImage: "pencil").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(DartTheme.text)
                        .background(DartTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DartTheme.controlRadius).stroke(DartTheme.line))
                }
                .buttonStyle(PressableStyle())
                Button(role: .destructive) { Task { await store.signOut() } } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(DartTheme.danger)
                        .background(DartTheme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: DartTheme.controlRadius))
                        .overlay(RoundedRectangle(cornerRadius: DartTheme.controlRadius).stroke(DartTheme.danger.opacity(0.30)))
                }
                .buttonStyle(PressableStyle())
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete account").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        } else if store.isConfigured {
            Button { showSignIn = true } label: {
                PrimaryButtonLabel(title: "Sign in or create account", icon: "person.crop.circle.badge.plus")
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var previewExplanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("About this build").font(.headline)
            Text(aboutText)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct DartTextPromptCard: View {
    let symbol: String
    let title: String
    let message: String
    let placeholder: String
    @Binding var text: String
    let actionTitle: String
    let onAction: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DartIconTile(symbol: symbol, size: 56, highlighted: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.heavy)).foregroundStyle(DartTheme.text)
                Text(message).font(.subheadline).foregroundStyle(DartTheme.muted)
            }
            DartField(label: title) { TextField(placeholder, text: $text).textFieldStyle(.plain) }
            Button(action: onAction) { PrimaryButtonLabel(title: actionTitle, icon: "checkmark") }
                .buttonStyle(PressableStyle())
            Button("Cancel", action: onCancel)
                .font(.headline).foregroundStyle(DartTheme.muted)
                .frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .padding(22)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(DartTheme.line))
        .shadow(color: .black.opacity(0.20), radius: 28, y: 14)
    }
}

private struct ProfileRow: View {
    let icon: String
    let title: String
    let value: String
    var showsChevron = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(DartTheme.blue).frame(width: 26)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 15)
    }
}
