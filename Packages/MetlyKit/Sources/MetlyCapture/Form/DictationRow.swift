import SwiftUI

/// Mic button · language menu (Русский / English) · status (preparing, model download, listening).
struct DictationRow: View {
    @Bindable var voice: VoiceNoteRecognizer
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { controls }
                VStack(alignment: .leading, spacing: 10) { controls }
            }
            DictationStatus(state: voice.state, language: voice.language)
        }
        .sensoryFeedback(.selection, trigger: voice.language)
    }

    @ViewBuilder private var controls: some View {
        DictationMicButton(state: voice.state, action: action)
        DictationLanguageMenu(language: $voice.language)
            .disabled(voice.isBusy)
        if voice.state == .preparing {
            ProgressView()
                .accessibilityLabel("Preparing Dictation")
        }
    }
}

private struct DictationMicButton: View {
    let state: VoiceNoteRecognizer.State
    let action: () -> Void

    private var isListening: Bool { state == .listening }
    private var isDownloading: Bool {
        if case .downloadingModel = state { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isListening ? "waveform" : "mic.fill")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative, isActive: isListening)
                .frame(minHeight: 30)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(isListening ? .red : .accentColor)
        .accessibilityLabel(accessibilityTitle)
    }

    private var title: LocalizedStringKey {
        if isListening { return "Stop" }
        return isDownloading ? "Cancel" : "Dictate"
    }

    private var accessibilityTitle: LocalizedStringKey {
        if isListening { return "Stop Dictation" }
        return isDownloading ? "Cancel Dictation" : "Dictate Note"
    }
}

/// Русский / English, remembered across launches. In Uzbek the menu notes that Uzbek isn't available yet
/// (Apple has no Uzbek speech model) — a plain note, no "coming soon" action.
private struct DictationLanguageMenu: View {
    @Binding var language: DictationLanguage

    var body: some View {
        Menu {
            Picker("Voice Note Language", selection: $language) {
                ForEach(DictationLanguage.allCases) { option in
                    Text(verbatim: option.nativeName).tag(option)
                }
            }
            .pickerStyle(.inline)
            if DictationLanguage.isUzbekAppLanguage() {
                Section {
                    Text(DictationCopy.uzbekUnavailable)
                }
            }
        } label: {
            Label {
                Text(verbatim: language.nativeName)
            } icon: {
                Image(systemName: "globe")
            }
            .frame(minHeight: 30)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.secondary)
        .accessibilityLabel("Voice Note Language")
        .accessibilityValue(Text(verbatim: language.nativeName))
    }
}

/// "Listening…" or the model download progress under the buttons.
private struct DictationStatus: View {
    let state: VoiceNoteRecognizer.State
    let language: DictationLanguage

    var body: some View {
        switch state {
        case .listening:
            Text("Listening… tap the mic to stop")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .downloadingModel(let fraction?):
            ProgressView(value: fraction) {
                downloadLabel
            } currentValueLabel: {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        case .downloadingModel(nil):
            HStack(spacing: 8) {
                ProgressView()
                downloadLabel
            }
            .accessibilityElement(children: .combine)
        default:
            EmptyView()
        }
    }

    private var downloadLabel: some View {
        Text(DictationCopy.downloading(language))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
