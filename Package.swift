// swift-tools-version: 5.9
import PackageDescription

// Homebrew whisper-cpp install paths (arm64 Mac)
let whisperInclude = "/opt/homebrew/include"
let whisperLib = "/opt/homebrew/lib"

let package = Package(
    name: "VoicePepper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VoicePepper", targets: ["VoicePepper"]),
    ],
    dependencies: [
        // Global hotkey management - pinned to avoid #Preview macro issues with CLI tools
        .package(
            url: "https://github.com/sindresorhus/KeyboardShortcuts",
            exact: "1.14.0"
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

        // Main macOS app target
        .executableTarget(
            name: "VoicePepper",
            dependencies: [
                "CWhisper",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/VoicePepper",
            exclude: ["Resources/VoicePepper.entitlements"],
            swiftSettings: [
                // Pass ggml/whisper include path to Swift's clang importer (for CWhisper module)
                .unsafeFlags(["-Xcc", "-I\(whisperInclude)"]),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("Combine"),
                .linkedFramework("CoreAudio"),
            ]
        ),
    ]
)
