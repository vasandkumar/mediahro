// swift-tools-version: 5.9
// Engine plugin (lane B1). libmpv and its dependencies are dynamic
// xcframeworks staged into Frameworks/ by tool/stage_native.py from the
// pinned mediahro-deps archive (deps.lock) or, until then, the ADR-004
// bootstrap. LGPL libraries stay dynamic (docs/09 §2). Without staged
// frameworks the plugin still builds and the engine reports libraryMissing.

import Foundation
import PackageDescription

let frameworksDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Frameworks")
let xcframeworks = ((try? FileManager.default.contentsOfDirectory(
    atPath: frameworksDir.path)) ?? [])
    .filter { $0.hasSuffix(".xcframework") }
    .sorted()
let binaryTargets: [Target] = xcframeworks.map {
    .binaryTarget(name: String($0.dropLast(".xcframework".count)), path: "Frameworks/\($0)")
}

let package = Package(
    name: "mediahro_engine",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "mediahro-engine", targets: ["mediahro_engine"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "mediahro_engine",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ] + binaryTargets.map { .target(name: $0.name) },
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("OpenGLES"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOSurface"),
            ]
        )
    ] + binaryTargets
)
