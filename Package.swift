// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "InterviewArcVoice",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "InterviewArcVoiceCore", targets: ["InterviewArcVoiceCore"]),
        .executable(name: "InterviewArcVoice", targets: ["InterviewArcVoice"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/gfreezy/libfvad",
            revision: "b685985209f19e9f94c04514e849089869b1d5d5"
        ),
    ],
    targets: [
        .target(
            name: "InterviewArcVoiceCore",
            dependencies: [
                .product(name: "libfvad", package: "libfvad"),
            ],
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
