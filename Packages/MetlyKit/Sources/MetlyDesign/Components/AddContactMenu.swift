import MetlyCore
import SwiftUI

/// "+ Add Contact": pick a kind (Phone, Telegram, WhatsApp, Instagram, Email, Website, LinkedIn).
/// PROFILE › Contact Details, a card's "Show on This Card" and a person's contact info use it.
public struct AddContactMenu: View {
    let isEnabled: Bool
    let action: (ContactFieldKind) -> Void

    public init(isEnabled: Bool = true, action: @escaping (ContactFieldKind) -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Menu {
            ForEach(ContactFieldKind.addOrder) { kind in
                Button {
                    action(kind)
                } label: {
                    Label(kind.title, systemImage: kind.symbolName)
                }
            }
        } label: {
            Label("Add Contact", systemImage: "plus.circle.fill")
                .symbolRenderingMode(.multicolor)
        }
        .disabled(!isEnabled)
        .accessibilityHint(isEnabled ? Text("Choose a phone, messenger or link to add") : Text("You can add up to \(ContactEntry.maxCount) contacts"))
    }
}

#Preview {
    Form {
        AddContactMenu { _ in }
        AddContactMenu(isEnabled: false) { _ in }
    }
}
