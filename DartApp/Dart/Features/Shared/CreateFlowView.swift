import SwiftUI

/// Opens straight into the request form (optionally with a pickup spot already chosen) or the run form.
struct CreateSheet: View {
    enum Destination: Identifiable, Hashable {
        case request(PickupSpot?)
        case run

        var id: String {
            switch self {
            case .request(let spot): "request-\(spot?.rawValue ?? "none")"
            case .run: "run"
            }
        }

        var isRequest: Bool { if case .request = self { true } else { false } }
    }

    let destination: Destination
    @Environment(\.dartDismiss) private var dismiss
    @EnvironmentObject private var store: DartStore
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationStack {
            Group {
                if store.isLive || state.screenshotScenario == "checkout" {
                    switch destination {
                    case .request(let spot): RequestFormView(initialSpot: spot) { dismiss() }
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
                Image(systemName: destination.isRequest ? "bag.fill" : "figure.walk")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DartTheme.limeInk)
                    .frame(width: 72, height: 72)
                    .background(DartTheme.lime.gradient, in: RoundedRectangle(cornerRadius: 23))
                Text(destination.isRequest ? "Get your Grubhub order delivered" : "Heading to an eatery?")
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
                Text("Preview mode: no request or broadcast will be created. Sign in from Account to post.")
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

    private var description: String { destination.isRequest ? "Order on Grubhub like usual. A student already nearby picks it up and brings it to you." : "Carry a few orders back from the eatery you’re already going to, and earn on the way." }
    private var stepOne: String { destination.isRequest ? "Pick the eatery your order is at." : "Choose the eatery you’re heading to." }
    private var stepTwo: String { destination.isRequest ? "Confirm where to bring it." : "Say where you’re heading back to." }
    private var stepThree: String { destination.isRequest ? "A darter grabs it and brings it over." : "Accept the orders that fit your trip." }
}

private struct IntroStep: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Text(number).font(.subheadline.bold()).foregroundStyle(DartTheme.limeInk).frame(width: 30, height: 30).background(DartTheme.lime, in: Circle())
            Text(text).font(.body.weight(.medium))
        }
    }
}
