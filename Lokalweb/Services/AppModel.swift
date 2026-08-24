import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sites: [Site] = []
    @Published private(set) var serviceStates: [ManagedService: ServiceState] = [:]
    @Published private(set) var binaries = RuntimeBinaries()
    @Published private(set) var databaseStatuses: [UUID: DatabaseStatus] = [:]
    @Published private(set) var phpDiagnostics: [PHPRuntimeDiagnostic] = []
    @Published private(set) var snapshots: [UUID: [DatabaseSnapshot]] = [:]
    @Published var configuration: RuntimeConfiguration
    @Published var isBusy = false
    @Published var activity = "Ready"
    @Published var lastError: String?
    @Published var logs = "No Lokalweb logs yet."

    let paths: AppPaths
    private let persistence: Persistence
    private let runtime: RuntimeManager

    init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.persistence = Persistence(paths: paths)
        self.runtime = RuntimeManager(paths: paths)
        self.configuration = (try? persistence.loadRuntimeConfiguration()) ?? .default
        self.sites = (try? persistence.loadSites()) ?? []
        self.runtime.recoverStaleState()
        refresh()
    }

    var allRunning: Bool {
        requiredServices.allSatisfy { serviceStates[$0]?.isRunning == true }
    }

    var anyRunning: Bool {
        ManagedService.allCases.contains { serviceStates[$0]?.isRunning == true }
    }

    var needsAttention: Bool {
        if lastError != nil { return true }
        return requiredServices.contains { service in
            switch serviceStates[service] {
            case .failed, .unavailable: return true
            default: return false
            }
        }
    }

    var menuBarStatus: MenuBarStatus {
        MenuBarStatus.resolve(
            isBusy: isBusy,
            needsAttention: needsAttention,
            allRunning: allRunning,
            anyRunning: anyRunning
        )
    }

    var phpRuntimePlan: PHPRuntimePlan {
        PHPRuntimePlan(sites: sites, configuration: configuration)
    }

    var missingRuntimeFormulae: [String] {
        var missing = binaries.missingFormulae + phpDiagnostics.filter { !$0.installed }.map(\.formula)
        if binaries.apache == nil { missing.append("httpd") }
        return Array(Set(missing)).sorted()
    }

    private var requiredServices: [ManagedService] {
        var required: [ManagedService] = [.webServer, .php, .database]
        if sites.contains(where: { $0.webServer == .apache }) { required.append(.apache) }
        return required
    }

    func refresh() {
        binaries = runtime.discover(configuration: configuration)
        phpDiagnostics = runtime.phpRuntimeDiagnostics(sites: sites, configuration: configuration)
        refreshServiceStates(force: true)
    }

    func refreshServiceStates(force: Bool = false) {
        if isBusy && !force { return }
        for service in ManagedService.allCases {
            if binaryPath(for: service) == nil {
                serviceStates[service] = .unavailable(service.rawValue)
            } else {
                serviceStates[service] = runtime.state(for: service)
            }
        }
        let currentLogs = runtime.combinedLogs()
        logs = currentLogs.isEmpty ? "No Lokalweb logs yet." : currentLogs
    }

    func startAll() {
        perform("Starting Lokalweb") {
            try self.runtime.startAll(sites: self.sites, configuration: self.configuration)
            return "All services are running"
        }
    }

    func stopAll() {
        perform("Stopping Lokalweb") {
            try self.runtime.stopAll(configuration: self.configuration)
            return "All Lokalweb services stopped"
        }
    }

    func installMissingRuntimes() {
        perform("Installing runtimes with Homebrew") {
            _ = try self.runtime.installMissing(configuration: self.configuration, sites: self.sites)
            return "Runtime installation finished"
        }
    }

    func prepareHTTPS() {
        perform("Preparing trusted localhost HTTPS") {
            try self.runtime.prepareHTTPS(configuration: self.configuration)
            return "Trusted localhost HTTPS is ready"
        }
    }

    func installWordPressTools() {
        perform("Installing WP-CLI with Homebrew") {
            try self.runtime.installWordPressTools(configuration: self.configuration)
            return "WP-CLI is ready"
        }
    }

    func inspection(for site: Site) -> SiteInspection {
        SiteInspector().inspect(site: site, configuration: configuration)
    }

    @discardableResult
    func addSite(name: String, rootPath: String) -> Bool {
        lastError = nil
        do {
            let site = try proposedSite(name: name, rootPath: rootPath)
            return commitSites(sites + [site], message: "Added \(site.name)")
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateSite(_ site: Site) -> Bool {
        lastError = nil
        var normalized = site
        normalized.name = site.name.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.slug = site.slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalized.rootPath = URL(fileURLWithPath: site.rootPath).standardizedFileURL.path
        normalized.databaseName = site.databaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try SiteValidator().validate(normalized, among: sites)
            guard let index = sites.firstIndex(where: { $0.id == normalized.id }) else { return false }
            var updatedSites = sites
            updatedSites[index] = normalized
            let saved = commitSites(updatedSites, message: "Updated \(normalized.name)")
            if saved { databaseStatuses[normalized.id] = nil }
            return saved
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func removeSite(_ site: Site) {
        let updatedSites = sites.filter { $0.id != site.id }
        if commitSites(updatedSites, message: "Removed \(site.name) from Lokalweb") {
            databaseStatuses[site.id] = nil
        }
    }

    func createDatabase(for site: Site) {
        perform("Creating database \(site.databaseName)", operation: {
            try self.runtime.createDatabase(named: site.databaseName, configuration: self.configuration)
            return try self.runtime.databaseStatus(named: site.databaseName, configuration: self.configuration)
        }, onSuccess: { status in
            self.databaseStatuses[site.id] = status
            return "Database \(site.databaseName) is ready"
        })
    }

    func refreshDatabaseStatus(for site: Site) {
        guard serviceStates[.database]?.isRunning == true else {
            databaseStatuses[site.id] = nil
            return
        }
        perform("Inspecting database \(site.databaseName)", operation: {
            try self.runtime.databaseStatus(named: site.databaseName, configuration: self.configuration)
        }, onSuccess: { status in
            self.databaseStatuses[site.id] = status
            return status.exists
                ? "Database \(site.databaseName) has \(status.tableCount) tables"
                : "Database \(site.databaseName) has not been created"
        })
    }

    func importDatabase(for site: Site, from inputURL: URL) {
        perform("Importing \(inputURL.lastPathComponent)", operation: {
            try self.runtime.importDatabase(named: site.databaseName, from: inputURL, configuration: self.configuration)
            return try self.runtime.databaseStatus(named: site.databaseName, configuration: self.configuration)
        }, onSuccess: { status in
            self.databaseStatuses[site.id] = status
            return "Imported \(inputURL.lastPathComponent) into \(site.databaseName)"
        })
    }

    func exportDatabase(for site: Site, to outputURL: URL) {
        perform("Exporting database \(site.databaseName)", operation: {
            try self.runtime.exportDatabase(named: site.databaseName, to: outputURL, configuration: self.configuration)
        }, onSuccess: { _ in
            "Exported \(site.databaseName) to \(outputURL.lastPathComponent)"
        })
    }

    func refreshSnapshots(for site: Site) {
        snapshots[site.id] = runtime.snapshots(for: site)
    }

    func createSnapshot(for site: Site) {
        perform("Creating database snapshot", operation: {
            try self.runtime.createSnapshot(for: site, configuration: self.configuration)
        }, onSuccess: { _ in
            self.snapshots[site.id] = self.runtime.snapshots(for: site)
            return "Created a snapshot of \(site.databaseName)"
        })
    }

    func restoreSnapshot(_ snapshot: DatabaseSnapshot, for site: Site) {
        perform("Restoring database snapshot", operation: {
            try self.runtime.restoreSnapshot(snapshot, for: site, configuration: self.configuration)
            return try self.runtime.databaseStatus(named: site.databaseName, configuration: self.configuration)
        }, onSuccess: { status in
            self.databaseStatuses[site.id] = status
            return "Restored \(site.databaseName) from \(snapshot.displayName)"
        })
    }

    func deleteSnapshot(_ snapshot: DatabaseSnapshot, for site: Site) {
        perform("Deleting database snapshot", operation: {
            try self.runtime.deleteSnapshot(snapshot, for: site)
        }, onSuccess: { _ in
            self.snapshots[site.id] = self.runtime.snapshots(for: site)
            return "Deleted database snapshot"
        })
    }

    func linkPlugin(from sourceURL: URL, to site: Site) {
        perform("Linking plugin folder") {
            try self.runtime.linkPlugin(from: sourceURL, to: site)
            return "Linked \(sourceURL.lastPathComponent) into \(site.name)"
        }
    }

    func createWordPressSite(
        name: String,
        rootPath: String,
        adminUser: String,
        adminPassword: String,
        adminEmail: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard validateWordPressCredentials(
            title: name,
            adminUser: adminUser,
            adminPassword: adminPassword,
            adminEmail: adminEmail
        ) else {
            completion(false)
            return
        }
        do {
            let site = try proposedSite(name: name, rootPath: rootPath)
            installWordPress(
                site: site,
                title: name.trimmingCharacters(in: .whitespacesAndNewlines),
                adminUser: adminUser,
                adminPassword: adminPassword,
                adminEmail: adminEmail,
                registerAfterSuccess: true,
                completion: completion
            )
        } catch {
            lastError = error.localizedDescription
            completion(false)
        }
    }

    func completeWordPressInstallation(
        for site: Site,
        title: String,
        adminUser: String,
        adminPassword: String,
        adminEmail: String,
        completion: @escaping (Bool) -> Void
    ) {
        guard sites.contains(where: { $0.id == site.id }) else {
            lastError = "This site is no longer registered in Lokalweb."
            completion(false)
            return
        }
        guard validateWordPressCredentials(
            title: title,
            adminUser: adminUser,
            adminPassword: adminPassword,
            adminEmail: adminEmail
        ) else {
            completion(false)
            return
        }
        installWordPress(
            site: site,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            adminUser: adminUser,
            adminPassword: adminPassword,
            adminEmail: adminEmail,
            registerAfterSuccess: false,
            completion: completion
        )
    }

    func saveConfiguration() {
        guard !anyRunning else {
            lastError = "Stop Lokalweb before changing runtime ports or PHP version."
            return
        }
        do {
            configuration.normalize()
            try configuration.validate(sites: sites)
            try persistence.saveRuntimeConfiguration(configuration)
            refresh()
            activity = "Runtime settings saved"
        } catch {
            lastError = error.localizedDescription
        }
    }

    func open(_ site: Site) {
        guard let url = site.url(configuration: configuration) else { return }
        NSWorkspace.shared.open(url)
    }

    func reveal(_ site: Site) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: site.rootPath)])
    }

    func revealLogs() {
        NSWorkspace.shared.open(paths.logs)
    }

    func exportDiagnostics(to outputURL: URL) {
        perform("Exporting diagnostic report") {
            let report = self.runtime.diagnosticReport(sites: self.sites, configuration: self.configuration)
            try report.write(to: outputURL, atomically: true, encoding: .utf8)
            return "Exported diagnostic report"
        }
    }

    func stopForTermination(force: Bool? = nil) {
        guard force ?? configuration.stopServicesOnQuit, anyRunning else { return }
        try? runtime.stopAll(configuration: configuration)
    }

    func openAdmin(_ site: Site) {
        guard let base = site.url(configuration: configuration),
              let url = URL(string: "wp-admin/", relativeTo: base) else { return }
        NSWorkspace.shared.open(url)
    }

    @discardableResult
    private func commitSites(_ updatedSites: [Site], message: String) -> Bool {
        let previousSites = sites
        let webWasRunning = serviceStates[.webServer]?.isRunning == true
        do {
            if webWasRunning {
                try runtime.reloadWeb(sites: updatedSites, configuration: configuration)
            }
            try persistence.saveSites(updatedSites)
            sites = updatedSites
            activity = message
            refresh()
            return true
        } catch {
            let primaryError = error.localizedDescription
            if webWasRunning {
                do {
                    if runtime.state(for: .webServer).isRunning {
                        try runtime.reloadWeb(sites: previousSites, configuration: configuration)
                    } else {
                        try runtime.startAll(sites: previousSites, configuration: configuration)
                    }
                    lastError = primaryError
                } catch {
                    lastError = "\(primaryError) Lokalweb also could not restore the previous web configuration: \(error.localizedDescription)"
                }
            } else {
                lastError = primaryError
            }
            return false
        }
    }

    private func perform(_ pendingMessage: String, operation: @escaping () throws -> String) {
        perform(pendingMessage, operation: operation, onSuccess: { $0 })
    }

    private func perform<Value>(
        _ pendingMessage: String,
        operation: @escaping () throws -> Value,
        onSuccess: @escaping (Value) -> String
    ) {
        guard !isBusy else { return }
        isBusy = true
        activity = pendingMessage
        lastError = nil
        Task {
            do {
                let value = try await Task.detached(priority: .userInitiated) { try operation() }.value
                activity = onSuccess(value)
            } catch {
                lastError = error.localizedDescription
                activity = "Action failed"
            }
            isBusy = false
            refresh()
        }
    }

    private func proposedSite(name: String, rootPath: String) throws -> Site {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseSlug = Site.makeSlug(from: trimmedName)
        var slug = baseSlug
        var suffix = 2
        while sites.contains(where: { $0.slug == slug }) {
            slug = "\(baseSlug)-\(suffix)"
            suffix += 1
        }
        let site = Site(
            name: trimmedName,
            slug: slug,
            rootPath: URL(fileURLWithPath: rootPath).standardizedFileURL.path
        )
        try SiteValidator().validate(site, among: sites)
        return site
    }

    private func validateWordPressCredentials(
        title: String,
        adminUser: String,
        adminPassword: String,
        adminEmail: String
    ) -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              adminUser.range(of: #"^[A-Za-z0-9_.-]{1,60}$"#, options: .regularExpression) != nil,
              adminPassword.count >= 8,
              adminEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
            lastError = "Enter a site title, a valid admin username and email, and an admin password of at least 8 characters."
            return false
        }
        return true
    }

    private func installWordPress(
        site: Site,
        title: String,
        adminUser: String,
        adminPassword: String,
        adminEmail: String,
        registerAfterSuccess: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard !isBusy else {
            lastError = "Wait for the current Lokalweb action to finish."
            completion(false)
            return
        }
        isBusy = true
        activity = "Installing WordPress in \(site.name)"
        lastError = nil
        let runtime = self.runtime
        let currentConfiguration = configuration
        Task {
            var succeeded = false
            do {
                let status = try await Task.detached(priority: .userInitiated) {
                    try runtime.installWordPress(
                        site: site,
                        title: title,
                        adminUser: adminUser,
                        adminPassword: adminPassword,
                        adminEmail: adminEmail,
                        configuration: currentConfiguration
                    )
                    return try runtime.databaseStatus(
                        named: site.databaseName,
                        configuration: currentConfiguration
                    )
                }.value

                if registerAfterSuccess {
                    succeeded = commitSites(sites + [site], message: "Installed WordPress in \(site.name)")
                } else {
                    succeeded = true
                }
                if succeeded {
                    databaseStatuses[site.id] = status
                    activity = "WordPress is ready at \(site.url(configuration: configuration)?.absoluteString ?? site.name)"
                }
            } catch {
                lastError = error.localizedDescription
                if let runtimeError = error as? RuntimeError,
                   case .wordPressInstallFailed = runtimeError {
                    activity = "WordPress installation failed; cleanup needs attention"
                } else {
                    activity = "WordPress installation failed; generated files were cleaned up"
                }
            }
            isBusy = false
            refresh()
            completion(succeeded)
        }
    }

    private func binaryPath(for service: ManagedService) -> String? {
        switch service {
        case .webServer: return binaries.nginx
        case .apache: return binaries.apache
        case .php: return binaries.phpFPM
        case .database: return binaries.mariaDBServer
        }
    }
}
