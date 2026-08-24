import AppKit
import Combine
import SwiftUI

struct LokalwebMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        Text(model.menuBarStatus.label)
        Text(model.activity)

        Divider()

        Button {
            model.anyRunning ? model.stopAll() : model.startAll()
        } label: {
            Label(
                model.anyRunning ? "Stop All" : "Start All",
                systemImage: model.anyRunning ? "stop.fill" : "play.fill"
            )
        }
        .disabled(model.isBusy)

        Button {
            model.refresh()
        } label: {
            Label("Refresh Status", systemImage: "arrow.clockwise")
        }
        .disabled(model.isBusy)

        if !model.sites.isEmpty {
            Menu("Sites") {
                ForEach(model.sites) { site in
                    Menu(site.name) {
                        Button("Open Site") { model.open(site) }
                            .disabled(!model.allRunning)
                        if model.inspection(for: site).platform == .wordpress {
                            Button("Open WordPress Admin") { model.openAdmin(site) }
                                .disabled(!model.allRunning)
                        }
                    }
                }
            }
        }

        Button {
            navigation.requestNewWordPress()
            presentDashboard()
        } label: {
            Label("New WordPress Site…", systemImage: "plus.circle")
        }
        .disabled(!model.allRunning || model.isBusy)

        Divider()

        if model.needsAttention {
            Button("Show Attention…") { presentDashboard() }
        }

        Button("Open Lokalweb Dashboard") { presentDashboard() }

        Divider()

        Button("Quit Lokalweb") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func presentDashboard() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "dashboard")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

struct LokalwebMenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    let appDelegate: LokalwebAppDelegate
    private let statusTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Image(systemName: model.menuBarStatus.systemImage)
            .accessibilityLabel("Lokalweb — \(model.menuBarStatus.label)")
            .onAppear {
                appDelegate.connect(model: model)
            }
            .onReceive(statusTimer) { _ in
                model.refreshServiceStates()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showLokalwebDashboard)) { _ in
                presentDashboard()
            }
            .onChange(of: model.menuBarStatus) { previous, current in
                if current == .attention && previous != .attention {
                    presentDashboard()
                }
            }
    }

    private func presentDashboard() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "dashboard")
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

struct DashboardWindowAccessor: NSViewRepresentable {
    let resolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> DashboardWindowProbe {
        let view = DashboardWindowProbe()
        view.resolve = resolve
        return view
    }

    func updateNSView(_ nsView: DashboardWindowProbe, context: Context) {
        nsView.resolve = resolve
        nsView.reportWindow()
    }
}

final class DashboardWindowProbe: NSView {
    var resolve: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        guard let window else { return }
        resolve?(window)
    }
}

extension Notification.Name {
    static let showLokalwebDashboard = Notification.Name("com.lokalweb.show-dashboard")
}
