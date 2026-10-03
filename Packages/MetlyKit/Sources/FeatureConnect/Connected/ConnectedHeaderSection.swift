import MetlyCore
import MetlyData
import SwiftUI

/// "You're Connected" header: both cards overlapping, "You and {first} are connected…",
/// "You shared your {card} card with {first}." (SPEC §2.5.27).
struct ConnectedHeaderSection: View {
    let connection: Connection
    let myCard: Card?
    let profile: Profile?

    var body: some View {
        Section {
            VStack(spacing: 14) {
                OverlappingCards(mine: mine, theirs: theirs, accessibilityLabel: cardsDescription)
                VStack(spacing: 6) {
                    Text(ConnectCopy.connectedTitle)
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(ConnectCopy.connectedMessage(firstName))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if let myCard {
                        Text(ConnectCopy.sharedCard(myCard.name, with: firstName))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
    }

    private var firstName: String { ConnectCopy.firstName(of: connection.fullName) }

    private var mine: OverlappingCards.Face? {
        guard let myCard else { return nil }
        return .init(design: myCard.design, content: myCard.faceContent(profile: profile, audience: .connections))
    }

    private var theirs: OverlappingCards.Face {
        let snapshot = connection.theirCard ?? CardSnapshot(
            cardName: "Card", design: CardDesign(template: .minimal, palette: .snow, appearance: .light),
            fullName: connection.fullName, jobTitle: connection.jobTitle, company: connection.company,
            fields: connection.availableFields)
        return .init(design: snapshot.design, content: snapshot.faceContent)
    }

    private var cardsDescription: String {
        if let myCard {
            return "Your \(myCard.name) card and \(firstName)’s card"
        }
        return "\(firstName)’s card"
    }
}
