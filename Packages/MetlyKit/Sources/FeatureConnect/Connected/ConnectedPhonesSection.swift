import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Which numbers CONNECTED lists: all of them (primary first) once the person shared more than one —
/// their card face only shows the primary number.
enum ConnectedPhones {
    static func rows(for connection: Connection) -> [LabeledPhone] {
        let phones = connection.allPhones
        return phones.count > 1 ? phones : []
    }
}

/// "Phone Numbers": Mobile · Work · Home… — tap calls, touch and hold copies. Add to Contacts saves them all.
struct ConnectedPhonesSection: View {
    let connection: Connection

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        let phones = ConnectedPhones.rows(for: connection)
        if !phones.isEmpty {
            Section {
                ForEach(phones) { phone in
                    Button {
                        if let url = ContactLinks.call(phone.value) { openURL(url) }
                    } label: {
                        LabeledContent {
                            Text(phone.value)
                                .foregroundStyle(.tint)
                                .lineLimit(1)
                        } label: {
                            Label {
                                Text(phone.label.title)
                                    .foregroundStyle(.primary)
                            } icon: {
                                SettingsIcon(phone.label.symbolName, color: ContactFieldKind.phone.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") { copy(phone) }
                    }
                    .accessibilityLabel(Text("\(phone.label.title), \(phone.value)"))
                    .accessibilityHint("Calls this number. Touch and hold to copy")
                }
            } header: {
                Text("Phone Numbers")
            } footer: {
                Text("Add to Contacts saves every number with its label.")
            }
        }
    }

    private func copy(_ phone: LabeledPhone) {
        UIPasteboard.general.string = phone.value
        router.showToast(String(localized: "\(ContactFieldKind.phone.title) Copied"), systemImage: "doc.on.doc")
    }
}
