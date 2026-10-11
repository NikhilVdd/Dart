import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: GrabItem
    @State private var showUpcoming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        PreviewPill(text: item.kindLabel.uppercased())
                        Text(item.title)
                            .font(.largeTitle.bold())
                            .minimumScaleFactor(0.82)
                        Text(item.detail).font(.body).foregroundStyle(.secondary)
                        StatusChip(status: item.status)
                    }

                    VStack(spacing: 0) {
                        DetailRow(icon: "person.fill", label: item.kind == .campusRequest ? "Requester" : "Shopper", value: item.person.name)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "mappin.and.ellipse", label: "Pickup", value: item.pickup)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "location.fill", label: "Destination", value: item.destination)
                        Divider().padding(.leading, 50)
                        DetailRow(icon: "clock.fill", label: item.kind == .friendRun ? "Cutoff" : "Timing", value: item.timing)
                    }
                    .padding(.horizontal, 16)
                    .grabGlass()

                    if item.reward != nil || item.merchandiseBudget != nil {
                        HStack(spacing: 12) {
                            if let reward = item.reward {
                                MoneyCard(label: "Helper reward", amount: reward, emphasized: true)
                            }
                            if let budget = item.merchandiseBudget {
                                MoneyCard(label: "Item budget", amount: budget, emphasized: false)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview only").font(.headline)
                        Text("Accepting, purchasing, list editing, and delivery completion arrive in a later development section. No payment or delivery is happening here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(GrabTheme.paleBlue.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Button { showUpcoming = true } label: {
                        PrimaryButtonLabel(title: futureActionTitle, icon: "arrow.right.circle.fill")
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(GrabTheme.pageInset)
            }
            .background(GrabBackdrop())
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .alert("Coming in a later section", isPresented: $showUpcoming) {
                Button("Got it", role: .cancel) { }
            } message: {
                Text("This action is shown to preview the product flow. It does not accept a task, spend money, or change a delivery.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var futureActionTitle: String {
        switch item.kind {
        case .campusRequest: "Preview accept flow"
        case .friendRun: "Preview add item flow"
        case .buildingRun: "Preview building request"
        }
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).foregroundStyle(GrabTheme.blue).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.medium))
            }
            Spacer()
        }
        .padding(.vertical, 14)
    }
}

private struct MoneyCard: View {
    let label: String
    let amount: Int
    let emphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("$\(amount)").font(.title.bold()).foregroundStyle(emphasized ? GrabTheme.gold : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.06)))
    }
}
