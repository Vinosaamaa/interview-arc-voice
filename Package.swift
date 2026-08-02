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
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            exact: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "InterviewArcVoiceCore",
            dependencies: [
                .product(name: "libfvad", package: "libfvad"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
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
