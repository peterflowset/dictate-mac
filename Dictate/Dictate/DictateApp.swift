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
            MenuBarIconView(manager: appDelegate.dictateManager)
        }
        .menuBarExtraStyle(.window)

        Settings {
            EmptyView()
        }
    }
}

struct MenuBarIconView: View {
    @ObservedObject var manager: DictateManager

    var body: some View {
        Image(systemName: manager.statusIcon)
            .symbolRenderingMode(manager.isRecording ? .palette : .hierarchical)
            .foregroundStyle(manager.isRecording ? .red : .primary)
            .id("\(manager.statusIcon)-\(manager.isRecording)-\(manager.isProcessing)")
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
        let hotkeyPressed: Bool
        switch dictateManager.hotkey {
        case .leftOption:
            hotkeyPressed = event.modifierFlags.contains(.option) && event.keyCode == 58
        case .fn:
            hotkeyPressed = event.modifierFlags.contains(.function)
        }

        if hotkeyPressed && !dictateManager.isRecording && !dictateManager.isProcessing {
            dictateManager.startRecording()
        } else if !hotkeyPressed && dictateManager.isRecording {
            dictateManager.stopRecording()
        }
    }
}
