import SwiftUI

struct DartItemCard: View {
    let item: DartItem
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 13) {
                DartIconTile(symbol: symbol, size: compact ? 46 : 54, highlighted: item.status == .waiting)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(category.uppercased())
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(DartTheme.muted)
                        if item.status != .waiting { StatusDot(status: item.status) }
                    }
                    Text(item.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(DartTheme.text)
                        .lineLimit(compact ? 1 : 2)
                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(DartTheme.muted)
                        .lineLimit(compact ? 1 : 2)
                }
                Spacer(minLength: 4)
                if let reward = item.reward {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$\(reward)")
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(DartTheme.limeInk)
                        Text("reward")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DartTheme.muted)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(DartTheme.lime, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            HStack(spacing: 8) {
                Label(item.pickup, systemImage: "mappin.circle.fill")
                    .lineLimit(1)
                Image(systemName: "arrow.right").font(.caption2.bold())
                Text(item.destination).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(DartTheme.muted)

            HStack(spacing: 8) {
                Label(item.effort ?? item.timing, systemImage: "clock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DartTheme.text)
                Spacer()
                Text(item.status == .waiting ? "View details" : item.status.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DartTheme.limeInk)
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(DartTheme.limeInk)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(DartTheme.lime.opacity(0.82), in: Capsule())
        }
        .padding(18)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous).stroke(DartTheme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    private var symbol: String {
        switch item.kind {
        case .campusRequest: "shippingbox.fill"
        case .friendRun: "person.2.fill"
        case .buildingRun: "building.2.fill"
        case .campusRun: "storefront.fill"
        }
    }

    private var category: String {
        let value = "\(item.title) \(item.subtitle)".lowercased()
        if value.contains("coffee") || value.contains("food") || value.contains("dinner") { return "Food" }
        if value.contains("grocery") || value.contains("shampoo") || value.contains("target") { return "Groceries" }
        if value.contains("library") || value.contains("charger") || value.contains("pick up") { return "Pickup" }
        return item.kind == .campusRequest ? "Campus task" : "Store run"
    }
}

private struct StatusDot: View {
    let status: DartStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(DartTheme.lime).frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(DartTheme.muted)
    }
}

struct GroupCard: View {
    let group: DartGroup

    var body: some View {
        HStack(spacing: 14) {
            AvatarStack(initials: group.memberInitials)
                .frame(width: 82, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(group.name).font(.headline)
                Text("\(group.memberCount) members · \(group.kind.rawValue)")
                    .font(.caption).foregroundStyle(DartTheme.blue)
                Text(group.latestMessage).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DartTheme.cardRadius, style: .continuous).stroke(DartTheme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 7)
        .contentShape(Rectangle())
    }
}
