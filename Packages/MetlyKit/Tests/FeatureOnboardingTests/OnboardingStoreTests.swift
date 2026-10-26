import Foundation
import Testing
import UIKit
@testable import FeatureOnboarding

@Suite("Onboarding store & helpers")
struct OnboardingStoreTests {
    private func makeStore() throws -> OnboardingStore {
        let suite = "test.onboarding.\(UUID().uuidString)"
        return OnboardingStore(defaults: try #require(UserDefaults(suiteName: suite)))
    }

    @Test func persistsAndClearsPrefill() throws {
        let store = try makeStore()
        #expect(store.setupPrefill == nil)
        let prefill = SetupPrefill(fullName: "Aziza Karimova", email: "aziza@icloud.com", provider: .google)
        store.setupPrefill = prefill
        #expect(store.setupPrefill == prefill)
        store.setupPrefill = nil
        #expect(store.setupPrefill == nil)
    }

    @Test func persistsPendingInvite() throws {
        let store = try makeStore()
        store.pendingInviteSlug = "jasur-p4y1"
        #expect(store.pendingInviteSlug == "jasur-p4y1")
        store.pendingInviteSlug = ""
        #expect(store.pendingInviteSlug == nil)
        store.pendingInviteSlug = "x"
        store.pendingInviteSlug = nil
        #expect(store.pendingInviteSlug == nil)
    }

    @Test func persistsLocalNetworkAccess() throws {
        let store = try makeStore()
        #expect(store.localNetworkAccess == nil)
        store.localNetworkAccess = .denied
        #expect(store.localNetworkAccess == .denied)
    }

    @Test func prefillHasValuesOnlyWithNameOrEmail() {
        #expect(!SetupPrefill(fullName: nil, email: "", provider: .apple).hasValues)
        #expect(SetupPrefill(fullName: "A", email: nil, provider: .apple).hasValues)
        #expect(SetupPrefill(fullName: nil, email: "a@b.uz", provider: .google).hasValues)
    }

    @Test func invitePayloadPointsAtPublicCard() {
        let payload = OnboardingCoordinator.invitePayload(slug: "jasur-p4y1")
        #expect(payload.slug == "jasur-p4y1")
        #expect(payload.url?.absoluteString == "https://tanishly.app/c/jasur-p4y1")
        #expect(payload.vCard == nil)
    }

    @Test func downscalesLargePhotos() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let original = try #require(image.pngData())
        let jpeg = try #require(await ImageDownscaler.jpegData(from: original, maxPixelSize: 800))
        let result = try #require(UIImage(data: jpeg))
        #expect(max(result.size.width, result.size.height) == 800)
        #expect(jpeg.count < original.count)
    }

    @Test func downscalerRejectsGarbage() async {
        #expect(await ImageDownscaler.jpegData(from: Data("not an image".utf8)) == nil)
    }
}
