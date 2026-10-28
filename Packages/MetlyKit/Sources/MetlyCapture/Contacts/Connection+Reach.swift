import Foundation
import MetlyCore
import MetlyData

public extension Connection {
    /// Every phone with Mobile-labelled numbers first (each group in saved order) — the order messengers try.
    var phonesForMessaging: [LabeledPhone] {
        let phones = allPhones
        return phones.filter { $0.label == .mobile } + phones.filter { $0.label != .mobile }
    }

    /// Telegram by the saved username, else by the first phone Telegram can use (mobile numbers first).
    /// Nil when neither exists — then Telegram isn't offered.
    var telegramTarget: TelegramTarget? {
        TelegramTarget(username: telegram, phones: phonesForMessaging.map(\.value))
    }
}

public extension LabeledPhone {
    /// "Mobile · +998 90 123 45 67" — call menus and pickers.
    var labeledValue: String { "\(label.title) · \(value)" }
}
