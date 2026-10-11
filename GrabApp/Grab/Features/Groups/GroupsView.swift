import SwiftUI

struct GroupsView: View {
    private let friends = PreviewData.groups.filter { $0.kind == .friends }
    private let buildings = PreviewData.groups.filter { $0.kind == .building }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    PreviewPill()
                    Text("Groups").font(.largeTitle.bold())
                    Text("Plan free runs with friends or approved paid runs with your building.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    SectionHeading(title: "Friends", subtitle: "Shared runs are free between friends")
                    ForEach(friends) { group in
                        NavigationLink(value: group) { GroupCard(group: group) }
                            .buttonStyle(PressableStyle())
                    }

                    SectionHeading(title: "Your building", subtitle: "Paid runs are approved by the shopper")
                        .padding(.top, 8)
                    ForEach(buildings) { group in
                        NavigationLink(value: group) { GroupCard(group: group) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, GrabTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(GrabBackdrop())
            .navigationDestination(for: GrabGroup.self) { GroupDetailView(group: $0) }
        }
    }
}

private struct GroupDetailView: View {
    let group: GrabGroup
    @State private var selectedItem: GrabItem?
    @State private var upcomingMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    PreviewPill(text: group.kind.rawValue.uppercased())
                    Text(group.name).font(.largeTitle.bold())
                    HStack {
                        AvatarStack(initials: group.memberInitials)
                        Text("\(group.memberCount) members").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                SectionHeading(title: "Conversation", subtitle: "Sample messages · sending arrives in Section 3")
                VStack(spacing: 12) {
                    ForEach(group.conversation) { message in
                        HStack {
                            if message.isCurrentUser { Spacer(minLength: 45) }
                            VStack(alignment: message.isCurrentUser ? .trailing : .leading, spacing: 4) {
                                Text(message.sender).font(.caption).foregroundStyle(.secondary)
                                Text(message.body)
                                    .font(.subheadline)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(message.isCurrentUser ? GrabTheme.blue : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                                    .foregroundStyle(message.isCurrentUser ? .white : .primary)
                                Text(message.time).font(.caption2).foregroundStyle(.tertiary)
                            }
                            if !message.isCurrentUser { Spacer(minLength: 45) }
                        }
                    }
                    Button { upcomingMessage = "Real group messaging arrives in Section 3." } label: {
                        Label("Message sending · coming in Section 3", systemImage: "text.bubble")
                            .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(14)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(18)
                .grabGlass()

                SectionHeading(title: "Active store run")
                Button { selectedItem = group.run } label: { GrabItemCard(item: group.run) }
                    .buttonStyle(PressableStyle())

                HStack {
                    SectionHeading(title: "Shopping list", subtitle: "Preview items")
                    Button("Edit later") { upcomingMessage = "Shopping-list editing arrives in Section 3." }
                        .font(.subheadline.weight(.semibold))
                }
                VStack(spacing: 0) {
                    ForEach(Array(group.shoppingList.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            Image(systemName: "circle").foregroundStyle(GrabTheme.blue)
                            Text(item)
                            Spacer()
                        }
                        .padding(.vertical, 13)
                        if index < group.shoppingList.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 18)
                .grabGlass()
            }
            .padding(GrabTheme.pageInset)
            .padding(.bottom, 96)
        }
        .background(GrabBackdrop())
        .sheet(item: $selectedItem) { ItemDetailView(item: $0) }
        .alert("Upcoming functionality", isPresented: Binding(get: { upcomingMessage != nil }, set: { if !$0 { upcomingMessage = nil } })) {
            Button("OK", role: .cancel) { upcomingMessage = nil }
        } message: { Text(upcomingMessage ?? "") }
    }
}
