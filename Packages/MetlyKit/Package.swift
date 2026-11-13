// swift-tools-version: 6.2
import PackageDescription

/// UI-facing modules default to MainActor isolation (Swift 6.2 approachable concurrency).
let mainActorSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

/// Pure / networking modules stay nonisolated so values can cross actors freely.
let nonisolatedSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "MetlyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        // Linked by the app target.
        .library(name: "MetlyApp", targets: [
            "MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyNetworking", "MetlyWidgetKit", "MetlyCapture", "MetlySharedUI",
            "FeatureOnboarding", "FeatureHome", "FeatureCards", "FeatureScan",
            "FeatureConnect", "FeaturePeople", "FeatureEvents", "FeatureProfile",
        ]),
        // Linked by the widget extension (keep it light).
        .library(name: "MetlyWidgetSupport", targets: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyWidgetKit"]),

        // One product per module so `scripts/build.sh <Module>` can build it alone.
        .library(name: "MetlyCore", targets: ["MetlyCore"]),
        .library(name: "MetlyDesign", targets: ["MetlyDesign"]),
        .library(name: "MetlyCardKit", targets: ["MetlyCardKit"]),
        .library(name: "MetlyData", targets: ["MetlyData"]),
        .library(name: "MetlyNetworking", targets: ["MetlyNetworking"]),
        .library(name: "MetlyWidgetKit", targets: ["MetlyWidgetKit"]),
        .library(name: "MetlyCapture", targets: ["MetlyCapture"]),
        .library(name: "MetlySharedUI", targets: ["MetlySharedUI"]),
        .library(name: "FeatureOnboarding", targets: ["FeatureOnboarding"]),
        .library(name: "FeatureHome", targets: ["FeatureHome"]),
        .library(name: "FeatureCards", targets: ["FeatureCards"]),
        .library(name: "FeatureScan", targets: ["FeatureScan"]),
        .library(name: "FeatureConnect", targets: ["FeatureConnect"]),
        .library(name: "FeaturePeople", targets: ["FeaturePeople"]),
        .library(name: "FeatureEvents", targets: ["FeatureEvents"]),
        .library(name: "FeatureProfile", targets: ["FeatureProfile"]),
    ],
    // No third-party dependencies: Google sign-in uses ASWebAuthenticationSession + PKCE.
    dependencies: [],
    targets: [
        // MARK: Foundation (orchestrator-owned contracts)
        .target(name: "MetlyCore", swiftSettings: nonisolatedSettings),
        .target(name: "MetlyDesign", dependencies: ["MetlyCore"], resources: [.process("Resources")], swiftSettings: mainActorSettings),
        .target(name: "MetlyCardKit", dependencies: ["MetlyCore", "MetlyDesign"], swiftSettings: nonisolatedSettings),
        .target(name: "MetlyNetworking", dependencies: ["MetlyCore"], swiftSettings: nonisolatedSettings),
        // SwiftData @Model types must not be MainActor-isolated → nonisolated default; services are @MainActor explicitly.
        .target(name: "MetlyData", dependencies: ["MetlyCore", "MetlyNetworking"], swiftSettings: nonisolatedSettings),
        .target(name: "MetlyWidgetKit", dependencies: ["MetlyCore", "MetlyCardKit"], swiftSettings: mainActorSettings),
        // Context capture shared by People, Connect, Scan, Events (owned by the People & Context agent).
        .target(name: "MetlyCapture", dependencies: ["MetlyCore", "MetlyDesign", "MetlyData"], swiftSettings: mainActorSettings),
        // Data-aware UI shared by several features (card actions menu, card rules, Safari). Orchestrator-owned.
        .target(name: "MetlySharedUI", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData"], swiftSettings: mainActorSettings),

        // MARK: Features (never depend on each other)
        .target(name: "FeatureOnboarding", dependencies: [
            "MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyNetworking",
        ], swiftSettings: mainActorSettings),
        .target(name: "FeatureHome", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyCapture", "MetlyNetworking", "MetlySharedUI"], swiftSettings: mainActorSettings),
        .target(name: "FeatureCards", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyNetworking", "MetlyCapture", "MetlySharedUI"], swiftSettings: mainActorSettings),
        .target(name: "FeatureScan", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyNetworking", "MetlyCapture", "MetlySharedUI"], swiftSettings: mainActorSettings),
        .target(name: "FeatureConnect", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyNetworking", "MetlyCapture", "MetlySharedUI"], swiftSettings: mainActorSettings),
        .target(name: "FeaturePeople", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyCapture", "MetlyNetworking", "MetlySharedUI"], swiftSettings: mainActorSettings),
        .target(name: "FeatureEvents", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyCapture", "MetlyNetworking", "MetlySharedUI"], swiftSettings: mainActorSettings),
        .target(name: "FeatureProfile", dependencies: ["MetlyCore", "MetlyDesign", "MetlyCardKit", "MetlyData", "MetlyNetworking", "MetlySharedUI"], swiftSettings: mainActorSettings),

        // MARK: Tests (Swift Testing)
        .testTarget(name: "MetlyCoreTests", dependencies: ["MetlyCore"]),
        .testTarget(name: "MetlyDesignTests", dependencies: ["MetlyDesign"]),
        .testTarget(name: "MetlyCardKitTests", dependencies: ["MetlyCardKit"]),
        .testTarget(name: "MetlyDataTests", dependencies: ["MetlyData"]),
        // Its own process: writing stores with the frozen schemas next to other suites using the current one
        // makes SwiftData mix up the same-named models.
        .testTarget(name: "MetlyDataMigrationTests", dependencies: ["MetlyData"]),
        .testTarget(name: "MetlyNetworkingTests", dependencies: ["MetlyNetworking"]),
        .testTarget(name: "MetlyWidgetKitTests", dependencies: ["MetlyWidgetKit"]),
        .testTarget(name: "MetlyCaptureTests", dependencies: ["MetlyCapture"]),
        .testTarget(name: "MetlySharedUITests", dependencies: ["MetlySharedUI"]),
        .testTarget(name: "FeatureOnboardingTests", dependencies: ["FeatureOnboarding"]),
        .testTarget(name: "FeatureHomeTests", dependencies: ["FeatureHome"]),
        .testTarget(name: "FeatureCardsTests", dependencies: ["FeatureCards"]),
        .testTarget(name: "FeatureScanTests", dependencies: ["FeatureScan"]),
        .testTarget(name: "FeatureConnectTests", dependencies: ["FeatureConnect"]),
        .testTarget(name: "FeaturePeopleTests", dependencies: ["FeaturePeople"]),
        .testTarget(name: "FeatureEventsTests", dependencies: ["FeatureEvents"]),
        .testTarget(name: "FeatureProfileTests", dependencies: ["FeatureProfile"]),
    ]
)
