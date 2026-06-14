import ApplicationServices
import Foundation

final class EventTapInputBlocker: InputBlocking {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventTapState = EventTapState()

    func start() -> Bool {
        stop()

        let mask = Self.blockedEvents.reduce(CGEventMask(0)) { result, eventType in
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

    func stop() {
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

    nonisolated static let blockedEvents: Set<CGEventType> = [
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
        CGEventType(rawValue: 14)!,
        CGEventType(rawValue: 18)!,
        CGEventType(rawValue: 19)!,
        CGEventType(rawValue: 20)!,
        CGEventType(rawValue: 29)!,
        CGEventType(rawValue: 30)!,
        CGEventType(rawValue: 31)!,
        CGEventType(rawValue: 32)!,
    ]
}

private final class EventTapState {
    var tap: CFMachPort?
}
