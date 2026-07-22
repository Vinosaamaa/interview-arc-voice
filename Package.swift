// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "InterviewArcVoice",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InterviewArcVoiceCore", targets: ["InterviewArcVoiceCore"]),
        .executable(name: "InterviewArcVoice", targets: ["InterviewArcVoice"]),
    ],
    targets: [
        .target(
            name: "InterviewArcVoiceCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "InterviewArcVoice",
            dependencies: ["InterviewArcVoiceCore"]
        ),
        .testTarget(
            name: "InterviewArcVoiceCoreTests",
            dependencies: ["InterviewArcVoiceCore"]
        ),
    ]
)

