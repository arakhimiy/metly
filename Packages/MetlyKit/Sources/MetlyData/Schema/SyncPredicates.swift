import Foundation
import SwiftData

// Concrete #Predicates for SyncedRecord. Each model needs its own copy: SwiftData resolves a key path
// written against a generic `Model: SyncedRecord` through the protocol witness, which works in Debug
// but traps in Release ("Tanishly crashes 2–3 s after sign-in", TestFlight 1.0 (1)).

extension Profile {
    public static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<Profile> {
        equal ? #Predicate { $0.syncStateRaw == raw } : #Predicate { $0.syncStateRaw != raw }
    }

    public static func idPredicate(_ id: UUID) -> Predicate<Profile> {
        #Predicate { $0.id == id }
    }
}

extension Card {
    public static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<Card> {
        equal ? #Predicate { $0.syncStateRaw == raw } : #Predicate { $0.syncStateRaw != raw }
    }

    public static func idPredicate(_ id: UUID) -> Predicate<Card> {
        #Predicate { $0.id == id }
    }
}

extension Connection {
    public static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<Connection> {
        equal ? #Predicate { $0.syncStateRaw == raw } : #Predicate { $0.syncStateRaw != raw }
    }

    public static func idPredicate(_ id: UUID) -> Predicate<Connection> {
        #Predicate { $0.id == id }
    }
}

extension FollowUp {
    public static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<FollowUp> {
        equal ? #Predicate { $0.syncStateRaw == raw } : #Predicate { $0.syncStateRaw != raw }
    }

    public static func idPredicate(_ id: UUID) -> Predicate<FollowUp> {
        #Predicate { $0.id == id }
    }
}

extension Event {
    public static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<Event> {
        equal ? #Predicate { $0.syncStateRaw == raw } : #Predicate { $0.syncStateRaw != raw }
    }

    public static func idPredicate(_ id: UUID) -> Predicate<Event> {
        #Predicate { $0.id == id }
    }
}

extension ConnectRequest {
    public static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<ConnectRequest> {
        equal ? #Predicate { $0.syncStateRaw == raw } : #Predicate { $0.syncStateRaw != raw }
    }

    public static func idPredicate(_ id: UUID) -> Predicate<ConnectRequest> {
        #Predicate { $0.id == id }
    }
}
