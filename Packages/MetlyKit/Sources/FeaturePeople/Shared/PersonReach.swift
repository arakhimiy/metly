import Foundation
import MetlyCapture
import MetlyCore
import MetlyData

/// What CONNECTION_DETAIL's Message and Call actions can do for a person.
struct PersonReach: Equatable {
    enum Message: Equatable {
        /// Telegram by username, or by phone number when no username is saved.
        case telegram(TelegramTarget)
        /// Their saved WhatsApp (`wa.me/<digits>`).
        case whatsApp(URL)
        /// No messenger: Messages to their (mobile) number.
        case sms(URL)
        case none
    }

    /// What Message opens with one tap: Telegram by username › WhatsApp › Telegram by phone › Messages.
    let message: Message
    /// Every way to message them, in that order (Messages only without a Telegram username); more than
    /// one → Message opens a menu.
    let choices: [Message]
    /// Their saved WhatsApp, when there is one.
    let whatsAppURL: URL?
    /// Every number Call can dial, primary first ("Mobile · +998…", "Work · …").
    let callablePhones: [LabeledPhone]
    /// Messages to the mobile number (else the first one that works), offered next to Telegram by phone.
    let smsURL: URL?

    init(_ person: Connection) {
        callablePhones = person.allPhones.filter { ContactLinks.call($0.value) != nil }
        smsURL = person.phonesForMessaging.lazy.compactMap { ContactLinks.sms($0.value) }.first
        whatsAppURL = person.contacts.entries(of: .whatsapp).lazy.compactMap { ContactLinks.whatsApp($0.value) }.first
        let telegram = person.telegramTarget
        var choices: [Message] = []
        if let telegram, !telegram.isByPhone { choices.append(.telegram(telegram)) }
        if let whatsAppURL { choices.append(.whatsApp(whatsAppURL)) }
        if let telegram, telegram.isByPhone { choices.append(.telegram(telegram)) }
        // A saved Telegram username is how they want to be messaged: no Messages next to it (as before).
        if let smsURL, telegram?.isByPhone ?? true { choices.append(.sms(smsURL)) }
        self.choices = choices
        message = choices.first ?? .none
    }

    /// Message opens Telegram by phone number (the UI then says so).
    var messagesTelegramByPhone: Bool {
        if case .telegram(let target) = message { return target.isByPhone }
        return false
    }
}
