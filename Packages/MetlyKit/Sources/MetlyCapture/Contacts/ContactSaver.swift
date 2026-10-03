@preconcurrency import Contacts
import ContactsUI
import SwiftUI

/// iOS Contacts' "New Contact" screen prefilled from a `ContactDraft`.
/// Uses `CNContactViewController(forNewContact:)`, so no Contacts permission prompt is needed:
/// the user saves explicitly from the system UI.
public struct ContactSaver: UIViewControllerRepresentable {
    let draft: ContactDraft
    let onCompletion: (_ saved: Bool) -> Void

    public init(draft: ContactDraft, onCompletion: @escaping (_ saved: Bool) -> Void) {
        self.draft = draft
        self.onCompletion = onCompletion
    }

    public func makeUIViewController(context: Context) -> UINavigationController {
        let controller = CNContactViewController(forNewContact: draft.makeContact())
        controller.contactStore = CNContactStore()
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    public func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        context.coordinator.onCompletion = onCompletion
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    public final class Coordinator: NSObject, CNContactViewControllerDelegate {
        var onCompletion: (Bool) -> Void

        init(onCompletion: @escaping (Bool) -> Void) {
            self.onCompletion = onCompletion
        }

        public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
            onCompletion(contact != nil)
        }
    }
}

public extension View {
    /// Presents the system "New Contact" sheet while `item` is non-nil; `onCompletion(true)` when saved.
    /// Typical toast on success: "Added to Contacts".
    func contactSaver(item: Binding<ContactDraft?>, onCompletion: @escaping (_ saved: Bool) -> Void) -> some View {
        sheet(item: item) { draft in
            ContactSaver(draft: draft) { saved in
                item.wrappedValue = nil
                onCompletion(saved)
            }
            .ignoresSafeArea()
        }
    }
}
