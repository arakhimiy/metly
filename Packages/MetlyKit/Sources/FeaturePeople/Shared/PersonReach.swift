import Foundation
import UIKit
import MetlyCapture
import MetlyCore
import MetlyData

/// What CONNECTION_DETAIL's Message and Call actions can do for a person.
struct PersonReach: Equatable {
    enum Message: Equatable {
        /// Telegram by username, or by phone number when no username is saved.
        case telegram(TelegramTarget)
        /// WhatsApp (`wa.me/<digits>`): their saved WhatsApp, or — with WhatsApp on this iPhone — their mobile
        /// number (`byPhone`; WhatsApp says so itself if the number isn't on WhatsApp).
        case whatsApp(URL, byPhone: Bool)
        /// No messenger: Messages to their (mobile) number.
        case sms(URL)
        case none
    }

    /// What Message opens with one tap: Telegram by username › WhatsApp › Telegram by phone › Messages.
    let message: Message
    /// Every way to message them, in that order (Messages only without a Telegram username); more than
    /// one → Message opens a menu.
    let choices: [Message]
    /// Their WhatsApp chat: the saved WhatsApp, else their mobile number when WhatsApp is on this iPhone.
    let whatsAppURL: URL?
    /// Every number Call can dial, primary first ("Mobile · +998…", "Work · …").
    let callablePhones: [LabeledPhone]
    /// Messages to the mobile number (else the first one that works), offered next to Telegram by phone.
    let smsURL: URL?

    /// - Parameter hasWhatsApp: WhatsApp is installed here (decides WhatsApp by phone number).
    init(_ person: Connection, hasWhatsApp: Bool = MessengerApps.hasWhatsApp) {
        callablePhones = person.allPhones.filter { ContactLinks.call($0.value) != nil }
        smsURL = person.phonesForMessaging.lazy.compactMap { ContactLinks.sms($0.value) }.first
        let savedWhatsApp = person.contacts.entries(of: .whatsapp).lazy.compactMap { ContactLinks.whatsApp($0.value) }.first
        let whatsAppByPhone = hasWhatsApp
            ? person.phonesForMessaging.lazy.compactMap { TelegramPhone.digits(from: $0.value) }.first
                .flatMap { URL(string: "https://wa.me/\($0)") }
            : nil
        whatsAppURL = savedWhatsApp ?? whatsAppByPhone
        let telegram = person.telegramTarget
        var choices: [Message] = []
        if let telegram, !telegram.isByPhone { choices.append(.telegram(telegram)) }
        if let savedWhatsApp { choices.append(.whatsApp(savedWhatsApp, byPhone: false)) }
        if let telegram, telegram.isByPhone { choices.append(.telegram(telegram)) }
        if savedWhatsApp == nil, let whatsAppByPhone { choices.append(.whatsApp(whatsAppByPhone, byPhone: true)) }
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

/// Messenger apps on this iPhone (their URL schemes are listed in Info.plist `LSApplicationQueriesSchemes`).
@MainActor
enum MessengerApps {
    static var hasWhatsApp: Bool {
        URL(string: "whatsapp://").map(UIApplication.shared.canOpenURL) ?? false
    }
}
