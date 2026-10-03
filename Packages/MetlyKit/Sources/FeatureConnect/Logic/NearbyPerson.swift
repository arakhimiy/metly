import Foundation
import MetlyCore
import MetlyNetworking

/// Someone with CONNECT open nearby, resolved by the server from their opaque discovery token.
nonisolated struct NearbyPerson: Identifiable, Equatable, Sendable {
    let userID: UUID
    /// Every discovery token currently seen for this person (a device restarting Connect gets a new one).
    var tokens: [String]
    var fullName: String
    var jobTitle: String
    var company: String
    var avatarURL: URL?
    /// The card they're sharing (INCOMING / previews).
    var card: CardSnapshot?

    var id: UUID { userID }

    init(userID: UUID, tokens: [String], fullName: String, jobTitle: String = "", company: String = "",
         avatarURL: URL? = nil, card: CardSnapshot? = nil) {
        self.userID = userID
        self.tokens = tokens
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.avatarURL = avatarURL
        self.card = card
    }

    init(_ dto: NearbyPeerDTO) {
        self.init(userID: dto.userID, tokens: [dto.token], fullName: dto.fullName, jobTitle: dto.jobTitle,
                  company: dto.company, avatarURL: dto.avatarURL, card: dto.card)
    }

    /// The token to address requests to (the most recently seen one).
    var token: String { tokens.last ?? "" }

    var firstName: String { ConnectCopy.firstName(of: fullName) }

    /// "{title} · {company}".
    var role: String { [jobTitle, company].filter { !$0.isEmpty }.joined(separator: " · ") }

    var asPeer: ConnectMachine.Peer {
        ConnectMachine.Peer(userID: userID, firstName: firstName, token: token)
    }
}
