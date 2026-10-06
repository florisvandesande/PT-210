// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "PT210PrintCore",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v27),
        .macCatalyst(.v27)
    ],
    products: [
        .library(name: "PT210PrintCore", targets: ["PT210PrintCore"])
    ],
    targets: [
        .target(name: "PT210PrintCore"),
        .testTarget(name: "PT210PrintCoreTests", dependencies: ["PT210PrintCore"])
    ]
)
