// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PlatformProbe",
    products: [
        .library(name: "ProbeCore", targets: ["ProbeCore"])
    ],
    targets: [
        .target(name: "ProbeCore", path: "Sources/ProbeCore"),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"], path: "Tests/ProbeCoreTests")
    ]
)
