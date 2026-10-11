import SwiftUI

struct GrabItemCard: View {
    let item: GrabItem
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(GrabTheme.blue)
                    .frame(width: 42, height: 42)
                    .background(GrabTheme.blue.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline).foregroundStyle(.primary)
                    Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(compact ? 1 : 2)
                }
                Spacer(minLength: 4)
                if let reward = item.reward {
                    Text("$\(reward)")
                        .font(.title3.bold())
                        .foregroundStyle(GrabTheme.gold)
                }
            }
            HStack(spacing: 8) {
                Text(item.kindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let effort = item.effort {
                    Label(effort, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.timing).font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens preview details")
    }

    private var symbol: String {
        switch item.kind {
        case .campusRequest: "shippingbox.fill"
        case .friendRun: "person.2.fill"
        case .buildingRun: "building.2.fill"
        }
    }
}

struct GroupCard: View {
    let group: GrabGroup

    var body: some View {
        HStack(spacing: 14) {
            AvatarStack(initials: group.memberInitials)
                .frame(width: 82, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(group.name).font(.headline)
                Text("\(group.memberCount) members · \(group.kind.rawValue)")
                    .font(.caption).foregroundStyle(GrabTheme.blue)
                Text(group.latestMessage).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GrabTheme.cardRadius, style: .continuous).stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
        .contentShape(Rectangle())
    }
}
