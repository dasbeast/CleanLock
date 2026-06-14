import Foundation
import IOKit.hid

final class TrackpadGestureBlocker: GestureBlocking {
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
                if let value {
                    existing[key] = value
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

        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let currentServices = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient]) ?? []
        let gestureKeys = Set(Self.disabledGestureValues.keys)

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
