import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI

/// Editor "Media": profile photo, logo (both profile-level, applied on Done) and the QR switch.
struct EditorMediaSection: View {
    @Binding var draft: CardDraft
    let profile: Profile?

    var body: some View {
        MediaPickerSection(kind: .photo, imageData: draft.photo.resolved(profile?.photoData),
                           edit: $draft.photo, showOnCard: $draft.design.showPhoto,
                           note: draft.design.templateShowsPhoto ? nil
                               : String(localized: "The \(draft.design.template.title) template doesn’t show a photo."))

        MediaPickerSection(kind: .logo, imageData: draft.logo.resolved(profile?.logoData),
                           edit: $draft.logo, showOnCard: $draft.design.showLogo,
                           note: draft.design.templateShowsLogo ? nil
                               : String(localized: "The \(draft.design.template.title) template doesn’t show a logo."))

        Section {
            Toggle("Show QR Code", isOn: $draft.design.showQR)
        } header: {
            Text("QR Code")
        } footer: {
            Text("Always black on a white plate. Logos never go on the code.")
        }
    }
}
