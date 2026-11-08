// swift-tools-version:5.9
import PackageDescription

// The Sources/SpecCode/*.swift files are GENERATED from the spec (scripts/extract_spec_code.py).
let package = Package(
    name: "SpecCode",
    platforms: [.watchOS(.v10)],
    products: [.library(name: "SpecCode", targets: ["SpecCode"])],
    targets: [
        .target(name: "SpecCode"),
        .testTarget(name: "SpecCodeTests", dependencies: ["SpecCode"]),
    ]
)
