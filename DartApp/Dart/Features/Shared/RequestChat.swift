import SwiftUI

/// One chat message, shared by group chat and request chat.
struct ChatBubble: View {
    let message: Message

    var body: some View {
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
}

/// A text field with a send button.
struct ChatComposer: View {
    let placeholder: String
    let send: (String) async -> Bool

    @State private var draft = ""
    @State private var sending = false

    var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .onSubmit { Task { await submit() } }
            Button { Task { await submit() } } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
            }
            .buttonStyle(.plain)
            .foregroundStyle(GrabTheme.blue)
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
    }

    private func submit() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        if await send(body) { draft = "" }
    }
}

/// Private chat between a request's requester and its helper, shown in the item details.
struct RequestChatCard: View {
    @EnvironmentObject private var store: GrabStore
    let item: GrabItem

    private var ref: BackendRef? { item.backend }
    private var isOpen: Bool { [.accepted, .pickingUp, .onTheWay, .delivered].contains(item.status) }
    private var otherName: String {
        guard let ref else { return "them" }
        if ref.role == .helper { return item.person.name.split(separator: " ").first.map(String.init) ?? "the requester" }
        return "your helper"
    }

    var body: some View {
        if let ref, ref.source == .request, [.owner, .helper].contains(ref.role) {
            let messages = store.requestChat(for: ref.id)
            if isOpen || !messages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "Messages", subtitle: isOpen ? "Only you and \(otherName) can see these" : "This chat is closed")
                    if messages.isEmpty {
                        Text(ref.role == .helper
                             ? "Ask about brand, size or where to leave it."
                             : "Tell your helper anything they need to know: room number, substitutes, how you’ll pay for the item.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(messages) { ChatBubble(message: $0) }
                    if isOpen {
                        ChatComposer(placeholder: "Message \(otherName)") { body in
                            await store.sendRequestMessage(body, requestID: ref.id)
                        }
                    }
                }
                .padding(18)
                .grabGlass()
                .task(id: ref.id) { await store.openRequestChat(requestID: ref.id) }
                .onDisappear { store.closeRequestChat(requestID: ref.id) }
            } else {
                Color.clear.frame(height: 0)
                    .task(id: ref.id) { await store.openRequestChat(requestID: ref.id) }
                    .onDisappear { store.closeRequestChat(requestID: ref.id) }
            }
        }
    }
}
