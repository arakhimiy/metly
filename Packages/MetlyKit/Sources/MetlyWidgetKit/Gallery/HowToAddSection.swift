import AppIntents
import MetlyCore
import SwiftUI

/// "How to Add": step-by-step for Home Screen, Lock Screen and Control Center.
struct HowToAddSection: View {
    var body: some View {
        Section {
            HowToAddGroup(title: "Home Screen", systemImage: "apps.iphone", steps: [
                String(localized: "Touch and hold an empty area of your Home Screen until the apps jiggle.", bundle: .appStrings),
                String(localized: "Tap Edit, then tap Add Widget.", bundle: .appStrings),
                String(localized: "Search for \(Brand.appName), choose My QR, Card or Follow-ups, then tap Add Widget.", bundle: .appStrings),
            ])
            HowToAddGroup(title: "Lock Screen", systemImage: "lock.iphone", steps: [
                String(localized: "Touch and hold your Lock Screen, then tap Customize.", bundle: .appStrings),
                String(localized: "Choose Lock Screen, then tap the area below the time.", bundle: .appStrings),
                String(localized: "Choose \(Brand.appName) and tap a QR Code widget.", bundle: .appStrings),
            ])
            HowToAddGroup(title: "Control Center", systemImage: "switch.2", steps: [
                String(localized: "Swipe down from the top-right corner of the screen.", bundle: .appStrings),
                String(localized: "Touch and hold an empty area, then tap Add a Control.", bundle: .appStrings),
                String(localized: "Search for \(Brand.appName) and choose Show My QR.", bundle: .appStrings),
            ])
        } header: {
            Text("How to Add")
        }
    }
}

struct HowToAddGroup: View {
    let title: LocalizedStringKey
    let systemImage: String
    let steps: [String]

    var body: some View {
        DisclosureGroup {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                Label {
                    Text(step)
                } icon: {
                    Image(systemName: "\(index + 1).circle.fill")
                        .foregroundStyle(.tint)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Step \(index + 1): \(step)"))
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

/// "Siri & Shortcuts": the App Shortcuts phrases + a link to the Shortcuts app.
struct ShortcutPhrasesSection: View {
    var body: some View {
        Section {
            ForEach(WidgetShortcutPhrase.all) { phrase in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(phrase.text)”")
                        Text(phrase.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: phrase.systemImage)
                        .foregroundStyle(.tint)
                }
                .accessibilityElement(children: .combine)
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Siri & Shortcuts")
        } footer: {
            Text("Say a phrase to Siri, or find these actions in Shortcuts and Spotlight.")
        }
    }
}
