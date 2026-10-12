import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var store: GrabStore
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
                    appearanceCard
                    earningsCard
                    previewExplanation
                    if !store.isLive {
                        NavigationLink {
                            ComponentGalleryView()
                        } label: {
                            Label("Open component gallery", systemImage: "square.grid.2x2.fill")
                                .font(.headline).foregroundStyle(GrabTheme.blue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .grabGlass()
                        }
                        .buttonStyle(PressableStyle())
                        Button(role: .destructive) { confirmReset = true } label: {
                            Label("Reset demo", systemImage: "arrow.counterclockwise")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, GrabTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(GrabBackdrop())
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .sheet(isPresented: $choosingHome) {
                PlaceSearchView(title: "Where you live", selection: $homeID, filter: .destinations, allowsAnyStore: false)
            }
            .onChange(of: homeID) { _, id in
                guard let id, id != store.profile?.homePlaceID else { return }
                Task { _ = await store.setHome(id) }
            }
            .alert("Display name", isPresented: $editingName) {
                TextField("Name", text: $nameDraft)
                Button("Save") { Task { await store.updateDisplayName(nameDraft.trimmingCharacters(in: .whitespaces)) } }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) { Task { _ = await store.deleteAccount() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes your profile, requests, runs and group memberships. Deliveries you’re making go back to open. This can’t be undone.")
            }
            .confirmationDialog("Reset all demo preferences?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset demo", role: .destructive) { state.resetDemo() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This restores the original preview mode, activity segment, tab, and System appearance.")
            }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            Text(store.isLive ? (store.profile?.initials ?? "?") : "NV")
                .font(.title.bold()).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(GrabTheme.blue.gradient, in: Circle())
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
        .grabGlass()
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Appearance", subtitle: "Changes immediately and persists")
            Picker("Appearance", selection: $state.appearance) {
                ForEach(AppearanceChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
            }
            .pickerStyle(.segmented)
        }
        .padding(18)
        .grabGlass()
    }

    private var earningsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.isLive ? "Earnings" : "Sample earnings", systemImage: "sparkles").font(.headline)
                Spacer()
                if !store.isLive { PreviewPill(text: "SAMPLE") }
            }
            Text("$\(store.earnings.map { GrabStore.dollars($0.earnedCents) } ?? 46)")
                .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(GrabTheme.gold)
            Text(earningsCaption)
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(GrabTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: GrabTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: GrabTheme.cardRadius).stroke(GrabTheme.gold.opacity(0.2)))
    }

    private var earningsCaption: String {
        guard store.isLive, let earnings = store.earnings else {
            return "Illustrative local data only — not available funds or a payment balance."
        }
        return "\(earnings.completedCount) completed · \(earnings.activeCount) in progress. Rewards are tracked, not yet paid out — payments arrive in a later section."
    }

    private var aboutText: String {
        switch store.phase {
        case .live: "Connected to the Grab backend. Requests, runs, chat, shopping lists and notifications are live while the app is open. Card payments and push notifications with the app closed are not part of this build."
        case .signedOut: "Connected to the Grab backend. Sign in to replace the sample data with your campus’s live requests, runs, and groups."
        case .preview: "This is a development-only product preview. Sample tasks, people, messages, rewards, notifications, and earnings are not real. Add Supabase settings to connect a backend."
        }
    }

    @ViewBuilder private var accountCard: some View {
        if store.isLive {
            HStack(spacing: 12) {
                Button { nameDraft = store.profile?.displayName ?? ""; editingName = true } label: {
                    Label("Edit name", systemImage: "pencil").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) { Task { await store.signOut() } } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Text("Delete account").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        } else if store.isConfigured {
            Button { showSignIn = true } label: {
                PrimaryButtonLabel(title: "Sign in with campus email", icon: "person.crop.circle.badge.plus")
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

private struct ProfileRow: View {
    let icon: String
    let title: String
    let value: String
    var showsChevron = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(GrabTheme.blue).frame(width: 26)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
            if showsChevron { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
        }
        .padding(.vertical, 15)
    }
}
