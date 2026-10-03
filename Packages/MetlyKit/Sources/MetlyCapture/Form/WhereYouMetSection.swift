import SwiftUI

/// Event · Place · City · Time, auto-filled from the active event or the current location ("Auto").
struct WhereYouMetSection: View {
    @Binding var draft: CaptureDraft
    let location: LocationContextProvider

    @State private var settingsAlert: SettingsAlert?

    var body: some View {
        Section {
            LabeledContent("Event") {
                TextField("Event", text: $draft.eventName, prompt: Text("None"))
                    .multilineTextAlignment(.trailing)
                    .submitLabel(.next)
            }
            LabeledContent("Place") {
                TextField("Place", text: $draft.place, prompt: Text("Where?"))
                    .multilineTextAlignment(.trailing)
                    .textContentType(.location)
                    .submitLabel(.next)
            }
            LabeledContent("City") {
                TextField("City", text: $draft.city, prompt: Text("City"))
                    .multilineTextAlignment(.trailing)
                    .textContentType(.addressCity)
                    .submitLabel(.done)
            }
            DatePicker("Time", selection: $draft.metAt, in: ...Date.now.addingTimeInterval(60),
                       displayedComponents: [.date, .hourAndMinute])
            if showsLocationRow {
                CurrentLocationRow(isLocating: location.isLocating, action: useCurrentLocation)
            }
        } header: {
            WhereYouMetHeader(isAutoFilled: draft.isAutoFilled)
        } footer: {
            if draft.isAutoFilled {
                Text("Filled in automatically. Tap a field to change it.")
            }
        }
        .task { await autoFillIfAuthorized() }
        .settingsAlert($settingsAlert)
    }

    private var showsLocationRow: Bool {
        draft.place.trimmed.isEmpty && (location.isLocating || !location.isAuthorized || location.status == .failed)
    }

    /// Silent auto-fill only when the user already granted location access.
    private func autoFillIfAuthorized() async {
        location.refreshAuthorization()
        guard location.isAuthorized, draft.place.trimmed.isEmpty else { return }
        await fill()
    }

    private func useCurrentLocation() {
        location.refreshAuthorization()
        if location.isDenied {
            settingsAlert = .locationOff
            return
        }
        Task { await fill() }
    }

    private func fill() async {
        guard let suggestion = await location.resolveCurrentPlace() else {
            if location.status == .denied { settingsAlert = .locationOff }
            return
        }
        // The user may have typed meanwhile — never overwrite their input.
        guard draft.place.trimmed.isEmpty else { return }
        draft.place = suggestion.place
        if draft.city.trimmed.isEmpty { draft.city = suggestion.city }
        draft.markAutoFilled()
    }
}

private struct WhereYouMetHeader: View {
    let isAutoFilled: Bool

    var body: some View {
        HStack {
            Text("Where You Met")
            Spacer()
            if isAutoFilled {
                Label("Auto", systemImage: "wand.and.stars")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Filled in automatically")
            }
        }
    }
}

private struct CurrentLocationRow: View {
    let isLocating: Bool
    let action: () -> Void

    var body: some View {
        if isLocating {
            HStack(spacing: 12) {
                ProgressView()
                Text("Finding where you are…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Button("Use Current Location", systemImage: "location.fill", action: action)
        }
    }
}
