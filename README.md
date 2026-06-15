# CleanLock

CleanLock is a tiny macOS utility for wiping down a Mac without accidentally typing, clicking, scrolling, or triggering common trackpad gestures.

## Build

```sh
./build.sh
```

The app bundle is created at:

```text
.build/CleanLock.app
```

## Run

```sh
open .build/CleanLock.app
```

## Test

```sh
xcodebuild -project CleanLock.xcodeproj -scheme CleanLock -configuration Debug test
```

## Xcode

Open the project in Xcode:

```sh
open CleanLock.xcodeproj
```

Select the **CleanLock** scheme, then build or run it from Xcode.

## App Icon

The app icon is the Icon Composer package at `Assets/IconComposer/app icon lock.icon`.
It is added directly to the Xcode target's Resources build phase so Xcode can render the app icon at build time.

On first launch, click **Allow Input Blocking** in CleanLock and grant Input Monitoring or Accessibility permission in macOS System Settings. Relaunch CleanLock after granting permission if macOS does not update the permission immediately.

## How It Works

CleanLock uses a macOS HID event tap to swallow keyboard, mouse, scroll wheel, and tablet-style input events during a timed cleaning session. Sessions begin with a 3-second grace countdown and automatically end when the timer reaches zero.

macOS does not expose every private multi-touch gesture to ordinary apps, so this blocks the normal event stream that apps receive and many trackpad gestures that arrive as scroll or pointer events. System-level gestures may still be handled by macOS before an app can intercept them.
