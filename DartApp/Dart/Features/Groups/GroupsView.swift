import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var store: DartStore
    @State private var showJoin = false
    @State private var showCreate = false
    @State private var inviteCode = ""
    @State private var newGroupName = ""
    @State private var choosingHome = false
    @State private var homeID: UUID?

    private var friends: [DartGroup] { store.groups.filter { $0.kind == .friends } }
    private var buildings: [DartGroup] { store.groups.filter { $0.kind == .building } }
    private var discoverable: [DartGroup] { store.discoverableGroups.filter { $0.kind == .building } }

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
                    if store.isLive && buildings.isEmpty {
                        Button { homeID = store.profile?.homePlaceID; choosingHome = true } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "house.fill").font(.title3).foregroundStyle(DartTheme.blue)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Where do you live?").font(.headline).foregroundStyle(.primary)
                                    Text("Choose your residence hall or apartment to join its building group.")
                                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(18)
                            .dartSurface()
                        }
                        .buttonStyle(PressableStyle())
                    }
                    ForEach(discoverable) { group in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.name).font(.headline)
                                Text("\(group.memberCount) neighbors on Dart").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Join") { Task { await store.joinBuilding(group) } }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(18)
                        .dartSurface()
                    }
                }
                .padding(.horizontal, DartTheme.pageInset)
                .padding(.top, 18)
                .padding(.bottom, 116)
            }
            .background(DartBackdrop())
            .refreshable { await store.refresh() }
            .sheet(isPresented: $choosingHome) {
                PlaceSearchView(title: "Where you live", selection: $homeID, filter: .destinations, allowsAnyStore: false)
            }
            .onChange(of: homeID) { _, id in
                guard let id, id != store.profile?.homePlaceID else { return }
                Task { _ = await store.setHome(id) }
            }
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
    @EnvironmentObject private var store: DartStore
    let group: DartGroup
    @State private var selectedItem: DartItem?
    @State private var upcomingMessage: String?
    @State private var newListItem = ""
    @State private var confirmLeave = false
    @Environment(\.dismiss) private var dismiss

    /// Re-read from the store so realtime refreshes show up while this screen is open.
    private var current: DartGroup { store.group(id: group.id) ?? group }

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
                            .font(.caption.weight(.semibold)).foregroundStyle(DartTheme.blue)
                            .textSelection(.enabled)
                    }
                }

                SectionHeading(title: "Conversation", subtitle: store.isLive ? nil : "Sample messages · sign in to chat")
                VStack(spacing: 12) {
                    let conversation = store.conversation(for: current)
                    if conversation.isEmpty {
                        Text("No messages yet. Say hi!").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(conversation) { ChatBubble(message: $0) }
                    if store.isLive {
                        ChatComposer(placeholder: "Message \(current.name)") { body in
                            await store.sendMessage(body, to: group.id)
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
                .dartSurface()

                if let run = current.run {
                    SectionHeading(title: "Active store run")
                    Button { selectedItem = run } label: { DartItemCard(item: run) }
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
                                Image(systemName: item.isPicked ? "checkmark.circle.fill" : "circle").foregroundStyle(DartTheme.blue)
                                Text(item.body).strikethrough(item.isPicked).foregroundStyle(item.isPicked ? .secondary : .primary)
                                Spacer()
                                if item.quantity > 1 { Text("×\(item.quantity)").font(.subheadline).foregroundStyle(.secondary) }
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if store.isLive {
                                Button(role: .destructive) { Task { _ = await store.delete(item) } } label: {
                                    Label("Remove from list", systemImage: "trash")
                                }
                            }
                        }
                        if index < current.shoppingList.count - 1 { Divider() }
                    }
                    if store.isLive {
                        if !current.shoppingList.isEmpty { Divider() }
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle").foregroundStyle(DartTheme.blue)
                            TextField("Add an item", text: $newListItem)
                                .onSubmit { Task { await addItem() } }
                        }
                        .padding(.vertical, 13)
                    }
                }
                .padding(.horizontal, 18)
                .dartSurface()
                if store.isLive && !current.shoppingList.isEmpty {
                    Text("Touch and hold an item to remove it.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(DartTheme.pageInset)
            .padding(.bottom, 96)
        }
        .background(DartBackdrop())
        .task { await store.openConversation(groupID: group.id) }
        .onDisappear { store.closeConversation(groupID: group.id) }
        .sheet(item: $selectedItem) { ItemDetailView(item: $0) }
        .toolbar {
            if store.isLive && current.isMember {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmLeave = true } label: {
                            Label("Leave group", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Group options")
                }
            }
        }
        .confirmationDialog("Leave \(current.name)?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) {
                Task { if await store.leave(current) { dismiss() } }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(current.kind == .building
                 ? "You’ll stop seeing this building’s runs, and it will no longer be your home."
                 : "You’ll stop seeing this group’s chat, list and runs. Rejoin any time with the invite code.")
        }
        .alert("Sign in required", isPresented: Binding(get: { upcomingMessage != nil }, set: { if !$0 { upcomingMessage = nil } })) {
            Button("OK", role: .cancel) { upcomingMessage = nil }
        } message: { Text(upcomingMessage ?? "") }
    }

    private func addItem() async {
        let body = newListItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        if await store.addListItem(body, groupID: group.id, runID: current.run?.backend?.id) { newListItem = "" }
    }
}
