import AppKit
import SwiftUI

@main
struct LokalwebApp: App {
    @NSApplicationDelegateAdaptor(LokalwebAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var navigation = AppNavigation()

    var body: some Scene {
        Window("Lokalweb", id: "dashboard") {
            RootView()
                .environmentObject(model)
                .environmentObject(navigation)
                .frame(minWidth: 980, minHeight: 650)
                .background {
                    DashboardWindowAccessor { window in
                        appDelegate.registerDashboardWindow(window, model: model)
                    }
                }
                .alert(
                    "Lokalweb needs attention",
                    isPresented: Binding(
                        get: { model.lastError != nil },
                        set: { if !$0 { model.lastError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { model.lastError = nil }
                } message: {
                    Text(model.lastError ?? "Unknown error")
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Status") { model.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            LokalwebMenuBarView()
                .environmentObject(model)
                .environmentObject(navigation)
        } label: {
            LokalwebMenuBarLabel(appDelegate: appDelegate)
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
    }
}
