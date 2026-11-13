import Foundation
import Network

/// iOS has no API to read the Local Network permission. Browsing our own Bonjour type with
/// `NWBrowser` reveals it: a denied app waits with `kDNSServiceErr_PolicyDenied`, an allowed one
/// becomes ready. The watcher keeps running, so turning access back on in Settings is noticed too.
nonisolated enum LocalNetworkWatcher {
    /// `kDNSServiceErr_PolicyDenied` from dns_sd.h.
    static let policyDeniedCode: Int32 = -65570

    /// Starts watching; `report(true)` when access is denied, `report(false)` when browsing works.
    static func start(serviceType: String, report: @escaping @Sendable (_ denied: Bool) -> Void) -> NWBrowser {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { @Sendable state in
            switch state {
            case .waiting(let error), .failed(let error):
                if isPolicyDenied(error) { report(true) }
            case .ready:
                report(false)
            default:
                break
            }
        }
        browser.start(queue: DispatchQueue(label: "app.nameshake.ios.connect.local-network"))
        return browser
    }

    static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error { return code == policyDeniedCode }
        return false
    }

    /// MultipeerConnectivity surfaces the same denial through NetService errors.
    static func isPolicyDenied(code: Int) -> Bool {
        code == Int(policyDeniedCode)
    }
}
