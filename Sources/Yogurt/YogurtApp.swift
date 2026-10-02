import SwiftUI
import AppKit

@main
struct YogurtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel.shared

    init() {
        Fonts.registerBundled()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                // Finder "Open With" / double-click. SwiftUI consumes the open
                // event, so AppDelegate.application(_:open:) never sees the URLs.
                .onOpenURL { model.open($0) }
                // Reuse the existing window instead of spawning a new one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    model.openPanel()
                }
                .keyboardShortcut("o")
            }
            CommandMenu("Notes") {
                Button("Insert Timestamp") {
                    model.insertTimestamp()
                }
                .keyboardShortcut("t")
                .disabled(model.mediaURL == nil)
            }
            CommandGroup(after: .toolbar) {
                Button(model.showMeter ? "Hide Audio Meter" : "Show Audio Meter") {
                    model.toggleMeter()
                }
                .keyboardShortcut("l")
                .disabled(model.mediaURL == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed so the window fronts properly when launched via `swift run`
        // (outside a .app bundle).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.notes.flushNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
