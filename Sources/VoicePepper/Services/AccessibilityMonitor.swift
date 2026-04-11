import AppKit

// MARK: - Accessibility Monitor (Task 3.3)
// Polls AXIsProcessTrusted() and fires callback when permission changes.
// macOS does not provide a notification for this, so polling is the standard approach.

final class AccessibilityMonitor {
    private var timer: Timer?
    private var lastState: Bool = false
    private let onChange: (Bool) -> Void

    private let pollInterval: TimeInterval = 2.0

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        self.lastState = AXIsProcessTrusted()
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkPermission()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPermission() {
        let current = AXIsProcessTrusted()
        guard current != lastState else { return }
        lastState = current
        onChange(current)
    }

    deinit {
        timer?.invalidate()
    }
}
