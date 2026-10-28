import Foundation
import MetlyCapture
import MetlyCore
import MetlyData

/// What CONNECTION_DETAIL's Message and Call actions can do for a person.
struct PersonReach: Equatable {
    enum Message: Equatable {
        /// Telegram by username, or by phone number when no username is saved.
        case telegram(TelegramTarget)
        /// No Telegram: Messages to their (mobile) number.
        case sms(URL)
        case none
    }

    let message: Message
    /// Every number Call can dial, primary first ("Mobile · +998…", "Work · …").
    let callablePhones: [LabeledPhone]
    /// Messages to the mobile number (else the first one that works), offered next to Telegram by phone.
    let smsURL: URL?

    init(_ person: Connection) {
        callablePhones = person.allPhones.filter { ContactLinks.call($0.value) != nil }
        smsURL = person.phonesForMessaging.lazy.compactMap { ContactLinks.sms($0.value) }.first
        if let target = person.telegramTarget {
            message = .telegram(target)
        } else if let smsURL {
            message = .sms(smsURL)
        } else {
            message = .none
        }
    }

    /// Message opens Telegram by phone number (the UI then says so).
    var messagesTelegramByPhone: Bool {
        if case .telegram(let target) = message { return target.isByPhone }
        return false
    }
}
