import SwiftUI

/// Multiline private note + voice dictation (live transcript appended to what was typed).
struct PrivateNoteSection: View {
    @Binding var note: String
    let voice: VoiceNoteRecognizer

    /// The note as it was when dictation started; the live transcript is appended to it.
    @State private var noteBeforeDictation = ""
    @State private var settingsAlert: SettingsAlert?
    @State private var showsUnavailable = false

    var body: some View {
        Section {
            TextField("What did you talk about?", text: $note, axis: .vertical)
                .lineLimit(3...8)
            DictationRow(state: voice.state, action: toggleDictation)
        } header: {
            Text("Private Note")
        } footer: {
            Label("Only you can see this. Audio isn't stored.", systemImage: "lock.fill")
        }
        .onChange(of: voice.transcript) { _, transcript in
            guard voice.isListening || !transcript.isEmpty else { return }
            note = Self.compose(noteBeforeDictation, transcript)
        }
        .onChange(of: voice.state) { _, state in
            handle(state)
        }
        .settingsAlert($settingsAlert)
        .alert("Voice Notes Unavailable", isPresented: $showsUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Dictation on this iPhone isn't available for your language right now. You can still type your note.")
        }
    }

    private func toggleDictation() {
        if voice.isBusy {
            voice.stop()
        } else {
            noteBeforeDictation = note
            voice.start()
        }
    }

    private func handle(_ state: VoiceNoteRecognizer.State) {
        switch state {
        case .denied(.microphone):
            settingsAlert = .microphoneOff
            voice.acknowledge()
        case .denied(.speech):
            settingsAlert = .speechOff
            voice.acknowledge()
        case .unavailable, .failed:
            showsUnavailable = true
            voice.acknowledge()
        case .idle, .preparing, .listening:
            break
        }
    }

    static func compose(_ base: String, _ transcript: String) -> String {
        let base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return base }
        return base.isEmpty ? transcript : base + " " + transcript
    }
}

private struct DictationRow: View {
    let state: VoiceNoteRecognizer.State
    let action: () -> Void

    private var isListening: Bool { state == .listening }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                Label(isListening ? "Stop" : "Dictate", systemImage: isListening ? "waveform" : "mic.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative, isActive: isListening)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(isListening ? .red : .accentColor)
            .accessibilityLabel(isListening ? "Stop Dictation" : "Dictate Note")

            if state == .preparing {
                ProgressView()
            } else if isListening {
                Text("Listening… tap the mic to stop")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
