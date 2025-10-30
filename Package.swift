// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fdb-knowledge-layer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "KnowledgeLayer",
            targets: ["KnowledgeLayer"]
        )
    ],
    dependencies: [
        // Sub-layer dependencies (local paths for development)
        .package(path: "../fdb-triple-layer"),
        .package(path: "../fdb-ontology-layer"),
        .package(path: "../fdb-embedding-layer"),

        // Direct dependencies
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/foundationdb/fdb-swift-bindings.git", branch: "main")
    ],
    targets: [
        .target(
            name: "KnowledgeLayer",
            dependencies: [
                .product(name: "TripleLayer", package: "fdb-triple-layer"),
                .product(name: "OntologyLayer", package: "fdb-ontology-layer"),
                .product(name: "EmbeddingLayer", package: "fdb-embedding-layer"),
                .product(name: "FoundationDB", package: "fdb-swift-bindings"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials"),
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "KnowledgeLayerTests",
            dependencies: ["KnowledgeLayer"],
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile"),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("ForwardTrailingClosures"),
                .enableUpcomingFeature("ImplicitOpenExistentials")
                // Note: StrictConcurrency is NOT enabled for tests to allow flexible initialization patterns
            ],
            linkerSettings: [
                .unsafeFlags(["-L/usr/local/lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/usr/local/lib"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
