import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct PeopleView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("People", specID: "PEOPLE")
    }
}
public struct ConnectionDetailView: View {
    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        FeaturePlaceholder("Connection", specID: "CONNECTION_DETAIL")
    }
}
public struct AddContextSheet: View {
    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        FeaturePlaceholder("Add Context", specID: "ADD_CONTEXT")
    }
}
public struct JustMetSheet: View {
    public let cardID: UUID?

    public init(cardID: UUID?) {
        self.cardID = cardID
    }

    public var body: some View {
        FeaturePlaceholder("Who did you just meet?", specID: "JUST_MET")
    }
}
public struct BlockedPeopleView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Blocked People", specID: "SETTINGS_BLOCKED")
    }
}
