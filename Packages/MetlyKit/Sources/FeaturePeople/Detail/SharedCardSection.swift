import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI

/// Their card face + "You shared your {card} card with {first}."
struct SharedCardSection: View {
    let person: Connection
    let sharedCardName: String?

    var body: some View {
        if let card = person.theirCard {
            Section {
                CardFaceView(design: card.design, content: card.faceContent)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                Text("Their \(card.cardName) Card")
            } footer: {
                footer
            }
        } else if sharedCardName != nil {
            Section {
            } footer: {
                footer
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let sharedCardName {
            Text("You shared your \(sharedCardName) card with \(PersonName.first(person.fullName)).")
        }
    }
}
