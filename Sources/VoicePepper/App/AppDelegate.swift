import AppKit
import Combine
import KeyboardShortcuts

// MARK: - KeyboardShortcuts Name (Task 3.1)

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.space, modifiers: .option))
}

// MARK: - App Delegate (Task 2.1)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Core services (Task 2.4 - DI via AppDelegate ownership)
    let appState = AppState()
    private var statusBarManager: StatusBarManager?
    private var audioCaptureService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var accessibilityMonitor: AccessibilityMonitor?

    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as agent (LSUIElement=YES in Info.plist handles dock hiding)
        NSApp.setActivationPolicy(.accessory)

        // Wire services
        setupServices()
        setupStatusBar()
        setupHotkey()
        setupAccessibilityMonitor()
        setupBindings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioCaptureService?.stop()
        transcriptionService?.stop()
    }

    // MARK: Setup

    private func setupServices() {
        let audioService = AudioCaptureService(appState: appState)
        let transcriptionSvc = TranscriptionService(appState: appState)

        audioCaptureService = audioService
        transcriptionService = transcriptionSvc

        // Start model loading immediately on launch
        transcriptionSvc.start()

        // E2E 测试钩子：允许 SwiftUI 按钮通过 AppState 触发录音
        appState.toggleRecordingAction = { [weak self] in
            self?.handleToggleRecording()
        }

        // Connect audio → transcription
        audioService.audioSegmentPublisher
            .sink { [weak transcriptionSvc] segment in
                transcriptionSvc?.enqueue(segment)
            }
            .store(in: &cancellables)
    }

    private func setupStatusBar() {
        statusBarManager = StatusBarManager(appState: appState)
    }

    private func setupHotkey() {
        // Task 3.1 - register ⌥Space via KeyboardShortcuts
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            Task { @MainActor in
                self?.handleToggleRecording()
            }
        }
    }

    private func setupAccessibilityMonitor() {
        // Task 3.3 - poll for accessibility permission changes
        accessibilityMonitor = AccessibilityMonitor { [weak self] granted in
            Task { @MainActor in
                self?.appState.accessibilityPermissionGranted = granted
            }
        }
        accessibilityMonitor?.start()

        // Update initial state
        appState.accessibilityPermissionGranted = AXIsProcessTrusted()
    }

    private func setupBindings() {
        // Keep model load state in sync (TranscriptionService loads async)
        transcriptionService?.modelReadyPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                self?.appState.isModelLoaded = ready
            }
            .store(in: &cancellables)

        transcriptionService?.modelErrorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.appState.modelLoadError = error
            }
            .store(in: &cancellables)
    }

    // MARK: Recording Control

    func handleToggleRecording() {
        NSLog("[AppDelegate] handleToggleRecording called, AXTrusted=%d, isRecording=%d",
              AXIsProcessTrusted() ? 1 : 0,
              appState.recordingState.isRecording ? 1 : 0)
        // Task 3.2 - check accessibility permission before recording
        guard AXIsProcessTrusted() else {
            NSLog("[AppDelegate] 未获得辅助功能权限，显示提示")
            promptAccessibilityPermission()
            return
        }

        if appState.recordingState.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        audioCaptureService?.start { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.appState.micPermissionDenied = (error == .permissionDenied)
                } else {
                    self?.appState.startRecording()
                }
            }
        }
    }

    private func stopRecording() {
        audioCaptureService?.stop()
        appState.stopRecording()
    }

    // MARK: Permission Prompts

    private func promptAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }
}
