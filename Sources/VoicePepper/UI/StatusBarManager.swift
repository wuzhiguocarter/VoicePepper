import AppKit
import SwiftUI
import Combine

// MARK: - Status Bar Manager (Task 2.2)

@MainActor
final class StatusBarManager {

    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var appState: AppState
    private var cancellables = Set<AnyCancellable>()

    // Pulse animation timer for recording state
    private var pulseTimer: Timer?
    private var pulsePhase: Bool = false

    init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()

        configurePopover()
        configureStatusItem()
        observeState()
    }

    // MARK: Configuration

    private func configurePopover() {
        let popoverView = TranscriptionPopoverView()
            .environmentObject(appState)

        let contentVC = NSHostingController(rootView: popoverView)
        contentVC.view.frame = NSRect(x: 0, y: 0, width: 400, height: 500)

        popover.contentViewController = contentVC
        popover.behavior = .transient
        popover.animates = true
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoicePepper")
        button.imagePosition = .imageOnly
        button.action = #selector(togglePopover)
        button.target = self
        button.setAccessibilityIdentifier("statusBarMicButton")

        updateIcon(isRecording: false)
    }

    private func observeState() {
        appState.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateIcon(isRecording: state.isRecording)
            }
            .store(in: &cancellables)
    }

    // MARK: Icon Update (Task 6.1 - pulse animation)

    private func updateIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }

        if isRecording {
            // Start pulse animation
            pulseTimer?.invalidate()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self, weak button] _ in
                Task { @MainActor [weak self, weak button] in
                    guard let self, let button else { return }
                    self.pulsePhase.toggle()
                    let symbolName = self.pulsePhase ? "mic.fill" : "mic"
                    button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Recording")
                    button.contentTintColor = .systemRed
                }
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulsePhase = false
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "VoicePepper")
            button.contentTintColor = nil
        }
    }

    // MARK: Popover Toggle

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
