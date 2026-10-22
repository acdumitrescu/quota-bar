// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Quota",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "QuotaApp", targets: ["QuotaApp"]),
        .executable(name: "quota", targets: ["quota-cli"]),
    ],
    targets: [
        .target(name: "QuotaCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "QuotaApp", dependencies: ["QuotaCore"]),
        .executableTarget(name: "quota-cli", dependencies: ["QuotaCore"]),
        .testTarget(name: "QuotaCoreTests", dependencies: ["QuotaCore"]),
    ]
)
