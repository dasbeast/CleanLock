import Combine
import Foundation

@MainActor
final class CleaningController: ObservableObject {
    // The controller moves idle -> arming -> locked, then back to idle.
    enum Phase {
        case idle
        case arming
        case locked
    }

    static let cleaningDurations = [30, 60, 120, 180]

    @Published var phase: Phase = .idle
    @Published var selectedDuration = 60
    @Published var secondsRemaining = 0
    @Published var accessibilityTrusted = false
    @Published var inputBlockingTrusted = false
    @Published var lockFailureMessage: String?

    private var timer: CleaningTimer?
    private var timerStartDate: Date?
    private var timerDuration = 0

    private let accessibility: AccessibilityPermissionProviding
    private let clock: ClockProviding
    private let timerScheduler: CleaningTimerScheduling
    private let eventBlocker: InputBlocking
    private let trackpadBlocker: InputBlocking
    private let gestureBlocker: GestureBlocking
    private let soundPlayer: AlertSoundPlaying

    convenience init() {
        // If the app previously quit mid-session, restore saved gesture settings.
        TrackpadGestureBlocker.recoverIfNeeded()
        self.init(
            accessibility: SystemAccessibilityPermissionProvider(),
            clock: SystemClock(),
            timerScheduler: FoundationCleaningTimerScheduler(),
            eventBlocker: EventTapInputBlocker(),
            trackpadBlocker: HIDTrackpadBlocker(),
            gestureBlocker: TrackpadGestureBlocker(),
            soundPlayer: SystemAlertSoundPlayer()
        )
    }

    init(
        accessibility: AccessibilityPermissionProviding,
        clock: ClockProviding,
        timerScheduler: CleaningTimerScheduling,
        eventBlocker: InputBlocking,
        trackpadBlocker: InputBlocking,
        gestureBlocker: GestureBlocking,
        soundPlayer: AlertSoundPlaying
    ) {
        self.accessibility = accessibility
        self.clock = clock
        self.timerScheduler = timerScheduler
        self.eventBlocker = eventBlocker
        self.trackpadBlocker = trackpadBlocker
        self.gestureBlocker = gestureBlocker
        self.soundPlayer = soundPlayer
    }

    var canStart: Bool {
        phase == .idle
    }

    var primaryButtonTitle: String {
        isReadyToBlockInput ? "Start Cleaning Mode" : "Allow Input Blocking"
    }

    var shouldShowPermissionHint: Bool {
        !isReadyToBlockInput
    }

    var statusTitle: String {
        switch phase {
        case .idle:
            return "Ready"
        case .arming:
            return "Starting soon"
        case .locked:
            return "Input paused"
        }
    }

    var statusDetail: String {
        switch phase {
        case .idle:
            if let lockFailureMessage {
                return lockFailureMessage
            }
            return "Choose a duration, click start, then lift your hands for the short countdown."
        case .arming:
            return "Move your hands away. Input blocking starts when this countdown finishes."
        case .locked:
            return "Keyboard, media keys, clicks, pointer movement, scrolling, and trackpad gestures are paused until the timer ends."
        }
    }

    var displayTime: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = accessibility.isTrusted
        if accessibilityTrusted {
            inputBlockingTrusted = true
        }
    }

    func requestAccessibilityAccess() {
        accessibilityTrusted = accessibility.requestAccess()
        if accessibilityTrusted {
            inputBlockingTrusted = true
        } else {
            accessibility.openSettings()
        }
    }

    func start() {
        refreshAccessibilityStatus()

        guard phase == .idle else {
            return
        }

        if !accessibilityTrusted {
            // Creating the event tap later can trigger Input Monitoring on newer macOS.
            requestAccessibilityAccess()
        }

        lockFailureMessage = nil
        phase = .arming
        timerDuration = 3
        timerStartDate = clock.now
        secondsRemaining = 3
        scheduleTimer { [weak self] in
            self?.tickArmingTimer()
        }
    }

    func stop(clearFailureMessage: Bool = true) {
        timer?.invalidate()
        timer = nil
        timerStartDate = nil
        gestureBlocker.stop()
        trackpadBlocker.stop()
        eventBlocker.stop()
        secondsRemaining = 0
        phase = .idle
        if clearFailureMessage {
            lockFailureMessage = nil
        }
        refreshAccessibilityStatus()
    }

    private func tickArmingTimer() {
        guard let start = timerStartDate else { return }
        let remaining = timerDuration - Int(clock.now.timeIntervalSince(start))
        guard remaining > 0 else {
            beginLockedMode()
            return
        }
        secondsRemaining = remaining
    }

    private func beginLockedMode() {
        // The event tap is the required blocker. Other blockers are additive.
        guard eventBlocker.start() else {
            inputBlockingTrusted = false
            lockFailureMessage = "WipeLock could not start the input blocker. Grant Accessibility or Input Monitoring permission in System Settings, then try again."
            stop(clearFailureMessage: false)
            return
        }

        inputBlockingTrusted = true
        gestureBlocker.start()
        // Seizing the trackpad can fail on some Macs, so locked mode still continues.
        _ = trackpadBlocker.start()

        phase = .locked
        timerDuration = selectedDuration
        timerStartDate = clock.now
        secondsRemaining = selectedDuration
        scheduleTimer { [weak self] in
            self?.tickLockedTimer()
        }
    }

    private func tickLockedTimer() {
        guard let start = timerStartDate else { return }
        let remaining = timerDuration - Int(clock.now.timeIntervalSince(start))
        guard remaining > 0 else {
            soundPlayer.playFinishedSound()
            stop()
            return
        }
        secondsRemaining = remaining
    }

    private func scheduleTimer(_ action: @escaping @MainActor () -> Void) {
        timer?.invalidate()
        timer = timerScheduler.scheduleRepeating(every: 1, action: action)
    }

    private var isReadyToBlockInput: Bool {
        accessibilityTrusted || inputBlockingTrusted
    }
}
