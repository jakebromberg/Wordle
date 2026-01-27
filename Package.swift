// swift-tools-version: 5.9

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "Wordle",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "wordle", targets: ["wordle"]),
        .library(name: "WordleLib", targets: ["WordleLib"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        // Macro implementation (runs at compile time)
        .macro(
            name: "WordleMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "WordleLib",
            dependencies: ["WordleMacros"],
            resources: [.copy("Resources/words5.txt")]
        ),
        .executableTarget(
            name: "wordle",
            dependencies: ["WordleLib"]
        ),
        .testTarget(
            name: "WordleTests",
            dependencies: ["WordleLib"]
        ),
        .testTarget(
            name: "WordleMacrosTests",
            dependencies: [
                "WordleMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ]
)
