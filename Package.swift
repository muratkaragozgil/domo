// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Domo",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Domo",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        )
    ]
)
