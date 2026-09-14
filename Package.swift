// swift-tools-version: 6.0
import PackageDescription

// The Xcode project builds the app. This package runs its logic and lifecycle tests.
let package = Package(
    name: "Layby",
    platforms: [.macOS("15.6")],
    products: [.library(name: "LaybyKit", targets: ["LaybyKit"])],
    targets: [
        .target(name: "LaybyKit", path: "Layby", exclude: ["MyApp.swift", "Assets.xcassets"]),
        .testTarget(name: "LaybyTests", dependencies: ["LaybyKit"], path: "LaybyTests")
    ],
    swiftLanguageModes: [.v5]
)
