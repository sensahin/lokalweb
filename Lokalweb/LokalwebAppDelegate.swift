import AppKit

@MainActor
final class LokalwebAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private weak var dashboardWindow: NSWindow?
    private var hasAppliedLaunchPolicy = false
    private var stopServicesForTermination: Bool?
    private static let dashboardLaunchKey = "hasPresentedDashboardOnLaunch"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func connect(model: AppModel) {
        self.model = model
    }

    func registerDashboardWindow(_ window: NSWindow, model: AppModel) {
        self.model = model
        dashboardWindow = window
        window.identifier = NSUserInterfaceItemIdentifier("lokalweb.dashboard")
        NSApplication.shared.setActivationPolicy(.regular)

        guard !hasAppliedLaunchPolicy else { return }
        hasAppliedLaunchPolicy = true
        let environment = ProcessInfo.processInfo.environment
        guard Self.shouldApplyDashboardLaunchPolicy(environment: environment) else { return }

        let defaults = UserDefaults.standard
        let hasLaunchedBefore = defaults.bool(forKey: Self.dashboardLaunchKey)
        defaults.set(true, forKey: Self.dashboardLaunchKey)
        guard !Self.shouldKeepDashboardVisibleOnLaunch(
            hasLaunchedBefore: hasLaunchedBefore,
            needsAttention: model.needsAttention,
            environment: environment
        ) else { return }

        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.dashboardWindow === window else { return }
            window.close()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            NotificationCenter.default.post(name: .showLokalwebDashboard, object: nil)
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.shouldStopServicesOnTermination(environment: ProcessInfo.processInfo.environment),
              let model else {
            return .terminateNow
        }
        guard !model.isBusy else {
            let alert = NSAlert()
            alert.messageText = "Lokalweb is finishing an action"
            alert.informativeText = "Wait for the current action to finish before quitting so its files and services are left in a consistent state."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return .terminateCancel
        }
        guard model.anyRunning else {
            stopServicesForTermination = false
            return .terminateNow
        }

        let stopByDefault = model.configuration.stopServicesOnQuit
        let alert = NSAlert()
        alert.messageText = "Quit Lokalweb?"
        alert.informativeText = stopByDefault
            ? "Your current setting stops Lokalweb-owned services when the app quits."
            : "Your current setting leaves Lokalweb-owned services running when the app quits."
        alert.addButton(withTitle: stopByDefault ? "Stop Services and Quit" : "Keep Services Running and Quit")
        alert.addButton(withTitle: stopByDefault ? "Keep Services Running and Quit" : "Stop Services and Quit")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            stopServicesForTermination = stopByDefault
            return .terminateNow
        case .alertSecondButtonReturn:
            stopServicesForTermination = !stopByDefault
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard Self.shouldStopServicesOnTermination(environment: ProcessInfo.processInfo.environment) else { return }
        model?.stopForTermination(force: stopServicesForTermination)
    }

    static func shouldStopServicesOnTermination(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }

    static func shouldApplyDashboardLaunchPolicy(environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }

    static func shouldKeepDashboardVisibleOnLaunch(
        hasLaunchedBefore: Bool,
        needsAttention: Bool,
        environment: [String: String]
    ) -> Bool {
        guard shouldApplyDashboardLaunchPolicy(environment: environment) else { return true }
        return !hasLaunchedBefore || needsAttention
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === dashboardWindow else { return }
        dashboardWindow = nil
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
