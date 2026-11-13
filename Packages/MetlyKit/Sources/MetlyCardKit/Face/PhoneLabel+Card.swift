import MetlyCore

public extension PhoneLabel {
    /// "Work phone" — what VoiceOver says before a number, and how a number is named in a sentence.
    var phoneNumberTitle: String {
        switch self {
        case .mobile: String(localized: "Mobile phone", bundle: .appStrings)
        case .work: String(localized: "Work phone", bundle: .appStrings)
        case .home: String(localized: "Home phone", bundle: .appStrings)
        case .other: String(localized: "Other phone", bundle: .appStrings)
        }
    }

    /// vCard 3.0 `TEL` parameters (RFC 2426 types, understood by Contacts and Android).
    var vCardType: String {
        switch self {
        case .mobile: "TYPE=CELL"
        case .work: "TYPE=WORK,VOICE"
        case .home: "TYPE=HOME,VOICE"
        case .other: "TYPE=VOICE"
        }
    }
}

extension PhoneLabel {
    /// Terminal template key when the card shows several numbers (`tel`, `tel.work`…).
    var terminalKey: String {
        switch self {
        case .mobile: "tel"
        case .work: "tel.work"
        case .home: "tel.home"
        case .other: "tel.other"
        }
    }
}
