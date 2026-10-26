import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct DartItemCard: View {
    let item: DartItem
    var compact = false

    var body: some View {
        HStack(spacing: 14) {
            if let spot = item.pickupSpot {
                SpotBadge(spot: spot, size: 48)
            } else {
                DartIconTile(symbol: symbol, size: 48, highlighted: item.status == .waiting)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(DartTheme.text)
                    .lineLimit(1)
                Text("To \(item.destination)")
                    .font(.subheadline)
                    .foregroundStyle(DartTheme.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if item.status != .waiting { StatusDot(status: item.status) }
                    Text(item.effort ?? item.timing)
                        .font(.caption)
                        .foregroundStyle(DartTheme.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let reward = item.reward {
                Text("$\(reward)")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(DartTheme.limeInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DartTheme.lime, in: Capsule())
            }
        }
        .padding(14)
        .background(DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DartTheme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }

    /// Orders lead with the eatery; runs keep their sentence ("Maya is at Golden Bear Cafe").
    private var headline: String {
        item.kind == .campusRequest ? (item.pickupSpot?.name ?? item.title) : item.title
    }

    private var symbol: String {
        if let spot = item.pickupSpot { return spot.symbol }
        return switch item.kind {
        case .campusRequest: "shippingbox.fill"
        case .friendRun: "person.2.fill"
        case .buildingRun: "building.2.fill"
        case .campusRun: "storefront.fill"
        }
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

/// Loads an image from the asset catalog, or from the app bundle's resources in the macOS harness.
func dartBundleImage(_ name: String) -> Image? {
    #if os(iOS)
    UIImage(named: name).map { Image(uiImage: $0) }
    #elseif os(macOS)
    NSImage(named: name).map { Image(nsImage: $0) }
    #else
    nil
    #endif
}

private extension PickupSpot {
    /// The plate behind the logo: Golden Bear's logo is a gold square, Gateway has no logo yet
    /// and is shown as a wordmark on Berkeley blue like its menu screens.
    var plateColor: Color {
        switch self {
        case .goldenBearCafe: Color(red: 0.996, green: 0.706, blue: 0.082)   // #FEB415
        case .gatewayCafe: Color(red: 0.0, green: 0.196, blue: 0.384)        // #003262
        default: .white
        }
    }
}

/// The eatery's own logo on a full-width plate.
struct SpotLogo: View {
    let spot: PickupSpot
    var height: CGFloat = 60

    var body: some View {
        ZStack {
            spot.plateColor
            if let name = spot.logoAsset, let image = dartBundleImage(name) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(.horizontal, spot == .goldenBearCafe ? 0 : 10)
                    .padding(.vertical, spot == .goldenBearCafe ? 0 : 12)
            } else {
                Text(spot == .gatewayCafe ? "Gateway Café" : spot.name)
                    .font(.system(size: height * 0.3, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DartTheme.line.opacity(spot.plateColor == .white ? 1 : 0)))
        .accessibilityHidden(true)
    }
}

/// A square badge with the eatery's mark, sized like `DartIconTile`.
struct SpotBadge: View {
    let spot: PickupSpot
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous).fill(spot.plateColor)
            if let name = spot.badgeAsset, let image = dartBundleImage(name) {
                image
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(spot == .goldenBearCafe ? 0 : size * 0.1)
            } else {
                Text("G")
                    .font(.system(size: size * 0.5, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.31, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.31, style: .continuous).stroke(DartTheme.line.opacity(spot.plateColor == .white ? 1 : 0)))
        .accessibilityHidden(true)
    }
}

/// One of the four eateries, as a tappable tile.
struct PickupSpotTile: View {
    let spot: PickupSpot
    var selected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpotLogo(spot: spot)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DartTheme.limeInk, DartTheme.lime)
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(DartTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(spot.area)
                    .font(.caption)
                    .foregroundStyle(DartTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(selected ? DartTheme.limeWash : DartTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(selected ? DartTheme.limeDeep.opacity(0.55) : DartTheme.line, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
    }
}

/// The four pickup spots in a 2×2 grid. Tapping one calls `choose`.
struct PickupSpotGrid: View {
    var selection: PickupSpot? = nil
    let choose: (PickupSpot) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(PickupSpot.allCases) { spot in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) { choose(spot) }
                } label: {
                    PickupSpotTile(spot: spot, selected: selection == spot)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(spot.name), \(spot.area)")
                .accessibilityAddTraits(selection == spot ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
