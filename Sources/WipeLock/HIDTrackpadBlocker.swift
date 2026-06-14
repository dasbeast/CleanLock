import Foundation
import IOKit.hid

final class HIDTrackpadBlocker: InputBlocking {
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
            kIOHIDDeviceUsagePageKey: 0xFF00,
            kIOHIDDeviceUsageKey: 0x0B
        ]
    ]
}
