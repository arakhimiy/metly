import Foundation
import MetlyCore
import UIKit

/// App/device details appended to support emails and shown in the Help footer.
nonisolated struct AppInfo: Equatable, Sendable {
    var version: String
    var build: String
    var systemVersion: String
    var deviceModel: String

    /// "1.0 (42)"
    var versionDescription: String { "\(version) (\(build))" }

    @MainActor static var current: AppInfo {
        let info = Bundle.main.infoDictionary
        return AppInfo(
            version: info?["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info?["CFBundleVersion"] as? String ?? "1",
            systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            deviceModel: hardwareIdentifier()
        )
    }

    /// e.g. "iPhone17,1" (the simulator reports the simulated model).
    @MainActor private static func hardwareIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

nonisolated enum SupportMail {
    /// `mailto:` link to support with the app version and device prefilled below the message.
    static func url(to address: String = Brand.supportEmail, appInfo: AppInfo) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(Brand.appName) Support"),
            URLQueryItem(name: "body", value: body(appInfo: appInfo)),
        ]
        return components.url
    }

    static func body(appInfo: AppInfo) -> String {
        """


        ---
        \(Brand.appName) \(appInfo.versionDescription)
        \(appInfo.systemVersion) · \(appInfo.deviceModel)
        """
    }
}
