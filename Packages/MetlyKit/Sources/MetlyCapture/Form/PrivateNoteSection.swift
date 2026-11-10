import SwiftUI

/// Multiline private note + voice dictation (live transcript appended to what was typed) in the language
/// chosen next to the mic. Return adds a line, so the keyboard gets a Done button.
struct PrivateNoteSection: View {
    @Binding var note: String
    let voice: VoiceNoteRecognizer
    /// Read when dictation starts (`DictationVocabulary`).
    var vocabulary: () -> [String] = { [] }

    /// The note as it was when dictation started; the live transcript is appended to it.
    @State private var noteBeforeDictation = ""
    @State private var settingsAlert: SettingsAlert?
    @State private var problem: DictationProblem?
    @FocusState private var isEditingNote: Bool

    var body: some View {
        Section {
            TextField("What did you talk about?", text: $note, axis: .vertical)
                .lineLimit(3...8)
                .focused($isEditingNote)
            DictationRow(voice: voice, action: toggleDictation)
        } header: {
            Text("Private Note")
        } footer: {
            Label("Only you can see this. Audio isn't stored.", systemImage: "lock.fill")
        }
        .toolbar {
            if isEditingNote {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isEditingNote = false }
                }
            }
        }
        .onChange(of: voice.transcript) { _, transcript in
            guard voice.isListening || !transcript.isEmpty else { return }
            note = Self.compose(noteBeforeDictation, transcript)
        }
        .onChange(of: voice.state) { _, state in
            handle(state)
        }
        .settingsAlert($settingsAlert)
        .alert(problem?.title ?? "", isPresented: isShowingProblem, presenting: problem) { problem in
            if problem.canRetry {
                Button("Cancel", role: .cancel) {}
                Button("Try Again", action: startDictation)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { problem in
            Text(problem.message)
        }
    }

    private var isShowingProblem: Binding<Bool> {
        Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })
    }

    private func toggleDictation() {
        if voice.isBusy {
            voice.stop()
        } else {
            startDictation()
        }
    }

    private func startDictation() {
        noteBeforeDictation = note
        voice.vocabulary = vocabulary()
        voice.start()
    }

    private func handle(_ state: VoiceNoteRecognizer.State) {
        switch state {
        case .denied(.microphone):
            settingsAlert = .microphoneOff
            voice.acknowledge()
        case .denied(.speech):
            settingsAlert = .speechOff
            voice.acknowledge()
        case .unavailable(let reason):
            problem = DictationProblem(reason)
            voice.acknowledge()
        case .failed(let message):
            problem = DictationProblem(failure: message)
            voice.acknowledge()
        case .idle, .preparing, .downloadingModel, .listening:
            break
        }
    }

    static func compose(_ base: String, _ transcript: String) -> String {
        let base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return base }
        return base.isEmpty ? transcript : base + " " + transcript
    }
}

/// What the dictation alert says (and whether it offers Try Again).
struct DictationProblem: Equatable {
    var title: String
    var message: String
    var canRetry: Bool

    init(_ reason: DictationUnavailability) {
        title = DictationCopy.title(for: reason)
        message = DictationCopy.message(for: reason)
        canRetry = reason.isRetryable
    }

    init(failure message: String) {
        title = String(localized: "Voice Notes Unavailable")
        self.message = message
        canRetry = true
    }
}
