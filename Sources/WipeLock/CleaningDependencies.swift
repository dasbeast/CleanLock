import AppKit
import ApplicationServices
import Foundation

// Small protocols keep macOS side effects replaceable in unit tests.
protocol AccessibilityPermissionProviding {
    var isTrusted: Bool { get }
    func requestAccess() -> Bool
}

struct SystemAccessibilityPermissionProvider: AccessibilityPermissionProviding {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccess() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }
}

protocol ClockProviding {
    var now: Date { get }
}

struct SystemClock: ClockProviding {
    var now: Date {
        Date()
    }
}

protocol CleaningTimer {
    func invalidate()
}

protocol CleaningTimerScheduling {
    func scheduleRepeating(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> CleaningTimer
}

final class FoundationCleaningTimerScheduler: CleaningTimerScheduling {
    func scheduleRepeating(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> CleaningTimer {
        // Timers fire on the run loop, then hop back to the main actor for UI state.
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                action()
            }
        }
        return FoundationCleaningTimer(timer: timer)
    }
}

private final class FoundationCleaningTimer: CleaningTimer {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}

protocol InputBlocking {
    func start() -> Bool
    func stop()
}

// Gesture changes are best-effort and do not need to report success to the UI.
protocol GestureBlocking {
    func start()
    func stop()
}

protocol AlertSoundPlaying {
    func playFinishedSound()
}

struct SystemAlertSoundPlayer: AlertSoundPlaying {
    func playFinishedSound() {
        NSSound.beep()
    }
}
