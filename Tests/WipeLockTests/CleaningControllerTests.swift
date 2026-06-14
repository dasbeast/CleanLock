import XCTest
@testable import WipeLock

@MainActor
final class CleaningControllerTests: XCTestCase {
    private var accessibility: FakeAccessibilityPermissionProvider!
    private var clock: FakeClock!
    private var timerScheduler: FakeTimerScheduler!
    private var eventBlocker: FakeInputBlocker!
    private var trackpadBlocker: FakeInputBlocker!
    private var gestureBlocker: FakeGestureBlocker!
    private var soundPlayer: FakeSoundPlayer!
    private var controller: CleaningController!

    override func setUp() async throws {
        // Use fakes so tests never touch real Accessibility, timers, or HID devices.
        accessibility = FakeAccessibilityPermissionProvider()
        clock = FakeClock(now: Date(timeIntervalSinceReferenceDate: 1_000))
        timerScheduler = FakeTimerScheduler()
        eventBlocker = FakeInputBlocker()
        trackpadBlocker = FakeInputBlocker()
        gestureBlocker = FakeGestureBlocker()
        soundPlayer = FakeSoundPlayer()
        controller = CleaningController(
            accessibility: accessibility,
            clock: clock,
            timerScheduler: timerScheduler,
            eventBlocker: eventBlocker,
            trackpadBlocker: trackpadBlocker,
            gestureBlocker: gestureBlocker,
            soundPlayer: soundPlayer
        )
    }

    func testDisplayTimeFormatsMinutesAndSeconds() {
        controller.secondsRemaining = 125

        XCTAssertEqual(controller.displayTime, "2:05")
    }

    func testCanStartRequiresIdleAndAccessibilityPermission() {
        accessibility.isTrustedValue = true
        controller.refreshAccessibilityStatus()

        XCTAssertTrue(controller.canStart)

        controller.start()

        XCTAssertFalse(controller.canStart)
    }

    func testStartWithoutPermissionRequestsAccessAndStaysIdle() {
        accessibility.isTrustedValue = false
        accessibility.requestAccessResult = false

        controller.start()

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(accessibility.requestAccessCallCount, 1)
        XCTAssertEqual(timerScheduler.scheduleCallCount, 0)
    }

    func testStartWithPermissionBeginsArmingCountdown() {
        accessibility.isTrustedValue = true

        controller.start()

        XCTAssertEqual(controller.phase, .arming)
        XCTAssertEqual(controller.secondsRemaining, 3)
        XCTAssertEqual(timerScheduler.scheduleCallCount, 1)
        XCTAssertFalse(eventBlocker.isStarted)
    }

    func testArmingCountdownTransitionsToLockedMode() {
        accessibility.isTrustedValue = true
        controller.selectedDuration = 120
        controller.start()

        clock.advance(by: 3)
        timerScheduler.fireLatest()

        XCTAssertEqual(controller.phase, .locked)
        XCTAssertEqual(controller.secondsRemaining, 120)
        XCTAssertTrue(eventBlocker.isStarted)
        XCTAssertTrue(trackpadBlocker.isStarted)
        XCTAssertTrue(gestureBlocker.isStarted)
        XCTAssertEqual(timerScheduler.scheduleCallCount, 2)
    }

    func testEventBlockerFailureReturnsToIdleAndKeepsFailureMessage() {
        accessibility.isTrustedValue = true
        eventBlocker.startResult = false
        controller.start()

        clock.advance(by: 3)
        timerScheduler.fireLatest()

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.secondsRemaining, 0)
        XCTAssertFalse(trackpadBlocker.isStarted)
        XCTAssertFalse(gestureBlocker.isStarted)
        XCTAssertEqual(controller.lockFailureMessage, "WipeLock could not start the keyboard blocker. Check Accessibility permission, then try again.")
    }

    func testStopClearsBlockersAndFailureMessage() {
        accessibility.isTrustedValue = true
        controller.lockFailureMessage = "Previous problem"
        controller.start()
        clock.advance(by: 3)
        timerScheduler.fireLatest()

        controller.stop()

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.secondsRemaining, 0)
        XCTAssertNil(controller.lockFailureMessage)
        XCTAssertFalse(eventBlocker.isStarted)
        XCTAssertFalse(trackpadBlocker.isStarted)
        XCTAssertFalse(gestureBlocker.isStarted)
        XCTAssertTrue(timerScheduler.latestTimer?.isInvalidated == true)
    }

    func testLockedCountdownBeepsAndStopsWhenTimeExpires() {
        accessibility.isTrustedValue = true
        controller.selectedDuration = 30
        controller.start()
        clock.advance(by: 3)
        timerScheduler.fireLatest()

        clock.advance(by: 30)
        timerScheduler.fireLatest()

        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(soundPlayer.playCallCount, 1)
        XCTAssertFalse(eventBlocker.isStarted)
    }
}

private final class FakeAccessibilityPermissionProvider: AccessibilityPermissionProviding {
    var isTrustedValue = false
    var requestAccessResult = false
    var requestAccessCallCount = 0

    var isTrusted: Bool {
        isTrustedValue
    }

    func requestAccess() -> Bool {
        requestAccessCallCount += 1
        isTrustedValue = requestAccessResult
        return requestAccessResult
    }
}

private final class FakeClock: ClockProviding {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}

private final class FakeTimerScheduler: CleaningTimerScheduling {
    private(set) var scheduleCallCount = 0
    private(set) var latestTimer: FakeTimer?

    func scheduleRepeating(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> CleaningTimer {
        scheduleCallCount += 1
        let timer = FakeTimer(action: action)
        latestTimer = timer
        return timer
    }

    func fireLatest() {
        latestTimer?.fire()
    }
}

private final class FakeTimer: CleaningTimer {
    private let action: @MainActor () -> Void
    private(set) var isInvalidated = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func invalidate() {
        isInvalidated = true
    }

    func fire() {
        guard !isInvalidated else { return }
        MainActor.assumeIsolated {
            action()
        }
    }
}

private final class FakeInputBlocker: InputBlocking {
    var startResult = true
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isStarted = false

    func start() -> Bool {
        startCallCount += 1
        isStarted = startResult
        return startResult
    }

    func stop() {
        stopCallCount += 1
        isStarted = false
    }
}

private final class FakeGestureBlocker: GestureBlocking {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var isStarted = false

    func start() {
        startCallCount += 1
        isStarted = true
    }

    func stop() {
        stopCallCount += 1
        isStarted = false
    }
}

private final class FakeSoundPlayer: AlertSoundPlaying {
    private(set) var playCallCount = 0

    func playFinishedSound() {
        playCallCount += 1
    }
}
