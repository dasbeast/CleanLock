import AppKit
import ApplicationServices
import IOKit.hid
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: CleaningController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        controller?.refreshAccessibilityStatus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

struct WipeLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = CleaningController()

    var body: some Scene {
        Window("WipeLock", id: "main") {
            ContentView()
                .environmentObject(controller)
                .frame(minWidth: 380)
                .onAppear {
                    controller.refreshAccessibilityStatus()
                    appDelegate.controller = controller
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

struct ContentView: View {
    @EnvironmentObject private var controller: CleaningController
    @State private var warningFlash = false

    private var isWarning: Bool {
        controller.phase == .locked && controller.secondsRemaining <= 3
    }

    var body: some View {
        VStack(spacing: 22) {
            header

            statusPanel

            if controller.phase == .idle {
                durationPicker
            }

            controls

            permissionRow
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: controller.secondsRemaining) { _ in
            guard isWarning else {
                warningFlash = false
                return
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                warningFlash.toggle()
            }
        }
        .onChange(of: controller.phase) { newPhase in
            if newPhase != .locked { warningFlash = false }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("WipeLock")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Pause keyboard, media keys, clicks, scrolling, and trackpad gestures while you clean.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 8) {
            Text(controller.statusTitle)
                .font(.title3.weight(.semibold))

            Text(controller.statusDetail)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if controller.phase != .idle {
                Text(controller.displayTime)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isWarning ? Color.red : .primary)
                    .animation(.easeInOut(duration: 0.25), value: isWarning)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .padding(18)
        .background(panelColor)
        .animation(.easeInOut(duration: 0.25), value: warningFlash)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var durationPicker: some View {
        Picker("Cleaning time", selection: Binding(
            get: { controller.selectedDuration },
            set: { newValue in
                DispatchQueue.main.async {
                    controller.selectedDuration = newValue
                }
            }
        )) {
            ForEach(CleaningController.cleaningDurations, id: \.self) { duration in
                Text(durationLabel(duration)).tag(duration)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Cleaning time")
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                controller.start()
            } label: {
                Text(controller.primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!controller.canStart)

            if controller.phase == .arming {
                Button("Cancel") {
                    controller.stop()
                }
                .controlSize(.large)
            }
        }
    }

    private var permissionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle()
                .fill(controller.accessibilityTrusted ? Color.green : Color.orange)
                .frame(width: 9, height: 9)

            Text(controller.accessibilityTrusted ? "Accessibility permission is enabled." : "Accessibility permission is needed before WipeLock can block input.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            if !controller.accessibilityTrusted {
                Button("Allow") {
                    controller.requestAccessibilityAccess()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var panelColor: Color {
        switch controller.phase {
        case .idle:
            return Color(nsColor: .controlBackgroundColor)
        case .arming:
            return Color.yellow.opacity(0.18)
        case .locked:
            if isWarning {
                return warningFlash ? Color.red.opacity(0.28) : Color.red.opacity(0.10)
            }
            return Color.teal.opacity(0.16)
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}

@MainActor
final class CleaningController: ObservableObject {
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
    @Published var lockFailureMessage: String?

    init() {
        TrackpadGestureBlocker.recoverIfNeeded()
    }

    private var timer: Timer?
    private var timerStartDate: Date?
    private var timerDuration = 0
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventTapState = EventTapState()
    private let trackpadBlocker = HIDTrackpadBlocker()
    private let gestureBlocker = TrackpadGestureBlocker()

    var canStart: Bool {
        phase == .idle && accessibilityTrusted
    }

    var primaryButtonTitle: String {
        accessibilityTrusted ? "Start Cleaning Mode" : "Permission Needed"
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
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func requestAccessibilityAccess() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        accessibilityTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    func start() {
        refreshAccessibilityStatus()

        guard accessibilityTrusted, phase == .idle else {
            requestAccessibilityAccess()
            return
        }

        lockFailureMessage = nil
        phase = .arming
        timerDuration = 3
        timerStartDate = Date()
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
        disableEventTap()
        secondsRemaining = 0
        phase = .idle
        if clearFailureMessage {
            lockFailureMessage = nil
        }
        refreshAccessibilityStatus()
    }

    private func tickArmingTimer() {
        guard let start = timerStartDate else { return }
        let remaining = timerDuration - Int(Date().timeIntervalSince(start))
        guard remaining > 0 else {
            beginLockedMode()
            return
        }
        secondsRemaining = remaining
    }

    private func beginLockedMode() {
        guard enableEventTap() else {
            lockFailureMessage = "WipeLock could not start the keyboard blocker. Check Accessibility permission, then try again."
            stop(clearFailureMessage: false)
            return
        }

        // Disable system gestures (Mission Control, Spaces, etc.) via HID service properties.
        gestureBlocker.start()

        // Best-effort: seize the raw HID device to prevent any process from receiving touch data.
        // Seizure may fail on some systems; we continue into locked mode regardless.
        let _ = trackpadBlocker.start()

        phase = .locked
        timerDuration = selectedDuration
        timerStartDate = Date()
        secondsRemaining = selectedDuration
        scheduleTimer { [weak self] in
            self?.tickLockedTimer()
        }
    }

    private func tickLockedTimer() {
        guard let start = timerStartDate else { return }
        let remaining = timerDuration - Int(Date().timeIntervalSince(start))
        guard remaining > 0 else {
            NSSound.beep()
            stop()
            return
        }
        secondsRemaining = remaining
    }

    private func scheduleTimer(_ action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                action()
            }
        }
    }

    private func enableEventTap() -> Bool {
        disableEventTap()

        let mask = CleaningController.blockedEvents.reduce(CGEventMask(0)) { result, eventType in
            result | (CGEventMask(1) << CGEventMask(eventType.rawValue))
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let state = userInfo.map {
                Unmanaged<EventTapState>
                    .fromOpaque($0)
                    .takeUnretainedValue()
            }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = state?.tap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            return nil
        }

        guard let tap = CGEvent.tapCreate(
            tap: CGEventTapLocation(rawValue: 0)!,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(eventTapState).toOpaque())
        ) else {
            return false
        }

        eventTapState.tap = tap
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func disableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        runLoopSource = nil
        eventTap = nil
        eventTapState.tap = nil
    }

    nonisolated private static let blockedEvents: Set<CGEventType> = [
        .leftMouseDown,
        .leftMouseUp,
        .rightMouseDown,
        .rightMouseUp,
        .mouseMoved,
        .leftMouseDragged,
        .rightMouseDragged,
        .keyDown,
        .keyUp,
        .flagsChanged,
        .scrollWheel,
        .tabletPointer,
        .tabletProximity,
        .otherMouseDown,
        .otherMouseUp,
        .otherMouseDragged,
        // Media, brightness, Mission Control, and similar hardware keys arrive
        // as the legacy NX_SYSDEFINED event, which CoreGraphics exposes by raw value.
        CGEventType(rawValue: 14)!,
        // Trackpad gesture event types (correspond to NSEventType raw values).
        // These block app-level pinch, zoom, rotate, and swipe gesture events.
        CGEventType(rawValue: 18)!,  // rotate
        CGEventType(rawValue: 19)!,  // beginGesture
        CGEventType(rawValue: 20)!,  // endGesture
        CGEventType(rawValue: 29)!,  // gesture (general / magnify subtype)
        CGEventType(rawValue: 30)!,  // magnify
        CGEventType(rawValue: 31)!,  // swipe (app-level back/forward)
        CGEventType(rawValue: 32)!,  // smartMagnify (double-tap zoom)
    ]
}

private final class EventTapState {
    var tap: CFMachPort?
}

private final class HIDTrackpadBlocker {
    private var manager: IOHIDManager?

    func start() -> Bool {
        stop()

        let newManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(newManager, Self.matchingDictionaries as CFArray)
        IOHIDManagerScheduleWithRunLoop(newManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(newManager, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(newManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }

        guard let devices = IOHIDManagerCopyDevices(newManager), CFSetGetCount(devices) > 0 else {
            IOHIDManagerClose(newManager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(newManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            return false
        }

        manager = newManager
        return true
    }

    func stop() {
        guard let manager else {
            return
        }

        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        self.manager = nil
    }

    private static let matchingDictionaries: [[String: Int]] = [
        [
            kIOHIDDeviceUsagePageKey: Int(kHIDPage_Digitizer),
            kIOHIDDeviceUsageKey: Int(kHIDUsage_Dig_TouchPad)
        ],
        [
            // Apple internal trackpads expose their gesture stream through the
            // top-case vendor device rather than the generic touchpad usage.
            kIOHIDDeviceUsagePageKey: 0xFF00,
            kIOHIDDeviceUsageKey: 0x0B
        ]
    ]
}

private final class TrackpadGestureBlocker {
    private struct PreferenceSnapshot {
        let domain: CFString
        let values: [String: CFPropertyList?]
    }

    private struct ServiceSnapshot {
        let service: IOHIDServiceClient
        let properties: [String: Any]
    }

    private var preferenceSnapshots: [PreferenceSnapshot] = []
    private var serviceSnapshots: [ServiceSnapshot] = []

    func start() {
        stop()
        saveAndDisablePreferenceDomains()
        saveAndDisableLiveHIDServices()
    }

    func stop() {
        restoreLiveHIDServices()
        restorePreferenceDomains()
    }

    private static let snapshotDefaultsKey = "WipeLock.GesturePreferenceSnapshot"

    static func recoverIfNeeded() {
        guard let entries = UserDefaults.standard.array(forKey: snapshotDefaultsKey) as? [[String: Any]] else {
            return
        }
        for entry in entries {
            guard let domainStr = entry["domain"] as? String else { continue }
            let domain = domainStr as CFString
            let existing = entry["existing"] as? [String: Any] ?? [:]
            let missing = entry["missing"] as? [String] ?? []
            for (key, value) in existing {
                CFPreferencesSetAppValue(key as CFString, value as AnyObject, domain)
            }
            for key in missing {
                CFPreferencesSetAppValue(key as CFString, nil, domain)
            }
            CFPreferencesAppSynchronize(domain)
        }
        UserDefaults.standard.removeObject(forKey: snapshotDefaultsKey)
    }

    private func persistSnapshot() {
        let entries: [[String: Any]] = preferenceSnapshots.map { snapshot in
            var existing: [String: Any] = [:]
            var missing: [String] = []
            for (key, value) in snapshot.values {
                if let v = value {
                    existing[key] = v
                } else {
                    missing.append(key)
                }
            }
            return ["domain": snapshot.domain as String, "existing": existing, "missing": missing]
        }
        UserDefaults.standard.set(entries, forKey: Self.snapshotDefaultsKey)
    }

    private func clearPersistedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.snapshotDefaultsKey)
    }

    private func saveAndDisablePreferenceDomains() {
        preferenceSnapshots = Self.preferenceDomains.map { domain in
            let existingValues = Dictionary(uniqueKeysWithValues: Self.disabledGestureValues.keys.map { key in
                let value = CFPreferencesCopyAppValue(key as CFString, domain)
                return (key, value)
            })

            for (key, value) in Self.disabledGestureValues {
                CFPreferencesSetAppValue(key as CFString, value, domain)
            }
            CFPreferencesAppSynchronize(domain)

            return PreferenceSnapshot(domain: domain, values: existingValues)
        }
        persistSnapshot()
    }

    private func restorePreferenceDomains() {
        guard !preferenceSnapshots.isEmpty else {
            return
        }

        for snapshot in preferenceSnapshots {
            for (key, value) in snapshot.values {
                CFPreferencesSetAppValue(key as CFString, value, snapshot.domain)
            }
            CFPreferencesAppSynchronize(snapshot.domain)
        }

        preferenceSnapshots = []
        clearPersistedSnapshot()
    }

    private func saveAndDisableLiveHIDServices() {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return
        }

        for service in services {
            guard
                let properties = IOHIDServiceClientCopyProperty(service, "HIDEventServiceProperties" as CFString) as? [String: Any],
                properties.keys.contains(where: Self.disabledGestureValues.keys.contains)
            else {
                continue
            }

            serviceSnapshots.append(ServiceSnapshot(service: service, properties: properties))

            var disabledProperties = properties
            for (key, value) in Self.disabledGestureValues {
                disabledProperties[key] = value
            }

            IOHIDServiceClientSetProperty(
                service,
                "HIDEventServiceProperties" as CFString,
                disabledProperties as CFDictionary
            )
        }
    }

    private func restoreLiveHIDServices() {
        guard !serviceSnapshots.isEmpty else { return }
        defer { serviceSnapshots = [] }

        // Get fresh service references — the ones captured at session start may be
        // stale after a long session, causing silent failure when writing back.
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let currentServices = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
        let gestureKeys = Set(Self.disabledGestureValues.keys)

        // Collect the original gesture values across all saved snapshots.
        var originalValues: [String: Any] = [:]
        for snapshot in serviceSnapshots {
            for key in gestureKeys where originalValues[key] == nil {
                if let value = snapshot.properties[key] {
                    originalValues[key] = value
                }
            }
        }

        for service in currentServices {
            guard
                var props = IOHIDServiceClientCopyProperty(service, "HIDEventServiceProperties" as CFString) as? [String: Any],
                props.keys.contains(where: gestureKeys.contains)
            else { continue }

            for key in gestureKeys {
                if let original = originalValues[key] {
                    props[key] = original
                } else {
                    // Key wasn't present before we set it — remove it entirely.
                    props.removeValue(forKey: key)
                }
            }

            IOHIDServiceClientSetProperty(service, "HIDEventServiceProperties" as CFString, props as CFDictionary)
        }
    }

    private static let preferenceDomains: [CFString] = [
        "com.apple.AppleMultitouchTrackpad" as CFString,
        "com.apple.driver.AppleBluetoothMultitouch.trackpad" as CFString
    ]

    private static let disabledGestureValues: [String: CFPropertyList] = [
        "TrackpadThreeFingerHorizSwipeGesture": 0 as CFNumber,
        "TrackpadThreeFingerVertSwipeGesture": 0 as CFNumber,
        "TrackpadFourFingerHorizSwipeGesture": 0 as CFNumber,
        "TrackpadFourFingerVertSwipeGesture": 0 as CFNumber,
        "TrackpadTwoFingerFromRightEdgeSwipeGesture": 0 as CFNumber,
        "TrackpadFiveFingerPinchGesture": 0 as CFNumber,
        "TrackpadFourFingerPinchGesture": 0 as CFNumber,
        "TrackpadThreeFingerTapGesture": 0 as CFNumber,
        "TrackpadTwoFingerDoubleTapGesture": 0 as CFNumber,
        "MouseTwoFingerHorizSwipeGesture": 0 as CFNumber,
        "MouseTwoFingerDoubleTapGesture": 0 as CFNumber,
        "MouseOneFingerDoubleTapGesture": 0 as CFNumber,
        "TrackpadPinch": false as CFBoolean,
        "TrackpadRotate": false as CFBoolean,
        "TrackpadHorizScroll": false as CFBoolean,
        "TrackpadMomentumScroll": false as CFBoolean
    ]
}

WipeLockApp.main()
