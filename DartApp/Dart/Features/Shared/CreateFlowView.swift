import SwiftUI

/// Requests are created from Request mode and store runs from Earn mode, each straight into its form.
struct CreateSheet: View {
    enum Destination: String, Identifiable {
        case request
        case run
        var id: String { rawValue }
    }

    let destination: Destination
    @Environment(\.dartDismiss) private var dismiss
    @EnvironmentObject private var store: DartStore

    var body: some View {
        NavigationStack {
            Group {
                if store.isLive {
                    switch destination {
                    case .request: RequestFormView { dismiss() }
                    case .run: RunFormView { dismiss() }
                    }
                } else {
                    CreateIntroView(destination: destination)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .macSheetSize()
    }
}

private struct CreateIntroView: View {
    let destination: CreateSheet.Destination
    @State private var showUpcoming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: destination == .request ? "shippingbox.fill" : "storefront.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(DartTheme.blue.gradient, in: RoundedRectangle(cornerRadius: 23))
                Text(destination == .request ? "Request something nearby" : "Share a store run")
                    .font(.largeTitle.bold())
                Text(description).font(.title3).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 18) {
                    IntroStep(number: "1", text: stepOne)
                    IntroStep(number: "2", text: stepTwo)
                    IntroStep(number: "3", text: stepThree)
                }
                .padding(20)
                .dartSurface()
                Button { showUpcoming = true } label: {
                    PrimaryButtonLabel(title: "Continue preview", icon: "arrow.right")
                }
                .buttonStyle(PressableStyle())
                Text("Preview mode: no request or broadcast will be created. Sign in from Profile to post.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(DartTheme.pageInset)
        }
        .background(DartBackdrop())
        .navigationTitle("How it works")
        .dartDialog(isPresented: $showUpcoming) {
            DartAlertCard(symbol: "person.crop.circle.badge.plus", title: "Sign in to post",
                          message: "Posting requests and runs needs a signed-in account on a build connected to the Dart backend.",
                          primaryTitle: "Done") {
                showUpcoming = false
            }
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
            Text(number).font(.subheadline.bold()).foregroundStyle(.white).frame(width: 30, height: 30).background(DartTheme.blue, in: Circle())
            Text(text).font(.body.weight(.medium))
        }
    }
}
