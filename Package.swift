// swift-tools-version: 5.9
import PackageDescription
import Foundation

// Homebrew prefix: /opt/homebrew (arm64) or /usr/local (x86_64)
// Override via HOMEBREW_PREFIX env var for cross-architecture CI builds
let homebrewPrefix = ProcessInfo.processInfo.environment["HOMEBREW_PREFIX"] ?? "/opt/homebrew"
let whisperInclude = "\(homebrewPrefix)/include"
let whisperLib = "\(homebrewPrefix)/lib"

let package = Package(
    name: "VoicePepper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoicePepper", targets: ["VoicePepper"]),
        .executable(name: "VoicePepperEval", targets: ["VoicePepperEval"]),
        .library(name: "VoicePepperCore", targets: ["VoicePepperCore"]),
    ],
    dependencies: [
        // Global hotkey management - pinned to avoid #Preview macro issues with CLI tools
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            exact: "1.14.0"
        ),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.12.4"
        ),
        .package(
            url: "https://github.com/argmaxinc/argmax-oss-swift.git",
            from: "0.9.0"
        ),
    ],
    targets: [
        // C bridge to system libwhisper (installed via `brew install whisper-cpp`)
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            publicHeadersPath: "include",
            cSettings: [
                // Both whisper-cpp and ggml headers are in /opt/homebrew/include
                .unsafeFlags([
                    "-I\(whisperInclude)",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(whisperLib)",
                    "-lwhisper",
                    "-lggml",
                    "-lggml-base",
                ])
            ]
        ),

        // C bridge to system libopus (installed via `brew install opus`)
        .target(
            name: "COpus",
            path: "Sources/COpus",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(whisperInclude)"]),
            ],
            linkerSettings: [
                .unsafeFlags(["-L\(whisperLib)", "-lopus"]),
            ]
        ),

        // Shared pipeline library (no AppKit/UI dependency)
        .target(
            name: "VoicePepperCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/VoicePepperCore"
        ),

        // CLI eval binary
        .executableTarget(
            name: "VoicePepperEval",
            dependencies: ["VoicePepperCore"],
            path: "Sources/VoicePepperEval"
        ),

        // VoicePepperCore unit tests (requires full Xcode, not CommandLineTools)
        .testTarget(
            name: "VoicePepperCoreTests",
            dependencies: ["VoicePepperCore"],
            path: "Tests/VoicePepperCoreTests"
        ),

        // Main macOS app target
        .executableTarget(
            name: "VoicePepper",
            dependencies: [
                "CWhisper",
                "COpus",
                "VoicePepperCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/VoicePepper",
            exclude: ["Resources/VoicePepper.entitlements"],
            swiftSettings: [
                .unsafeFlags(["-Xcc", "-I\(whisperInclude)"]),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("Combine"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("CoreBluetooth"),
            ]
        ),
    ]
)
