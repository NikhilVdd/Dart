import SwiftUI

struct CreateMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var destination: CreateDestination?

    enum CreateDestination: String, Identifiable {
        case request
        case run
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                PreviewPill()
                Text("What would you like to create?").font(.largeTitle.bold())
                Text("Choose a flow to preview. Full forms arrive in Section 2 and later.")
                    .foregroundStyle(.secondary)

                CreateOption(icon: "shippingbox.fill", title: "Request something", subtitle: "Ask someone nearby to bring an item or complete an errand") {
                    destination = .request
                }
                CreateOption(icon: "storefront.fill", title: "Announce a store run", subtitle: "Let friends or approved neighbors know you’re already going") {
                    destination = .run
                }
                Spacer()
            }
            .padding(GrabTheme.pageInset)
            .background(GrabBackdrop())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } }
            }
            .navigationDestination(item: $destination) { destination in
                CreateIntroView(destination: destination)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct CreateOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(18)
            .grabGlass()
        }
        .buttonStyle(PressableStyle())
    }
}

private struct CreateIntroView: View {
    let destination: CreateMenuView.CreateDestination
    @State private var showUpcoming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: destination == .request ? "shippingbox.fill" : "storefront.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(GrabTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 23))
                Text(destination == .request ? "Request something nearby" : "Share a store run")
                    .font(.largeTitle.bold())
                Text(description).font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 18) {
                    IntroStep(number: "1", text: stepOne)
                    IntroStep(number: "2", text: stepTwo)
                    IntroStep(number: "3", text: stepThree)
                }
                .padding(20)
                .grabGlass()
                Button { showUpcoming = true } label: {
                    PrimaryButtonLabel(title: "Continue preview", icon: "arrow.right")
                }
                .buttonStyle(PressableStyle())
                Text("Section 1 stops here intentionally. No request or broadcast will be created.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(GrabTheme.pageInset)
        }
        .background(GrabBackdrop())
        .navigationTitle("How it works")
        .alert("Form arrives next", isPresented: $showUpcoming) {
            Button("Done", role: .cancel) { }
        } message: {
            Text(destination == .request ? "Campus request creation is planned for Section 2." : "Friend and building run creation is planned for Sections 3 and 4.")
        }
    }

    private var description: String { destination == .request ? "Describe the errand, set a clear destination and deadline, then offer a reward." : "Choose who can see the run, set a request cutoff, and stay in control of any building broadcast." }
    private var stepOne: String { destination == .request ? "Describe exactly what you need." : "Choose the store and audience." }
    private var stepTwo: String { destination == .request ? "Set destination, timing, and budget." : "Set a clear request cutoff." }
    private var stepThree: String { destination == .request ? "Review before posting nearby." : "Approve before sharing with a building." }
}

private struct IntroStep: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Text(number).font(.subheadline.bold()).foregroundStyle(.white).frame(width: 30, height: 30).background(GrabTheme.blue, in: Circle())
            Text(text).font(.body.weight(.medium))
        }
    }
}
