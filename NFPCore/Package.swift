// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NFPCore",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NFPCore", targets: ["NFPCore"]),
    ],
    targets: [
        .target(name: "NFPCore"),
        // Läuft auch ohne Xcode (nur Command Line Tools): `swift run NFPCoreChecks`
        .executableTarget(name: "NFPCoreChecks", dependencies: ["NFPCore"]),
    ]
)
