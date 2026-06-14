import AppKit
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

@main
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
