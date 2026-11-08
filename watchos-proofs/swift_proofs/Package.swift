// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WatchProofs",
    platforms: [.watchOS(.v10)],
    products: [.library(name: "WatchProofs", targets: ["WatchProofs"])],
    targets: [
        .target(name: "WatchProofs"),
        .testTarget(name: "WatchProofsTests", dependencies: ["WatchProofs"]),
    ]
)
