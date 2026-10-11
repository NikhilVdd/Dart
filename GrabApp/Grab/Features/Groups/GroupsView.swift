import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var store: GrabStore
    @State private var showJoin = false
    @State private var showCreate = false
    @State private var inviteCode = ""
    @State private var newGroupName = ""

    private var friends: [GrabGroup] { store.groups.filter { $0.kind == .friends } }
    private var buildings: [GrabGroup] { store.groups.filter { $0.kind == .building } }
    private var discoverable: [GrabGroup] { store.discoverableGroups.filter { $0.kind == .building } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !store.isLive { PreviewPill() }
                    Text("Groups").font(.largeTitle.bold())
                    Text("Plan free runs with friends or approved paid runs with your building.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    SectionHeading(title: "Friends", subtitle: "Shared runs are free between friends")
                    if store.isLive && friends.isEmpty {
                        EmptyStateCard(title: "No friend groups yet", message: "Create one or join with an invite code.")
                    }
                    ForEach(friends) { group in
                        NavigationLink(value: group.id) { GroupCard(group: group) }
                            .buttonStyle(PressableStyle())
                    }

                    SectionHeading(title: "Your building", subtitle: "Paid runs are approved by the shopper")
                        .padding(.top, 8)
                    ForEach(buildings) { group in
                        NavigationLink(value: group.id) { GroupCard(group: group) }
                            .buttonStyle(PressableStyle())
                    }
                    ForEach(discoverable) { group in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name).font(.headline)
                                Text("\(group.memberCount) neighbors on Grab").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Join") { Task { await store.joinBuilding(group) } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(18)
                        .grabGlass()
                    }
                }
                .padding(.horizontal, GrabTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(GrabBackdrop())
            .refreshable { await store.refresh() }
            .navigationDestination(for: UUID.self) { id in
                if let group = store.group(id: id) { GroupDetailView(group: group) }
            }
            .toolbar {
                if store.isLive {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button { showCreate = true } label: { Label("New friend group", systemImage: "person.2.badge.plus") }
                            Button { showJoin = true } label: { Label("Join with invite code", systemImage: "ticket") }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .accessibilityLabel("Add group")
                    }
                }
            }
            .alert("Join a group", isPresented: $showJoin) {
                TextField("Invite code", text: $inviteCode)
                Button("Join") { Task { if await store.joinGroup(code: inviteCode) { inviteCode = "" } } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Ask a member for the group’s 8-character code.") }
            .alert("New friend group", isPresented: $showCreate) {
                TextField("Name", text: $newGroupName)
                Button("Create") { Task { if await store.createGroup(named: newGroupName) { newGroupName = "" } } }
                Button("Cancel", role: .cancel) { }
            }
        }
    }
}

private struct GroupDetailView: View {
    @EnvironmentObject private var store: GrabStore
    let group: GrabGroup
    @State private var selectedItem: GrabItem?
    @State private var upcomingMessage: String?
    @State private var draft = ""
    @State private var newListItem = ""
    @State private var sending = false

    /// Re-read from the store so realtime refreshes show up while this screen is open.
    private var current: GrabGroup { store.group(id: group.id) ?? group }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    PreviewPill(text: current.kind.rawValue.uppercased())
                    Text(current.name).font(.largeTitle.bold())
                    HStack {
                        AvatarStack(initials: current.memberInitials)
                        Text("\(current.memberCount) members").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if store.isLive, let code = current.inviteCode {
                        Label("Invite code \(code)", systemImage: "ticket")
                            .font(.caption.weight(.semibold)).foregroundStyle(GrabTheme.blue)
                            .textSelection(.enabled)
                    }
                }

                SectionHeading(title: "Conversation", subtitle: store.isLive ? nil : "Sample messages · sign in to chat")
                VStack(spacing: 12) {
                    let conversation = store.conversation(for: current)
                    if conversation.isEmpty {
                        Text("No messages yet. Say hi!").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(conversation) { message in
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
                    if store.isLive {
                        HStack(spacing: 10) {
                            TextField("Message \(current.name)", text: $draft, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                            Button { Task { await send() } } label: {
                                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                            }
                            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Send message")
                        }
                    } else {
                        Button { upcomingMessage = "Sign in from Profile to send messages." } label: {
                            Label("Sign in to send messages", systemImage: "text.bubble")
                                .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).padding(14)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(18)
                .grabGlass()

                if let run = current.run {
                    SectionHeading(title: "Active store run")
                    Button { selectedItem = run } label: { GrabItemCard(item: run) }
                        .buttonStyle(PressableStyle())
                }

                SectionHeading(title: "Shopping list", subtitle: store.isLive ? "Tap to check off" : "Preview items")
                VStack(spacing: 0) {
                    ForEach(Array(current.shoppingList.enumerated()), id: \.element.id) { index, item in
                        Button {
                            if store.isLive { Task { await store.toggle(item) } }
                            else { upcomingMessage = "Sign in from Profile to edit the shopping list." }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.isPicked ? "checkmark.circle.fill" : "circle").foregroundStyle(GrabTheme.blue)
                                Text(item.body).strikethrough(item.isPicked).foregroundStyle(item.isPicked ? .secondary : .primary)
                                Spacer()
                                if item.quantity > 1 { Text("×\(item.quantity)").font(.subheadline).foregroundStyle(.secondary) }
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < current.shoppingList.count - 1 { Divider() }
                    }
                    if store.isLive {
                        if !current.shoppingList.isEmpty { Divider() }
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle").foregroundStyle(GrabTheme.blue)
                            TextField("Add an item", text: $newListItem)
                                .onSubmit { Task { await addItem() } }
                        }
                        .padding(.vertical, 13)
                    }
                }
                .padding(.horizontal, 18)
                .grabGlass()
            }
            .padding(GrabTheme.pageInset)
            .padding(.bottom, 96)
        }
        .background(GrabBackdrop())
        .task { await store.openConversation(groupID: group.id) }
        .onDisappear { store.closeConversation(groupID: group.id) }
        .sheet(item: $selectedItem) { ItemDetailView(item: $0) }
        .alert("Sign in required", isPresented: Binding(get: { upcomingMessage != nil }, set: { if !$0 { upcomingMessage = nil } })) {
            Button("OK", role: .cancel) { upcomingMessage = nil }
        } message: { Text(upcomingMessage ?? "") }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        if await store.sendMessage(body, to: group.id) { draft = "" }
    }

    private func addItem() async {
        let body = newListItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if await store.addListItem(body, groupID: group.id, runID: current.run?.backend?.id) { newListItem = "" }
    }
}
