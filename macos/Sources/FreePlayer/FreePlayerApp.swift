import SwiftUI
import AppKit

@main
struct FreePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var eventMonitor: Any?
    private var backgroundActivity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        AppModel.shared.start()
        installShortcutMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        AppModel.shared.onTerminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Attach this delegate to the SwiftUI-hosted window.
    func configure(window: NSWindow) {
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Theme.background)
        window.minSize = NSSize(width: 960, height: 600)
    }

    // Close-to-tray: closing hides the window and keeps background playback.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let trayEnabled = Database.shared.getBoolSetting("tray_enabled", fallback: true)
        if trayEnabled {
            sender.orderOut(nil)
            setBackgroundPlayback(true)
            TrayController.shared.showHiddenNotification()
            return false
        }
        NSApp.terminate(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        setBackgroundPlayback(false)
    }

    private func setBackgroundPlayback(_ enabled: Bool) {
        if enabled && backgroundActivity == nil {
            backgroundActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiatedAllowingIdleSystemSleep],
                                                                      reason: "Background audio playback")
        } else if !enabled {
            if let act = backgroundActivity {
                ProcessInfo.processInfo.endActivity(act)
                backgroundActivity = nil
            }
        }
    }

    // ── Global keyboard shortcuts (Space / V / Esc) ──
    private func installShortcutMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil else { return event }
            let model = AppModel.shared
            // Don't hijack keys while editing text or activating a focused button
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSButton {
                return event
            }
            guard let chars = event.charactersIgnoringModifiers else { return event }
            switch chars {
            case " ":
                model.togglePlayPause()
                return nil
            case "v", "V":
                let modes: [VisualizerMode] = [.waveform, .spectrogram, .off]
                if event.modifierFlags.contains(.shift) {
                    if let idx = modes.firstIndex(of: model.visualizerMode) {
                        model.visualizerMode = modes[(idx + 1) % modes.count]
                    }
                } else {
                    model.visualizerMode = model.visualizerMode == .off ? .waveform : .off
                }
                return nil
            case "\u{1b}": // Esc
                if model.immersivePresented {
                    model.immersivePresented = false
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }
}
