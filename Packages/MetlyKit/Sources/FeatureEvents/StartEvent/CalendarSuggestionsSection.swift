import MetlyCore
import SwiftUI

/// "From Your Calendar": asks for calendar access in context, lists upcoming events
/// (tap fills the form) or explains how to turn access back on.
struct CalendarSuggestionsSection: View {
    let provider: CalendarSuggestionProvider
    let selectedIdentifier: String?
    let onPick: (CalendarSuggestion) -> Void

    var body: some View {
        Section {
            switch provider.access {
            case .notDetermined:
                CalendarAccessPromptRow(isRequesting: provider.isRequesting, onAllow: requestAccess)
            case .denied:
                CalendarAccessOffRows()
            case .restricted:
                Label("Calendar access is restricted on this iPhone.", systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            case .granted:
                if provider.suggestions.isEmpty {
                    Label("Nothing on your calendar for the next two weeks.", systemImage: "calendar")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(provider.suggestions) { suggestion in
                        CalendarSuggestionRow(suggestion: suggestion,
                                              isSelected: suggestion.eventIdentifier == selectedIdentifier) {
                            onPick(suggestion)
                        }
                    }
                }
            }
        } header: {
            Text("From Your Calendar")
        } footer: {
            if provider.access == .notDetermined || provider.access == .granted {
                Text("\(Brand.appName) looks at your calendar on this iPhone only to suggest events. Only the event you pick is saved.")
            }
        }
    }

    private func requestAccess() {
        Task { await provider.requestAccess() }
    }
}

/// Pre-permission explanation; tapping shows the system calendar prompt.
private struct CalendarAccessPromptRow: View {
    let isRequesting: Bool
    let onAllow: () -> Void

    var body: some View {
        Button(action: onAllow) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggest Events From Calendar")
                    Text("Pick a conference or meetup to fill in the name, place and dates.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
            } icon: {
                Image(systemName: "calendar.badge.plus")
            }
        }
        .disabled(isRequesting)
        .accessibilityHint("Asks for access to your calendar")
    }
}

/// Denied / write-only: explanation + Open Settings.
private struct CalendarAccessOffRows: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Calendar Access Is Off")
                Text("Allow full calendar access in Settings to see your events here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        Button("Open Settings", action: openSettings)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

/// One calendar event: title, "Today · Hyatt Regency", checkmark when picked.
private struct CalendarSuggestionRow: View {
    let suggestion: CalendarSuggestion
    let isSelected: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        // Explicit colors: hierarchical styles resolve against the button tint.
                        Text(suggestion.title)
                            .foregroundStyle(Color.primary)
                        Text(suggestion.subtitle())
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                } icon: {
                    Image(systemName: "calendar")
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Fills in the event details")
    }
}
