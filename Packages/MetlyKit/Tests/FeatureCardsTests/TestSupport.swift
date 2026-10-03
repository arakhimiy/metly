import Foundation
import MetlyCore
import MetlyData
import SwiftData

@MainActor
func makeContext() throws -> ModelContext {
    let container = try MetlyModelContainer.make(inMemory: true)
    retainedContainers.append(container)
    return ModelContext(container)
}

/// Keeps in-memory containers alive for the duration of a test.
@MainActor private var retainedContainers: [ModelContainer] = []

/// Aziza's profile with one field per privacy level (+ an empty LinkedIn).
@MainActor
@discardableResult
func insertProfile(in context: ModelContext) -> Profile {
    let profile = Profile(fullName: "Aziza Karimova", jobTitle: "Product Designer", company: "Tezkor",
                          contactFields: [
                              ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private),
                              ContactField(kind: .email, value: "aziza@tezkor.uz", privacy: .connections),
                              ContactField(kind: .telegram, value: "@aziza.k", privacy: .public),
                              ContactField(kind: .website, value: "aziza.design", privacy: .public),
                              ContactField(kind: .linkedin, value: "", privacy: .public),
                          ],
                          isSetupComplete: true)
    profile.syncState = .synced
    context.insert(profile)
    return profile
}

/// A synced (clean) card, so tests can tell whether an operation marked it dirty.
@MainActor
@discardableResult
func insertCard(_ name: String, sortOrder: Int, slug: String = "", design: CardDesign = CardDesign(),
                in context: ModelContext) -> Card {
    let card = Card(name: name, slug: slug, sortOrder: sortOrder, design: design)
    card.syncState = .synced
    context.insert(card)
    return card
}

/// Isolated defaults so preference writes never leak between tests.
@MainActor
func makePreferences() -> AppPreferences {
    let suite = "FeatureCardsTests.\(UUID().uuidString)"
    return AppPreferences(store: UserDefaults(suiteName: suite) ?? .standard)
}
