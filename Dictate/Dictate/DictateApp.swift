import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct DictateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.dictateManager)
        } label: {
            Image(systemName: appDelegate.dictateManager.statusIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let dictateManager = DictateManager()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermissions()
        setupGlobalHotkey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private nonisolated func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func setupGlobalHotkey() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let leftOptionPressed = event.modifierFlags.contains(.option) && event.keyCode == 58

        if leftOptionPressed && !dictateManager.isRecording && !dictateManager.isProcessing {
            dictateManager.startRecording()
        } else if !event.modifierFlags.contains(.option) && dictateManager.isRecording {
            dictateManager.stopRecording()
        }
    }
}
