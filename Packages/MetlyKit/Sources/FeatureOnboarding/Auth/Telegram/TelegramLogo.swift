import SwiftUI

/// Telegram's mark for the sign-in button: a white paper plane on Telegram's blue disc
/// (Telegram blue, #2AABEE → #229ED9).
struct TelegramLogo: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(red: 0.165, green: 0.671, blue: 0.933),
                                          Color(red: 0.133, green: 0.620, blue: 0.851)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                GeometryReader { proxy in
                    Image(systemName: "paperplane.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .frame(width: proxy.size.width * 0.5, height: proxy.size.height * 0.5)
                        .offset(x: -proxy.size.width * 0.03, y: proxy.size.height * 0.02)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .accessibilityHidden(true)   // the button title already says "Telegram"
    }
}

#Preview {
    TelegramLogo().frame(width: 44, height: 44).padding()
}
