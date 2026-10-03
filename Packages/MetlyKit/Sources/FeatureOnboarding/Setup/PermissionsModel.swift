import Observation

/// State of SETUP_PERMISSIONS rows.
@Observable
final class PermissionsModel {
    private(set) var statuses: [PermissionKind: PermissionStatus] = [:]
    private(set) var requesting: PermissionKind?
    @ObservationIgnored private let provider: any PermissionProviding

    init(provider: any PermissionProviding) {
        self.provider = provider
    }

    func status(of kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    var grantedCount: Int {
        statuses.values.count { $0 == .granted }
    }

    /// Re-reads every status (on appear and when returning from Settings).
    func refresh() async {
        for kind in PermissionKind.allCases where kind != requesting {
            let status = await provider.status(of: kind)
            if kind != requesting {
                statuses[kind] = status
            }
        }
    }

    func request(_ kind: PermissionKind) async {
        guard requesting == nil else { return }
        requesting = kind
        defer { requesting = nil }
        statuses[kind] = await provider.request(kind)
    }
}
