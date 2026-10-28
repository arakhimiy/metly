import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// SCANNED_CARD for a foreign vCard QR (SPEC §9 Q41): review the contact, then
/// **Add to People** (`.scanQR` connection → ADD_CONTEXT) or **Save to Contacts**. No Connect.
struct ContactCardDetail: View {
    let contact: PaperCardDraft
    let model: ScannedCardModel

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(Connection.live) private var people: [Connection]

    @State private var contactDraft: ContactDraft?
    @State private var addedCount = 0

    var body: some View {
        List {
            ContactCardHeader(contact: contact)
            Section {
                Group {
                    if let existing {
                        Button(action: { open(existing) }) {
                            Label("Open in People", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        Button(action: addToPeople) {
                            Label("Add to People", systemImage: "person.crop.circle.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .prominentButtonStyle()
                .controlSize(.large)
            } footer: {
                if let existing {
                    Text("\(existing.fullName) is already in your People.")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            ContactFieldsSection(fields: contact.fields, phoneLabel: contact.phoneLabel, additionalPhones: contact.additionalPhones)

            Section {
                Button("Save to Contacts", systemImage: "square.and.arrow.down", action: saveToContacts)
            }
        }
        .contactSaver(item: $contactDraft, onCompletion: contactSaved)
        .sensoryFeedback(.success, trigger: addedCount)
    }

    /// Same phone, email or Telegram as someone already in People.
    private var existing: Connection? {
        ScanConnectionFactory.existing(matching: contact.fields, phones: contact.additionalPhones.map(\.value), among: people)
    }

    private func addToPeople() {
        let connection = model.addToPeople(contact, modelContext: modelContext)
        addedCount += 1
        router.present(.addContext(connectionID: connection.id))
    }

    private func open(_ person: Connection) {
        router.open(.connectionDetail(id: person.id), in: .people)
    }

    private func saveToContacts() {
        contactDraft = ContactDraft(fullName: ScanConnectionFactory.displayName(for: contact), jobTitle: contact.jobTitle,
                                    company: contact.company, fields: contact.fields)
    }

    private func contactSaved(_ saved: Bool) {
        if saved { router.showToast(String(localized: "Added to Contacts"), systemImage: "person.crop.circle.badge.checkmark") }
    }
}
