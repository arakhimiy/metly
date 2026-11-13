import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI

/// "Show on This Card", top part (create Details step and the editor's Details tab): one switch each for
/// the job title and company, and inline photo / logo rows that add, change or remove the image right here.
/// The name always shows. Contacts follow in `CardFieldsSection`, the QR code in `CardQRSection`.
struct CardIdentitySection: View {
    let profile: Profile?
    @Binding var design: CardDesign
    @Binding var options: CardFaceOptions
    @Binding var photo: MediaEdit
    @Binding var logo: MediaEdit

    var body: some View {
        Section {
            CardTextToggleRow(title: String(localized: "Job Title", bundle: .appStrings), value: profile?.jobTitle ?? "", isOn: $options.showJobTitle)
            CardTextToggleRow(title: String(localized: "Company", bundle: .appStrings), value: profile?.company ?? "", isOn: $options.showCompany)
            CardMediaRow(kind: .logo, imageData: logoData, edit: $logo, isOn: $design.showLogo)
            if logoData != nil, design.showLogo, design.template.drawsLogoInChosenStyle {
                Picker("Logo Color", selection: $options.logoStyle) {
                    Text("Original").tag(CardLogoStyle.original)
                    Text("One Color").tag(CardLogoStyle.mono)
                }
            }
            CardMediaRow(kind: .photo, imageData: photoData, edit: $photo, isOn: $design.showPhoto)
        } header: {
            Text("Show on This Card")
        } footer: {
            if let note { Text(note) }
        }
    }

    private var logoData: Data? { logo.resolved(profile?.logoData) }
    private var photoData: Data? { photo.resolved(profile?.photoData) }

    /// Says when the chosen layout leaves out something that is switched on.
    private var note: String? {
        let template = design.template.title
        var notes: [String] = []
        if logoData != nil, design.showLogo, !design.templateShowsLogo {
            notes.append(String(localized: "The \(template) template doesn’t show a logo.", bundle: .appStrings))
        }
        if photoData != nil, design.showPhoto, !design.templateShowsPhoto {
            notes.append(String(localized: "The \(template) template doesn’t show a photo.", bundle: .appStrings))
        } else if photoData != nil, design.showPhoto, logoData != nil, design.showLogo, design.template == .split {
            notes.append(String(localized: "Duotone shows your logo in place of the photo.", bundle: .appStrings))
        }
        if logoData != nil, design.showLogo, options.logoStyle == .mono {
            notes.append(String(localized: "One color needs a logo with a transparent background (PNG).", bundle: .appStrings))
        }
        notes.append(String(localized: "Your photo and logo are shared by all your cards.", bundle: .appStrings))
        return notes.joined(separator: " ")
    }
}

/// A profile value with this card's switch; an empty value says where to add it.
private struct CardTextToggleRow: View {
    let title: String
    let value: String
    @Binding var isOn: Bool

    var body: some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(trimmed.isEmpty ? String(localized: "Add it in Profile", bundle: .appStrings) : trimmed)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .disabled(trimmed.isEmpty)
    }
}

/// The QR code switch.
struct CardQRSection: View {
    @Binding var showQR: Bool

    var body: some View {
        Section {
            Toggle("QR Code", isOn: $showQR)
        } footer: {
            Text("Always black on a white plate, so every phone can scan it.")
        }
    }
}

extension CardTemplate {
    /// Layouts that honour the Original / One color choice. Foil, Monogram, Duotone and Editorial always
    /// press a transparent logo in their own ink (foil, deboss, panel colour).
    var drawsLogoInChosenStyle: Bool { [.minimal, .bold, .stack].contains(self) }
}
