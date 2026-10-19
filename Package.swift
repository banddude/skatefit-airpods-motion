// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SkateFitBridgeChecks",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SkateFitCore", targets: ["SkateFitCore"])],
    targets: [
        .target(name: "SkateFitCore", path: ".", sources: [
            "SkateMotion/Models/BoardMathTypes.swift",
            "SkateMotion/Models/BoardOrientation.swift",
            "SkateMotion/Models/RunnerCourse.swift",
            "SkateMotion/Models/RunnerEngine.swift",
            "SkateMotion/Models/RunnerInput.swift",
            "SkateMotion/Models/RunnerProgressStore.swift",
            "Shared/TVBridge/TVBridgeProtocol.swift",
            "Shared/TVBridge/TVBridgeTransport.swift",
            "SkateMotionTV/TVGameSession.swift",

        ]),
        .testTarget(name: "TVBridgeTests", dependencies: ["SkateFitCore"], path: "TVBridgeTests")
    ])
