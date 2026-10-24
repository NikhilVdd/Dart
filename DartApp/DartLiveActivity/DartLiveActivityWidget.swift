import ActivityKit
import SwiftUI
import WidgetKit

@main
struct DartLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        DartLiveActivityWidget()
    }
}

struct DartLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DartDeliveryAttributes.self) { context in
            DartLockScreenView(context: context)
                .activityBackgroundTint(Color(red: 0.03, green: 0.04, blue: 0.03))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "dart://request/\(context.attributes.requestID)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DartMark()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Color.dartLime)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        DartProgress(progress: context.state.progress)
                        Text(context.state.headline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                DartMark()
            } compactTrailing: {
                Image(systemName: statusSymbol(context.state.status)).foregroundStyle(Color.dartLime)
            } minimal: {
                Image(systemName: statusSymbol(context.state.status)).foregroundStyle(Color.dartLime)
            }
            .keylineTint(Color.dartLime)
            .widgetURL(URL(string: "dart://request/\(context.attributes.requestID)"))
        }
    }
}

private struct DartLockScreenView: View {
    let context: ActivityViewContext<DartDeliveryAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                DartMark()
                Text("DART STATUS").font(.caption2.bold()).tracking(1.2).foregroundStyle(Color.dartLime)
                Spacer()
                Text(Date(timeIntervalSince1970: context.state.updatedAt), style: .relative).font(.caption).foregroundStyle(.secondary)
            }
            Text(context.attributes.title).font(.title3.bold()).lineLimit(1)
            DartProgress(progress: context.state.progress)
            HStack(spacing: 8) {
                Image(systemName: statusSymbol(context.state.status)).foregroundStyle(Color.dartLime)
                Text(context.state.headline).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
            }
            HStack {
                Label(context.attributes.pickup, systemImage: "bag").lineLimit(1)
                Spacer(minLength: 12)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Label(context.attributes.destination, systemImage: "mappin").lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct DartMark: View {
    var body: some View {
        Text("G")
            .font(.caption.bold())
            .foregroundStyle(.black)
            .frame(width: 24, height: 24)
            .background(Color.dartLime, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct DartProgress: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(Color.dartLime).frame(width: proxy.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: progress)
        .accessibilityLabel("Delivery progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private func statusSymbol(_ status: String) -> String {
    switch status {
    case "accepted": "person.crop.circle.badge.checkmark"
    case "picking_up": "bag.fill"
    case "on_the_way": "figure.walk.motion"
    case "delivered": "shippingbox.fill"
    case "completed": "checkmark.circle.fill"
    default: "clock.fill"
    }
}

private extension Color {
    static let dartLime = Color(red: 0.776, green: 1, blue: 0)
}
