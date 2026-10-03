/// Which sections `ContextCaptureForm` shows.
public struct CaptureSections: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Event, place, city (auto-filled) and time.
    public static let whereYouMet = CaptureSections(rawValue: 1 << 0)
    /// Private note with voice dictation.
    public static let note = CaptureSections(rawValue: 1 << 1)
    /// Preset and custom tag chips.
    public static let tags = CaptureSections(rawValue: 1 << 2)
    /// Follow-up quick picks + time, to-do and channel.
    public static let followUp = CaptureSections(rawValue: 1 << 3)

    public static let all: CaptureSections = [.whereYouMet, .note, .tags, .followUp]
}
