// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PT210PrintCore",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .macCatalyst(.v13)
    ],
    products: [
        .library(name: "PT210PrintCore", targets: ["PT210PrintCore"])
    ],
    targets: [
        .target(name: "PT210PrintCore"),
        .testTarget(name: "PT210PrintCoreTests", dependencies: ["PT210PrintCore"])
    ]
)
