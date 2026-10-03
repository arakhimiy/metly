import Foundation
import MetlyCore
import MetlyNetworking
import Testing
@testable import FeatureConnect

struct NearbyPeerListTests {
    private let kamilaID = UUID()
    private let sardorID = UUID()
    private let bekzodID = UUID()

    private func dto(_ token: String, _ userID: UUID, _ name: String, title: String = "CTO") -> NearbyPeerDTO {
        NearbyPeerDTO(token: token, userID: userID, fullName: name, jobTitle: title, company: "Payme")
    }

    @Test func sameUserUnderTwoTokensIsOneRow() {
        var list = NearbyPeerList()
        list.merge([dto("k1", kamilaID, "Kamila Yusupova")], blocked: [])
        list.merge([dto("k2", kamilaID, "Kamila Yusupova", title: "Head of Partnerships")], blocked: [])
        #expect(list.people.count == 1)
        #expect(list.people[0].tokens == ["k1", "k2"])
        #expect(list.people[0].token == "k2")              // newest token is the request target
        #expect(list.people[0].jobTitle == "Head of Partnerships")
        #expect(list.person(withToken: "k1")?.userID == kamilaID)
    }

    @Test func duplicateTokenInOneBatchIsMergedOnce() {
        var list = NearbyPeerList()
        list.merge([dto("k1", kamilaID, "Kamila"), dto("k1", kamilaID, "Kamila")], blocked: [])
        #expect(list.people.count == 1)
        #expect(list.people[0].tokens == ["k1"])
    }

    @Test func blockedPeopleNeverAppear() {
        var list = NearbyPeerList()
        list.merge([dto("k1", kamilaID, "Kamila"), dto("s1", sardorID, "Sardor")], blocked: [sardorID])
        #expect(list.people.map(\.userID) == [kamilaID])
    }

    @Test func blockingLaterRemovesThem() {
        var list = NearbyPeerList()
        list.merge([dto("k1", kamilaID, "Kamila"), dto("s1", sardorID, "Sardor")], blocked: [])
        list.removeBlocked([kamilaID])
        #expect(list.people.map(\.userID) == [sardorID])
    }

    @Test func ownTokenAndAccountAreSkipped() {
        let me = UUID()
        var list = NearbyPeerList()
        list.merge([dto("mine", UUID(), "Me"), dto("other", me, "Me Again"), dto("k1", kamilaID, "Kamila")],
                   blocked: [], ownToken: "mine", ownUserID: me)
        #expect(list.people.map(\.userID) == [kamilaID])
    }

    @Test func keepsFirstSeenOrder() {
        var list = NearbyPeerList()
        list.merge([dto("s1", sardorID, "Sardor")], blocked: [])
        list.merge([dto("k1", kamilaID, "Kamila"), dto("b1", bekzodID, "Bekzod")], blocked: [])
        list.merge([dto("s2", sardorID, "Sardor")], blocked: [])
        #expect(list.people.map(\.userID) == [sardorID, kamilaID, bekzodID])
    }

    @Test func personLeavesWhenTheirLastTokenIsLost() {
        var list = NearbyPeerList()
        list.merge([dto("k1", kamilaID, "Kamila"), dto("k2", kamilaID, "Kamila")], blocked: [])
        let removed1 = list.remove(token: "k1")
        #expect(removed1 == nil)
        #expect(list.people.count == 1)
        let removed2 = list.remove(token: "k2")
        #expect(removed2?.userID == kamilaID)
        #expect(list.isEmpty)
        let removed3 = list.remove(token: "unknown")
        #expect(removed3 == nil)
    }

    @Test func personDerivedValues() {
        let person = NearbyPerson(userID: kamilaID, tokens: ["k1"], fullName: "Kamila Yusupova",
                                  jobTitle: "Head of Partnerships", company: "Uzum")
        #expect(person.firstName == "Kamila")
        #expect(person.role == "Head of Partnerships · Uzum")
        #expect(person.asPeer == ConnectMachine.Peer(userID: kamilaID, firstName: "Kamila", token: "k1"))
        #expect(NearbyPerson(userID: kamilaID, tokens: [], fullName: "Kamila").role.isEmpty)
    }
}
