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

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        AppModel.shared.open(url)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.notes.flushNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
