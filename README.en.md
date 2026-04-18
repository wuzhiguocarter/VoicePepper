# VoicePepper

A macOS menu bar speech-to-text tool powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Fully offline — all audio processing happens locally on your device. No data is ever uploaded.

## Features

- **Offline Transcription** — Powered by whisper.cpp, supports 8 models (tiny to large-v3) including quantized variants
- **Global Hotkey** — Default `⌥ Space`, start/stop recording from any app
- **Smart Segmentation** — VAD-based silence detection for automatic segment splitting
- **BLE Recording Pen** — Supports Bluetooth recording pen (A06) for wireless real-time transcription
- **Recording History** — WAV format persistence with playback and re-transcription
- **Hot-swap Models** — Switch Whisper models in preferences without restarting
- **Menu Bar Resident** — Lives in the status bar, no Dock icon

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1/M2/M3/M4) or Intel Mac

## Installation Guide

### Step 1: Download

Go to the [GitHub Releases](https://github.com/wuzhiguocarter/VoicePepper/releases) page and download the latest DMG file.

**Which version to choose?**

Click  in the top-left corner → About This Mac → check your chip:

| Your Chip | Download |
|-----------|----------|
| Apple M1 / M2 / M3 / M4 | `VoicePepper-*-arm64.dmg` (smallest, recommended) |
| Intel | `VoicePepper-*-x86_64.dmg` |
| Not sure | `VoicePepper-*-universal.dmg` (supports both) |

### Step 2: Install

1. Double-click the downloaded `.dmg` file to open the installer window
2. Drag the **VoicePepper** icon to the **Applications** folder
3. Close the installer window. Find VoicePepper in Launchpad or the Applications folder

### Step 3: First Launch

Since the app is not signed with an Apple Developer ID, macOS will block the first launch. Follow these steps:

1. Open **Finder** → Applications
2. Find **VoicePepper** and **right-click** it (or Control-click)
3. Select **Open**
4. Click **Open** in the confirmation dialog

> You only need to do this once. After that, you can open it normally.

### Step 4: Grant Permissions

Two permissions are needed on first launch:

**Microphone** (system prompts automatically):
- Click **OK** to allow microphone access

**Accessibility** (required for global hotkey, manual setup):
1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Click the 🔒 lock to unlock
3. Click **+** and add **VoicePepper** from the Applications list
4. Make sure the toggle next to VoicePepper is on

### Step 5: Download Speech Model

On first launch, the app will guide you to download a Whisper speech recognition model.

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| tiny | 75 MB | Fastest | Fair | Quick trial, low-end Mac |
| base | 142 MB | Fast | Good | Daily use |
| large-v3-turbo-q5_0 | 600 MB | Medium | Best | Best accuracy (recommended) |

Models are downloaded once and stored in `~/Library/Application Support/VoicePepper/models/`.

## User Guide

### Basic Operations

VoicePepper is a menu bar app — it **does not appear in the Dock**. Look for its icon in the top-right menu bar.

| Action | Description |
|--------|-------------|
| `⌥ Space` | Start / stop recording (global hotkey, works in any app) |
| Click menu bar icon | Open transcription panel to view results |
| Panel → Copy All | Copy all transcribed text to clipboard |
| Panel → Clear | Clear current session |
| Right-click menu bar icon | Open preferences |

### Preferences

In preferences you can:

- **Custom Hotkey** — Change the recording trigger shortcut
- **Switch Model** — Choose a different Whisper model
- **Audio Source** — Switch between built-in microphone and BLE recording pen

### BLE Recording Pen

If you have a compatible Bluetooth recording pen (A06):

1. Turn on the pen's Bluetooth
2. Select BLE audio source in preferences
3. Wait for auto-connection
4. Press the pen's record button — VoicePepper transcribes in real time

### Uninstall

1. Quit VoicePepper (right-click menu bar icon → Quit)
2. Delete VoicePepper.app from the Applications folder
3. (Optional) Remove data: `rm -rf ~/Library/Application\ Support/VoicePepper`

## For Developers

### Build from Source

```bash
# Install dependencies
brew install whisper-cpp opus

# Build
swift build -c release

# Or open in Xcode
open Package.swift
```

See [SETUP.md](SETUP.md) for the full development guide.

### Tech Stack

- **Language**: Swift 5.9 + SwiftUI
- **Speech Recognition**: [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (C API bridge)
- **Audio Decoding**: [Opus](https://opus-codec.org/) (BLE recording pen audio)
- **Hotkeys**: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- **Build System**: Swift Package Manager
- **CI/CD**: GitHub Actions (auto-builds 3 architecture DMGs)

## License

[MIT](LICENSE)
