// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gate0dProbeCore",
    platforms: [.watchOS(.v10)],
    products: [
        .library(name: "Gate0dProbeCore", targets: ["Gate0dProbeCore"]),
    ],
    targets: [
        .target(name: "CProbeShims"),
        .target(name: "Gate0dProbeCore", dependencies: ["CProbeShims"]),
        .testTarget(name: "Gate0dProbeCoreTests", dependencies: ["Gate0dProbeCore"]),
    ]
)
