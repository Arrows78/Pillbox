import AppKit
import Contacts
import SwiftUI

// MARK: Reply to a text from the notification

/// Sends a reply in Messages to the sender of a text notification. The notification names the sender; the handle
/// (phone number or address) comes from the contact with that name, so Contacts access is asked for once.
enum MessageReply {
    static let app = "com.apple.MobileSMS"

    /// The first phone number or address of the contact called `name`.
    static func handle(for name: String) async -> String? {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { return nil }
        let keys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        guard let contact = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys))?.first else { return nil }
        return contact.phoneNumbers.first?.value.stringValue ?? (contact.emailAddresses.first?.value as String?)
    }

    /// The AppleScript that sends `text` to `handle`: iMessage first, SMS when iMessage cannot.
    nonisolated static func script(text: String, handle: String) -> String {
        func quote(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
        return """
        tell application "Messages"
            try
                send "\(quote(text))" to buddy "\(quote(handle))" of (first service whose service type is iMessage)
            on error
                send "\(quote(text))" to buddy "\(quote(handle))" of (first service whose service type is SMS)
            end try
        end tell
        """
    }

    /// Nil when the reply went out, otherwise what went wrong, in words for the notification row.
    static func reply(to sender: String, _ text: String) async -> String? {
        guard let handle = await handle(for: sender) else { return L("No number or address for this sender") }
        var error: NSDictionary?
        NSAppleScript(source: script(text: text, handle: handle))?.executeAndReturnError(&error)
        return error == nil ? nil : L("Messages could not send it")
    }
}

/// The reply line under a text notification.
struct SMSReplyField: View {
    let sender: String
    @State private var text = ""
    @State private var status: String?

    var body: some View {
        HStack(spacing: 6) {
            TextField(L("Reply"), text: $text)
                .textFieldStyle(.plain).font(.system(size: 11)).onSubmit(send)
            if let status { Text(verbatim: status).font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1) }
            Button(action: send) { Image(systemName: "paperplane.fill").font(.system(size: 10)) }
                .buttonStyle(.plain).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Send reply"))
        }
        .padding(.top, 2)
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        status = nil
        Task {
            let error = await MessageReply.reply(to: sender, body)
            status = error
            if error == nil { text = "" }
        }
    }
}
