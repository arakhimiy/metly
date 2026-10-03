import MetlyCore

// MARK: - MetlyCapture — shared "Context Capture" block (SPEC §3.14)
//
// Used by CONNECTED (Connect), ADD_CONTEXT + JUST_MET (People), PAPER_REVIEW + SCANNED_CARD (Scan)
// and EVENT flows. Owned by the People & Context agent.
//
// ┌──────────────────────────────────────────────────────────────────────────────────────────┐
// │ 1. Build a draft                                                                         │
// │    CaptureDraft.capture(for: connection, in: modelContext)   // CONNECTED / PAPER / ADD   │
// │    CaptureDraft.capture(for: nil, in: modelContext)          // JUST_MET (no person yet)  │
// │    CaptureDraft.newMeeting(with: connection, in: modelContext) // met a known person again│
// │    CaptureDraft(editing: connection)                          // edit existing context    │
// │                                                                                          │
// │ 2. Show it inside your Form (it emits Sections)                                          │
// │    Form {                                                                                │
// │        ContextCaptureForm(draft: $draft)                       // all four sections       │
// │        ContextCaptureForm(draft: $draft, sections: [.whereYouMet, .note, .followUp])      │
// │    }                                                                                     │
// │    Needs `AppServices` + `AppRouter` + a modelContext in the environment.                │
// │    Handles location auto-fill (When-In-Use, requested in context), voice dictation       │
// │    (on-device Speech, mic permission in context), tag chips, follow-up quick picks and   │
// │    the Free-plan follow-up limit alert (→ paywall).                                      │
// │                                                                                          │
// │ 3. Commit on Save                                                                        │
// │    modelContext.insert(connection)                    // if it is new                    │
// │    let result = draft.apply(to: connection, in: modelContext,                            │
// │                             limits: services.entitlements.limits)                        │
// │    router.showToast(result.toastMessage(otherwise: "Connection Saved"))                  │
// │    // → "Saved · Reminder Set" when a reminder was scheduled                             │
// └──────────────────────────────────────────────────────────────────────────────────────────┘
//
// Other public helpers:
//  • FollowUpPolicy — openCount(in:), canSchedule(hasOpenReminder:in:limits:),
//    preferredChannel(for:), schedule(_:for:in:limits:) (one open reminder per person).
//  • FollowUpQuickPick / FollowUpDraft — Tomorrow · In 3 Days · Next Week · Pick a Date… (10:00 local, min today).
//  • .followUpLimitAlert(isPresented:openCount:) — ALERT_FU_LIMIT with Upgrade → paywall(.followUpLimit).
//  • .settingsAlert($alert) + SettingsAlert.microphoneOff / .speechOff / .locationOff — "Open Settings" alerts.
//  • ContactDraft + .contactSaver(item:onCompletion:) — CNContactViewController(forNewContact:), no permission needed.
//  • ContactLinks — Telegram (tg:// + https fallback), tel:, sms:, mailto:, website and LinkedIn URLs.
//  • LocationContextProvider, VoiceNoteRecognizer — @Observable helpers if you need them directly.
//  • CaptureChip, FollowUpQuickPicker, TagFlowLayout — small reusable controls.

/// Constants shared by every capture surface.
public enum MetlyCapture {
    /// Preset tag chips (SPEC §3.14). Custom tags are added next to them.
    public static let presetTags = ["Investor", "Client", "Hiring", "Partner", "Friend"]

    /// Default reminder title when the user leaves "To Do" empty.
    public static let defaultFollowUpTitle = "Follow up"

    /// Default reminder time (local).
    public static let defaultFollowUpHour = 10
}
