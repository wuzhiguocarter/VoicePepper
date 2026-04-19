import AppKit
import SwiftUI
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
    /// 提升到顶层，供 VoicePepperApp Scene 在 applicationDidFinishLaunching 前安全访问
    let modelManager = WhisperModelManager()
    private var statusBarManager: StatusBarManager?
    private var audioCaptureService: AudioCaptureService?
    private var transcriptionService: TranscriptionService?
    private var accessibilityMonitor: AccessibilityMonitor?
    private let recordingFileService = RecordingFileService()
    private let diarizationService = FluidAudioDiarizationService()

    // BLE 录音笔服务
    let bleDeviceManager = BLEDeviceManager()
    private var bleRecorderService: BLERecorderService?

    private var cancellables = Set<AnyCancellable>()
    /// 手动管理偏好设置窗口，避免 .accessory app 中 showSettingsWindow: 不可靠的问题
    private var preferencesWindow: NSWindow?

    // MARK: Lifecycle

    func applicationWillFinishLaunching(_ notification: Notification) {
        terminatePreviousInstances()
    }

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
        bleRecorderService?.stopRealtimeTranscription()
        transcriptionService?.stop()
        // ggml-metal 析构链在 exit() 路径上会触发 GGML_ASSERT 并卡入 UE 状态；
        // _exit() 跳过 C++ 析构，由内核直接回收所有 GPU/文件资源，安全可靠。
        _exit(0)
    }

    // MARK: Single Instance

    /// 终止同名旧实例，确保同一时刻只有一个 VoicePepper 运行。
    /// 策略：先发 SIGTERM 优雅退出，2 秒后若仍存在则 SIGKILL 强杀。
    private func terminatePreviousInstances() {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let myName = ProcessInfo.processInfo.processName

        let stale = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != myPID && $0.localizedName == myName
        }

        guard !stale.isEmpty else { return }

        for app in stale {
            let pid = app.processIdentifier
            NSLog("[AppDelegate] 终止旧实例 PID=\(pid)")
            // 直接 SIGKILL：跳过 ggml-metal 析构路径，避免旧实例卡入 UE 状态
            kill(pid, SIGKILL)
        }

        // 等待 OS 回收旧实例资源（status bar 槽位、Metal 上下文等）
        Thread.sleep(forTimeInterval: 1.0)
    }

    // MARK: Setup

    private func setupServices() {
        let audioService = AudioCaptureService(appState: appState)
        let transcriptionSvc = TranscriptionService(appState: appState, modelManager: modelManager)

        audioCaptureService = audioService
        transcriptionService = transcriptionSvc

        // 注入 RecordingFileService 到 AppState
        appState.recordingFileService = recordingFileService
        recordingFileService.loadRecordings()

        // Start model loading immediately on launch
        transcriptionSvc.start()

        // E2E 测试钩子：允许 SwiftUI 按钮通过 AppState 触发录音
        appState.toggleRecordingAction = { [weak self] in
            self?.handleToggleRecording()
        }

        // 偏好设置入口：手动创建 NSWindow，规避 .accessory app 中 showSettingsWindow: 不可靠
        appState.openPreferencesAction = { [weak self] in
            self?.openPreferencesWindow()
        }

        // Connect mic audio → transcription
        audioService.audioSegmentPublisher
            .sink { [weak transcriptionSvc] segment in
                transcriptionSvc?.enqueue(segment)
            }
            .store(in: &cancellables)

        // 麦克风录音会话结束 → 持久化
        audioService.sessionEndPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                Task { @MainActor in
                    await self.transcriptionService?.waitUntilIdle()
                    let entries = self.appState.entries
                    await self.recordingFileService.save(
                        session: session,
                        transcriptionEntries: entries,
                        diarizationService: self.diarizationService
                    )
                    self.appState.clearSession()
                }
            }
            .store(in: &cancellables)

        // BLE 录音笔服务
        setupBLEServices(transcriptionSvc: transcriptionSvc)
    }

    private func setupBLEServices(transcriptionSvc: TranscriptionService) {
        let bleSvc = BLERecorderService(deviceManager: bleDeviceManager, appState: appState)
        bleRecorderService = bleSvc

        // BLE audio → transcription
        bleSvc.audioSegmentPublisher
            .sink { [weak transcriptionSvc] segment in
                transcriptionSvc?.enqueue(segment)
            }
            .store(in: &cancellables)

        // BLE 音频电平 → AppState
        bleSvc.levelPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.appState.audioLevel = level
            }
            .store(in: &cancellables)

        // BLE 录音会话结束 → 持久化
        bleSvc.sessionEndPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                Task { @MainActor in
                    await self.transcriptionService?.waitUntilIdle()
                    let entries = self.appState.entries
                    await self.recordingFileService.save(
                        session: session,
                        transcriptionEntries: entries,
                        diarizationService: self.diarizationService
                    )
                    self.appState.clearSession()
                }
            }
            .store(in: &cancellables)

        // BLE 状态 → AppState（直接回调）
        NSLog("[AppDelegate] 绑定 BLE 回调到实例 %p", Unmanaged.passUnretained(bleDeviceManager).toOpaque().debugDescription)
        bleDeviceManager.onConnectionStateChanged = { [weak self] state in
            NSLog("[AppDelegate] BLE 状态同步: %@", String(describing: state))
            self?.appState.bleConnectionState = state
        }
        bleDeviceManager.onBatteryLevelChanged = { [weak self] level in
            self?.appState.bleBatteryLevel = level
        }
        bleDeviceManager.onDeviceStatusChanged = { [weak self] status in
            self?.appState.bleDeviceStatus = status
        }
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
        NSLog("[AppDelegate] handleToggleRecording called, source=%@, AXTrusted=%d, isRecording=%d",
              appState.recordingSource.rawValue,
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
        switch appState.recordingSource {
        case .microphone:
            startMicRecording()
        case .bluetoothRecorder:
            startBLERecording()
        }
    }

    private func stopRecording() {
        switch appState.recordingSource {
        case .microphone:
            audioCaptureService?.stop()
        case .bluetoothRecorder:
            bleRecorderService?.stopRealtimeTranscription()
        }
        appState.stopRecording()
    }

    private func startMicRecording() {
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

    private func startBLERecording() {
        guard bleDeviceManager.connectionState == .connected else {
            NSLog("[AppDelegate] 蓝牙录音笔未连接，无法启动录音")
            return
        }
        bleRecorderService?.startRealtimeTranscription()
        appState.startRecording()
    }

    // MARK: Preferences Window

    func openPreferencesWindow() {
        // 若窗口已存在且可见，直接置前
        if let window = preferencesWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PreferencesView()
            .environmentObject(appState)
            .environmentObject(modelManager)
            .environmentObject(bleDeviceManager)

        let vc = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: vc)
        window.title = "偏好设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 520, height: 640))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        preferencesWindow = window
    }

    // MARK: Permission Prompts

    private func promptAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }
}
