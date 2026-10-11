import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PreviewPill()
                    profileHeader
                    infoCard
                    appearanceCard
                    earningsCard
                    previewExplanation
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
                .padding(.horizontal, GrabTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(GrabBackdrop())
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
            Text("NV")
                .font(.title.bold()).foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(GrabTheme.blue.gradient, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(state.profileName).font(.largeTitle.bold())
                Text("Preview profile").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var infoCard: some View {
        VStack(spacing: 0) {
            ProfileRow(icon: "graduationcap.fill", title: "Campus", value: state.campus)
            Divider().padding(.leading, 48)
            ProfileRow(icon: "building.2.fill", title: "Building", value: state.building)
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
                Label("Sample earnings", systemImage: "sparkles").font(.headline)
                Spacer()
                PreviewPill(text: "SAMPLE")
            }
            Text("$46").font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(GrabTheme.gold)
            Text("Illustrative local data only — not available funds or a payment balance.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(GrabTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: GrabTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: GrabTheme.cardRadius).stroke(GrabTheme.gold.opacity(0.2)))
    }

    private var previewExplanation: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("About this build").font(.headline)
            Text("This is Section 1: a development-only product preview. Sample tasks, people, messages, rewards, notifications, and earnings are not real. Accounts, transactions, and background location are intentionally unavailable.")
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
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundStyle(GrabTheme.blue).frame(width: 26)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .padding(.vertical, 15)
    }
}
