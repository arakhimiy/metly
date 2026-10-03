import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import FeatureConnect

struct ConnectMachineTests {
    private let kamila = ConnectMachine.Peer(userID: UUID(), firstName: "Kamila", token: "tok-kamila")
    private let nodira = ConnectMachine.Peer(userID: UUID(), firstName: "Nodira", token: "tok-nodira")
    private let connectionID = UUID()

    private func discovering() -> ConnectMachine {
        var machine = ConnectMachine()
        machine.send(.discoveryStarted)
        return machine
    }

    private func waiting(on peer: ConnectMachine.Peer) -> ConnectMachine {
        var machine = discovering()
        machine.send(.connectTapped(peer, method: .nearby))
        return machine
    }

    private func incoming(from name: String = "Bekzod") -> ConnectMachine.Incoming {
        ConnectMachine.Incoming(requestID: UUID(), peerUserID: UUID(), firstName: name)
    }

    // MARK: Discovery

    @Test func startsIdleAndDiscovers() {
        var machine = ConnectMachine()
        #expect(machine.phase == .idle)
        #expect(!machine.canSendRequest)
        machine.send(.discoveryStarted)
        #expect(machine.phase == .discovering)
        #expect(machine.canSendRequest)
        machine.send(.discoveryStopped)
        #expect(machine.phase == .idle)
    }

    @Test func connectIsIgnoredBeforeDiscovery() {
        var machine = ConnectMachine()
        let effects = machine.send(.connectTapped(kamila, method: .nearby))
        #expect(effects.isEmpty)
        #expect(machine.phase == .idle)
    }

    // MARK: Outgoing

    @Test func connectSendsOneRequestAndWaits() {
        var machine = discovering()
        let effects = machine.send(.connectTapped(kamila, method: .nearby))
        #expect(effects == [.sendRequest(kamila, method: .nearby)])
        #expect(machine.waitingPeer == kamila)
        #expect(!machine.canSendRequest)
    }

    @Test func onlyOneOutstandingRequest() {
        var machine = waiting(on: kamila)
        let effects = machine.send(.connectTapped(nodira, method: .nearby))
        #expect(effects.isEmpty)
        #expect(machine.waitingPeer == kamila)
    }

    @Test func acceptedOpensConnected() {
        var machine = waiting(on: kamila)
        let effects = machine.send(.outcome(.accepted(connectionID: connectionID), peerUserID: kamila.userID))
        #expect(effects == [.openConnected(connectionID: connectionID)])
        #expect(machine.phase == .connected(connectionID: connectionID))
        #expect(machine.connectedID == connectionID)
    }

    @Test func noResponseShowsNoticeAndKeepsBrowsing() {
        var machine = waiting(on: nodira)
        let effects = machine.send(.outcome(.noResponse, peerUserID: nodira.userID))
        #expect(effects.isEmpty)
        #expect(machine.phase == .discovering)
        #expect(machine.notice == .noResponse(firstName: "Nodira"))
        #expect(ConnectCopy.noResponse("Nodira") == "Nodira didn’t respond. Try again or show your QR.")
    }

    @Test func cancelledOutcomeReturnsQuietly() {
        var machine = waiting(on: kamila)
        machine.send(.outcome(.cancelled, peerUserID: kamila.userID))
        #expect(machine.phase == .discovering)
        #expect(machine.notice == nil)
    }

    @Test func cancelWithdrawsTheRequest() {
        var machine = waiting(on: kamila)
        let effects = machine.send(.cancelTapped)
        #expect(effects == [.withdrawRequest])
        #expect(machine.phase == .discovering)
        // The cancelled wait reporting back changes nothing.
        let effects1 = machine.send(.outcome(.cancelled, peerUserID: kamila.userID))
        #expect(effects1.isEmpty)
        #expect(machine.phase == .discovering)
    }

    @Test func outcomeForAnotherPeerIsIgnored() {
        var machine = waiting(on: kamila)
        machine.send(.outcome(.noResponse, peerUserID: nodira.userID))
        #expect(machine.waitingPeer == kamila)
        #expect(machine.notice == nil)
    }

    @Test func sendFailureShowsMessage() {
        var machine = waiting(on: kamila)
        machine.send(.requestFailed(message: "You’re offline."))
        #expect(machine.phase == .discovering)
        #expect(machine.notice == .failed(message: "You’re offline."))
    }

    @Test func newRequestClearsTheNotice() {
        var machine = waiting(on: nodira)
        machine.send(.outcome(.noResponse, peerUserID: nodira.userID))
        machine.send(.connectTapped(kamila, method: .nearby))
        #expect(machine.notice == nil)
        machine.send(.noticeDismissed)
        #expect(machine.notice == nil)
    }

    @Test func requestEndingAfterDiscoveryStoppedRestsIdle() {
        var machine = waiting(on: nodira)
        machine.send(.discoveryStopped)
        #expect(machine.waitingPeer == nodira)   // still waiting
        machine.send(.outcome(.noResponse, peerUserID: nodira.userID))
        #expect(machine.phase == .idle)
    }

    // MARK: Incoming

    @Test func incomingWhileDiscoveringAccepts() {
        var machine = discovering()
        let request = incoming()
        machine.send(.incomingReceived(request))
        #expect(machine.incoming == request)
        let effects2 = machine.send(.acceptTapped)
        #expect(effects2 == [.accept(requestID: request.requestID)])
        #expect(machine.isAccepting)
        let effects3 = machine.send(.acceptSucceeded(connectionID: connectionID))
        #expect(effects3 == [.openConnected(connectionID: connectionID)])
        #expect(machine.phase == .connected(connectionID: connectionID))
        #expect(machine.incoming == nil)
    }

    @Test func incomingDuringWaitingWithdrawsOutgoingOnAccept() {
        var machine = waiting(on: kamila)
        let request = incoming()
        machine.send(.incomingReceived(request))
        #expect(machine.waitingPeer == kamila)   // still waiting underneath the sheet
        #expect(machine.incoming == request)

        let effects = machine.send(.acceptTapped)
        #expect(effects == [.withdrawRequest, .accept(requestID: request.requestID)])
        #expect(machine.phase == .accepting(requestID: request.requestID))

        // The withdrawn wait reports "cancelled" — ignored while accepting.
        let effects4 = machine.send(.outcome(.cancelled, peerUserID: kamila.userID))
        #expect(effects4.isEmpty)
        #expect(machine.isAccepting)

        machine.send(.acceptSucceeded(connectionID: connectionID))
        #expect(machine.connectedID == connectionID)
    }

    @Test func declineDuringWaitingKeepsWaiting() {
        var machine = waiting(on: kamila)
        let request = incoming()
        machine.send(.incomingReceived(request))
        let effects5 = machine.send(.declineTapped)
        #expect(effects5 == [.decline(requestID: request.requestID)])
        #expect(machine.incoming == nil)
        #expect(machine.waitingPeer == kamila)
    }

    @Test func firstIncomingStaysOnScreen() {
        var machine = discovering()
        let first = incoming(from: "Bekzod")
        machine.send(.incomingReceived(first))
        machine.send(.incomingReceived(incoming(from: "Sardor")))
        #expect(machine.incoming == first)
    }

    @Test func incomingAfterConnectedIsIgnored() {
        var machine = waiting(on: kamila)
        machine.send(.outcome(.accepted(connectionID: connectionID), peerUserID: kamila.userID))
        machine.send(.incomingReceived(incoming()))
        #expect(machine.incoming == nil)
    }

    @Test func acceptFailureShowsNotice() {
        var machine = discovering()
        machine.send(.incomingReceived(incoming()))
        machine.send(.acceptTapped)
        machine.send(.incomingDismissed)              // can't swipe away while accepting
        #expect(machine.incoming != nil)
        machine.send(.acceptFailed(message: "This request is no longer available."))
        #expect(machine.phase == .discovering)
        #expect(machine.incoming == nil)
        #expect(machine.notice == .failed(message: "This request is no longer available."))
    }

    @Test func dismissingTheSheetKeepsTheRequestForLater() {
        var machine = discovering()
        machine.send(.incomingReceived(incoming()))
        let effects6 = machine.send(.incomingDismissed)
        #expect(effects6.isEmpty)
        #expect(machine.incoming == nil)
        #expect(machine.phase == .discovering)
    }

    @Test func acceptedJustAsCancelledStillOpensConnected() {
        var machine = waiting(on: kamila)
        machine.send(.cancelTapped)
        let effects = machine.send(.outcome(.accepted(connectionID: connectionID), peerUserID: kamila.userID))
        #expect(effects == [.openConnected(connectionID: connectionID)])
    }
}
