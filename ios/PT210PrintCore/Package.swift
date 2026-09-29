// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PT210PrintCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "PT210PrintCore", targets: ["PT210PrintCore"])
    ],
    targets: [
        .target(name: "PT210PrintCore"),
        .testTarget(name: "PT210PrintCoreTests", dependencies: ["PT210PrintCore"])
    ]
)
