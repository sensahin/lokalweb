import Foundation
import Darwin

enum RuntimeError: LocalizedError {
    case missingRuntime(String)
    case invalidSiteRoot(String)
    case portInUse(Int)
    case startTimedOut(String)
    case stopTimedOut(String)
    case unsafeProcess(Int32)
    case invalidDatabaseName
    case databaseNotFound(String)
    case invalidImportFile(String)
    case httpsCertificateMissing
    case invalidWordPressTarget(String)
    case wordPressInstallFailed(String)
    case pluginDestinationExists(String)
    case unsafeSnapshot

    var errorDescription: String? {
        switch self {
        case .missingRuntime(let name): return "\(name) is not installed. Install the missing runtime first."
        case .invalidSiteRoot(let path): return "The site root does not exist or is not a directory: \(path)"
        case .portInUse(let port): return "Port \(port) is already in use. Stop the conflicting service or choose another Lokalweb port."
        case .startTimedOut(let service): return "\(service) did not become ready in time. Check its log for details."
        case .stopTimedOut(let service): return "\(service) did not stop in time. Its process was left intact."
        case .unsafeProcess(let pid): return "Refused to stop PID \(pid) because it could not be verified as a Lokalweb process."
        case .invalidDatabaseName: return "The database name must be 1–64 letters, numbers, or underscores."
        case .databaseNotFound(let name): return "Database \(name) does not exist. Create or import it before exporting."
        case .invalidImportFile(let path): return "The SQL import file does not exist or is not readable: \(path)"
        case .httpsCertificateMissing: return "HTTPS is enabled, but its trusted localhost certificate is missing. Prepare HTTPS in Settings first."
        case .invalidWordPressTarget(let message): return message
        case .wordPressInstallFailed(let message): return message
        case .pluginDestinationExists(let path): return "A plugin already exists at \(path). Lokalweb will not overwrite it."
        case .unsafeSnapshot: return "Refused to use a snapshot outside this site's Lokalweb snapshot directory."
        }
    }
}

struct DatabaseStatus: Equatable {
    let exists: Bool
    let tableCount: Int
}

struct PHPRuntimeDiagnostic: Equatable, Identifiable {
    var id: String { formula }
    let formula: String
    let installed: Bool
    let version: String?
    let missingRecommendedExtensions: [String]
}

final class RuntimeManager {
    private let paths: AppPaths
    private let runner = CommandRunner()
    private let discovery = RuntimeDiscovery()

    init(paths: AppPaths) {
        self.paths = paths
    }

    func recoverStaleState() {
        let pidFiles = [paths.nginxPID, paths.apachePID, paths.databasePID] + paths.phpPIDFiles
        for url in pidFiles {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if let pid = readPID(url), processExists(pid) { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func discover(configuration: RuntimeConfiguration) -> RuntimeBinaries {
        discovery.discover(configuration: configuration)
    }

    func phpRuntimeDiagnostics(sites: [Site], configuration: RuntimeConfiguration) -> [PHPRuntimeDiagnostic] {
        let recommended = Set(["curl", "dom", "fileinfo", "intl", "mbstring", "mysqli", "openssl", "xml", "zip"])
        return PHPRuntimePlan(sites: sites, configuration: configuration).instances.map { instance in
            var requested = configuration
            requested.phpFormula = instance.formula
            let binaries = discover(configuration: requested)
            guard let php = binaries.phpCLI else {
                return PHPRuntimeDiagnostic(
                    formula: instance.formula,
                    installed: false,
                    version: nil,
                    missingRecommendedExtensions: recommended.sorted()
                )
            }
            let version = try? runner.run(php, arguments: ["-r", "echo PHP_VERSION;"]).output
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let moduleOutput = (try? runner.run(php, arguments: ["-m"]).output) ?? ""
            let modules = Set(moduleOutput.split(whereSeparator: \.isNewline).map { $0.lowercased() })
            return PHPRuntimeDiagnostic(
                formula: instance.formula,
                installed: true,
                version: version,
                missingRecommendedExtensions: recommended.subtracting(modules).sorted()
            )
        }
    }

    func state(for service: ManagedService) -> ServiceState {
        if service == .php { return phpState() }
        let pidURL: URL
        switch service {
        case .webServer: pidURL = paths.nginxPID
        case .apache: pidURL = paths.apachePID
        case .php: return phpState()
        case .database: pidURL = paths.databasePID
        }
        guard let pid = readPID(pidURL), processExists(pid) else { return .stopped }
        return processIsOwned(pid) ? .running : .failed("PID file points to a process Lokalweb does not own.")
    }

    func installMissing(configuration: RuntimeConfiguration, sites: [Site]) throws -> String {
        let binaries = discover(configuration: configuration)
        guard let brew = binaries.brew else { throw RuntimeError.missingRuntime("Homebrew") }
        let phpFormulae = PHPRuntimePlan(sites: sites, configuration: configuration).instances.compactMap { instance in
            var requested = configuration
            requested.phpFormula = instance.formula
            return discover(configuration: requested).phpFPM == nil ? instance.formula : nil
        }
        var missingFormulae = binaries.missingFormulae + phpFormulae
        if binaries.apache == nil { missingFormulae.append("httpd") }
        let formulae = Array(Set(missingFormulae)).sorted()
        guard !formulae.isEmpty else { return "All runtimes are already installed." }
        return try runner.run(brew, arguments: ["install"] + formulae).output
    }

    func prepareHTTPS(configuration: RuntimeConfiguration) throws {
        let initialBinaries = discover(configuration: configuration)
        if initialBinaries.mkcert == nil {
            guard let brew = initialBinaries.brew else { throw RuntimeError.missingRuntime("Homebrew") }
            try runner.run(brew, arguments: ["install", "mkcert"])
        }
        let binaries = discover(configuration: configuration)
        guard let mkcert = binaries.mkcert else { throw RuntimeError.missingRuntime("mkcert") }
        try paths.prepare()
        try runner.run(mkcert, arguments: ["-install"])
        try runner.run(mkcert, arguments: [
            "-cert-file", paths.certificate.path,
            "-key-file", paths.certificateKey.path,
            "*.localhost", "localhost", "127.0.0.1", "::1"
        ])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.certificateKey.path)
    }

    func installWordPressTools(configuration: RuntimeConfiguration) throws {
        let binaries = discover(configuration: configuration)
        guard let brew = binaries.brew else { throw RuntimeError.missingRuntime("Homebrew") }
        if binaries.wpCLI == nil {
            try runner.run(brew, arguments: ["install", "wp-cli"])
        }
    }

    func startAll(sites: [Site], configuration: RuntimeConfiguration) throws {
        try configuration.validate(sites: sites)
        let binaries = discover(configuration: configuration)
        let phpPlan = PHPRuntimePlan(sites: sites, configuration: configuration)
        var missing = binaries.missingFormulae.filter { $0 != configuration.phpFormula }
        let phpBinaries: [(PHPRuntimeInstance, RuntimeBinaries)] = phpPlan.instances.map { instance in
            var requested = configuration
            requested.phpFormula = instance.formula
            return (instance, discover(configuration: requested))
        }
        missing.append(contentsOf: phpBinaries.compactMap { $0.1.phpFPM == nil ? $0.0.formula : nil })
        if sites.contains(where: { $0.webServer == .apache }), binaries.apache == nil {
            missing.append("httpd")
        }
        guard missing.isEmpty else {
            throw RuntimeError.missingRuntime(Array(Set(missing)).sorted().joined(separator: ", "))
        }
        for site in sites where !isDirectory(site.rootPath) {
            throw RuntimeError.invalidSiteRoot(site.rootPath)
        }
        if configuration.httpsEnabled,
           (!FileManager.default.fileExists(atPath: paths.certificate.path)
            || !FileManager.default.fileExists(atPath: paths.certificateKey.path)) {
            throw RuntimeError.httpsCertificateMissing
        }

        try paths.prepare()
        try ConfigurationGenerator(paths: paths).writeAll(
            sites: sites,
            configuration: configuration,
            binaries: binaries
        )
        do {
            try startDatabase(configuration: configuration, binaries: binaries)
            for (instance, instanceBinaries) in phpBinaries {
                try startPHP(instance: instance, binaries: instanceBinaries)
            }
            if sites.contains(where: { $0.webServer == .apache }) {
                try startApache(configuration: configuration, binaries: binaries)
            }
            try startNginx(configuration: configuration, binaries: binaries)
        } catch {
            try? stopNginx(binaries: binaries)
            try? stopApache(binaries: binaries)
            try? stopPHP()
            try? stopDatabase(binaries: binaries)
            throw error
        }
    }

    func stopAll(configuration: RuntimeConfiguration) throws {
        let binaries = discover(configuration: configuration)
        var errors: [Error] = []
        for operation in [
            { try self.stopNginx(binaries: binaries) },
            { try self.stopApache(binaries: binaries) },
            { try self.stopPHP() },
            { try self.stopDatabase(binaries: binaries) }
        ] {
            do { try operation() } catch { errors.append(error) }
        }
        if let first = errors.first { throw first }
    }

    func reloadWeb(sites: [Site], configuration: RuntimeConfiguration) throws {
        try configuration.validate(sites: sites)
        let binaries = discover(configuration: configuration)
        let needsApache = sites.contains(where: { $0.webServer == .apache })
        if needsApache, binaries.apache == nil {
            throw RuntimeError.missingRuntime("Apache (Homebrew httpd)")
        }
        try ConfigurationGenerator(paths: paths).writeAll(sites: sites, configuration: configuration, binaries: binaries)
        guard state(for: .webServer).isRunning, let nginx = binaries.nginx else { return }
        let apacheWasRunning = state(for: .apache).isRunning
        do {
            if needsApache {
                if apacheWasRunning {
                    try reloadApache(binaries: binaries)
                } else {
                    try startApache(configuration: configuration, binaries: binaries)
                }
            }
            try runner.run(nginx, arguments: ["-t", "-p", paths.root.path + "/", "-c", paths.nginxConfiguration.path])
            try stopNginx(binaries: binaries)
            try startNginx(configuration: configuration, binaries: binaries, checkPorts: false)
            if !needsApache, apacheWasRunning {
                try stopApache(binaries: binaries)
            }
        } catch {
            if needsApache, !apacheWasRunning {
                try? stopApache(binaries: binaries)
            }
            throw error
        }
    }

    func createDatabase(named name: String, configuration: RuntimeConfiguration) throws {
        let safeName = try validatedDatabaseName(name)
        let binaries = discover(configuration: configuration)
        guard let client = binaries.mariaDBClient else { throw RuntimeError.missingRuntime("MariaDB client") }
        try requireRunningDatabase()
        try runner.run(client, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--execute=CREATE DATABASE IF NOT EXISTS `\(safeName)` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        ])
    }

    func databaseStatus(named name: String, configuration: RuntimeConfiguration) throws -> DatabaseStatus {
        let safeName = try validatedDatabaseName(name)
        let binaries = discover(configuration: configuration)
        guard let client = binaries.mariaDBClient else { throw RuntimeError.missingRuntime("MariaDB client") }
        try requireRunningDatabase()
        let result = try runner.run(client, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--batch",
            "--skip-column-names",
            "--execute=SELECT EXISTS(SELECT 1 FROM information_schema.schemata WHERE schema_name='\(safeName)'), COUNT(*) FROM information_schema.tables WHERE table_schema='\(safeName)';"
        ])
        let values = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" })
        guard values.count >= 2, let exists = Int(values[0]), let tableCount = Int(values[1]) else {
            throw CommandError.launchFailed("MariaDB returned an unreadable database status.")
        }
        return DatabaseStatus(exists: exists == 1, tableCount: tableCount)
    }

    func importDatabase(named name: String, from inputURL: URL, configuration: RuntimeConfiguration) throws {
        let safeName = try validatedDatabaseName(name)
        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw RuntimeError.invalidImportFile(inputURL.path)
        }
        let binaries = discover(configuration: configuration)
        guard let client = binaries.mariaDBClient else { throw RuntimeError.missingRuntime("MariaDB client") }
        try requireRunningDatabase()
        try createDatabase(named: safeName, configuration: configuration)

        let clientArguments = [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--default-character-set=utf8mb4",
            safeName
        ]
        if inputURL.pathExtension.lowercased() == "gz" {
            try runner.runPipeline(
                firstExecutable: "/usr/bin/gzip",
                firstArguments: ["-dc", inputURL.path],
                secondExecutable: client,
                secondArguments: clientArguments
            )
        } else {
            try runner.run(client, arguments: clientArguments, readingInputFrom: inputURL)
        }
    }

    func exportDatabase(named name: String, to outputURL: URL, configuration: RuntimeConfiguration) throws {
        let safeName = try validatedDatabaseName(name)
        let binaries = discover(configuration: configuration)
        guard let dump = binaries.mariaDBDump else { throw RuntimeError.missingRuntime("MariaDB dump utility") }
        try requireRunningDatabase()
        guard try databaseStatus(named: safeName, configuration: configuration).exists else {
            throw RuntimeError.databaseNotFound(safeName)
        }
        try runner.run(dump, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--single-transaction",
            "--quick",
            "--routines",
            "--triggers",
            "--events",
            "--default-character-set=utf8mb4",
            safeName
        ], writingOutputTo: outputURL)
    }

    func snapshots(for site: Site) -> [DatabaseSnapshot] {
        let directory = paths.snapshotDirectory(for: site.id)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { $0.pathExtension.lowercased() == "sql" }.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return DatabaseSnapshot(
                fileURL: url,
                createdAt: values?.contentModificationDate ?? .distantPast,
                byteCount: Int64(values?.fileSize ?? 0)
            )
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func createSnapshot(for site: Site, configuration: RuntimeConfiguration) throws -> DatabaseSnapshot {
        let directory = paths.snapshotDirectory(for: site.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).sql"
        let url = directory.appendingPathComponent(name)
        try exportDatabase(named: site.databaseName, to: url, configuration: configuration)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return DatabaseSnapshot(
            fileURL: url,
            createdAt: values.contentModificationDate ?? Date(),
            byteCount: Int64(values.fileSize ?? 0)
        )
    }

    func restoreSnapshot(_ snapshot: DatabaseSnapshot, for site: Site, configuration: RuntimeConfiguration) throws {
        try validate(snapshot: snapshot, for: site)
        let safeName = try validatedDatabaseName(site.databaseName)
        let binaries = discover(configuration: configuration)
        guard let client = binaries.mariaDBClient else { throw RuntimeError.missingRuntime("MariaDB client") }
        try requireRunningDatabase()
        try runner.run(client, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--execute=DROP DATABASE IF EXISTS `\(safeName)`; CREATE DATABASE `\(safeName)` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
        ])
        try importDatabase(named: safeName, from: snapshot.fileURL, configuration: configuration)
    }

    func deleteSnapshot(_ snapshot: DatabaseSnapshot, for site: Site) throws {
        try validate(snapshot: snapshot, for: site)
        try FileManager.default.removeItem(at: snapshot.fileURL)
    }

    func linkPlugin(from sourceURL: URL, to site: Site) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeError.invalidWordPressTarget("Choose an existing plugin directory.")
        }
        let plugins = URL(fileURLWithPath: site.rootPath, isDirectory: true)
            .appendingPathComponent("wp-content/plugins", isDirectory: true)
        guard FileManager.default.fileExists(atPath: plugins.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeError.invalidWordPressTarget("This site does not contain wp-content/plugins.")
        }
        let destination = plugins.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw RuntimeError.pluginDestinationExists(destination.path)
        }
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: sourceURL.standardizedFileURL)
    }

    func installWordPress(
        site: Site,
        title: String,
        adminUser: String,
        adminPassword: String,
        adminEmail: String,
        configuration: RuntimeConfiguration
    ) throws {
        let root = URL(fileURLWithPath: site.rootPath, isDirectory: true)
        let workspace = try WordPressInstallationWorkspace(root: root)
        guard state(for: .database).isRunning, state(for: .php).isRunning, state(for: .webServer).isRunning else {
            throw RuntimeError.invalidWordPressTarget("Start all Lokalweb services before installing WordPress.")
        }
        let binaries = discover(configuration: configuration)
        guard let wp = binaries.wpCLI else { throw RuntimeError.missingRuntime("WP-CLI") }
        let siteFormula = site.phpFormula ?? configuration.phpFormula
        var phpConfiguration = configuration
        phpConfiguration.phpFormula = siteFormula
        guard let php = discover(configuration: phpConfiguration).phpCLI else {
            throw RuntimeError.missingRuntime(RuntimeConfiguration.phpLabel(for: siteFormula))
        }
        let initialDatabaseStatus = try databaseStatus(named: site.databaseName, configuration: configuration)
        guard !initialDatabaseStatus.exists || initialDatabaseStatus.tableCount == 0 else {
            throw RuntimeError.invalidWordPressTarget(
                "Database \(site.databaseName) already contains \(initialDatabaseStatus.tableCount) tables. Choose another site name or database."
            )
        }
        let databaseCreatedByInstaller = !initialDatabaseStatus.exists

        do {
            if databaseCreatedByInstaller {
                try createDatabase(named: site.databaseName, configuration: configuration)
            }
            try runWP(php: php, wp: wp, arguments: ["--path=\(site.rootPath)", "core", "download"])
            try runWP(php: php, wp: wp, arguments: [
                "--path=\(site.rootPath)", "config", "create",
                "--dbname=\(site.databaseName)", "--dbuser=root", "--dbpass=",
                "--dbhost=127.0.0.1:\(configuration.databasePort)", "--skip-check"
            ])
            guard let url = site.url(configuration: configuration)?.absoluteString else {
                throw RuntimeError.invalidWordPressTarget("The site's local URL is invalid.")
            }
            try runWP(php: php, wp: wp, arguments: [
                "--path=\(site.rootPath)", "core", "install",
                "--url=\(url)", "--title=\(title)", "--admin_user=\(adminUser)",
                "--admin_password=\(adminPassword)", "--admin_email=\(adminEmail)", "--skip-email"
            ])
        } catch {
            var cleanupIssues = workspace.rollbackGeneratedContents()
            if databaseCreatedByInstaller {
                do {
                    try dropDatabase(named: site.databaseName, configuration: configuration)
                } catch {
                    cleanupIssues.append("Could not remove database \(site.databaseName): \(error.localizedDescription)")
                }
            }
            guard cleanupIssues.isEmpty else {
                throw RuntimeError.wordPressInstallFailed(
                    "\(error.localizedDescription) Lokalweb also encountered cleanup problems: \(cleanupIssues.joined(separator: " "))"
                )
            }
            throw error
        }
    }

    func combinedLogs(maximumCharacters: Int = 80_000) -> String {
        let logFiles: [(String, URL)] = [
            (ManagedService.webServer.rawValue, paths.nginxLog),
            (ManagedService.apache.rawValue, paths.apacheLog),
            (ManagedService.database.rawValue, paths.databaseLog)
        ] + paths.phpLogFiles.map { ($0.deletingPathExtension().lastPathComponent, $0) }
        return logFiles.compactMap { label, url -> String? in
            guard FileManager.default.fileExists(atPath: url.path),
                  let value = try? String(contentsOf: url, encoding: .utf8),
                  !value.isEmpty else { return nil }
            return "── \(label) ──\n\(String(value.suffix(maximumCharacters / max(logFiles.count, 1))))"
        }.joined(separator: "\n\n")
    }

    func diagnosticReport(sites: [Site], configuration: RuntimeConfiguration) -> String {
        let diagnostics = phpRuntimeDiagnostics(sites: sites, configuration: configuration)
        let serviceLines = ManagedService.allCases.map { "\($0.rawValue): \(state(for: $0).label)" }
        let phpLines = diagnostics.map { diagnostic in
            let missing = diagnostic.missingRecommendedExtensions.isEmpty
                ? "none"
                : diagnostic.missingRecommendedExtensions.joined(separator: ", ")
            return "\(diagnostic.formula): \(diagnostic.version ?? "not installed"); missing common extensions: \(missing)"
        }
        let siteLines = sites.map { site in
            "\(site.name): \(site.slug).localhost; root=\(site.rootPath); database=\(site.databaseName); php=\(site.phpFormula ?? configuration.phpFormula); server=\(site.webServer.label)"
        }
        return """
        Lokalweb diagnostic report
        Generated: \(Date().formatted(.iso8601))
        App version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        Service state
        \(serviceLines.joined(separator: "\n"))

        Configuration
        HTTP: \(configuration.httpPort)
        HTTPS: \(configuration.httpsEnabled ? String(configuration.httpsPort) : "disabled")
        Apache backend: \(configuration.apachePort)
        MariaDB: \(configuration.databasePort)
        PHP base port: \(configuration.phpPort)
        App data: \(paths.root.path)
        Runtime data: \(paths.runtimeRoot.path)

        PHP runtimes
        \(phpLines.joined(separator: "\n"))

        Sites
        \(siteLines.isEmpty ? "none" : siteLines.joined(separator: "\n"))

        Recent logs
        \(combinedLogs(maximumCharacters: 40_000))
        """
    }

    private func startNginx(
        configuration: RuntimeConfiguration,
        binaries: RuntimeBinaries,
        checkPorts: Bool = true
    ) throws {
        if state(for: .webServer).isRunning { return }
        if checkPorts {
            try ensurePortAvailable(configuration.httpPort)
            if configuration.httpsEnabled { try ensurePortAvailable(configuration.httpsPort) }
        }
        guard let nginx = binaries.nginx else { throw RuntimeError.missingRuntime("nginx") }
        try runner.run(nginx, arguments: ["-t", "-p", paths.root.path + "/", "-c", paths.nginxConfiguration.path])
        try runner.run(nginx, arguments: ["-p", paths.root.path + "/", "-c", paths.nginxConfiguration.path])
        try waitUntilRunning(.webServer)
    }

    private func startApache(configuration: RuntimeConfiguration, binaries: RuntimeBinaries) throws {
        if state(for: .apache).isRunning { return }
        try ensurePortAvailable(configuration.apachePort)
        guard let apache = binaries.apache else {
            throw RuntimeError.missingRuntime("Apache (Homebrew httpd)")
        }
        try runner.run(apache, arguments: ["-t", "-f", paths.apacheConfiguration.path])
        try runner.run(apache, arguments: ["-f", paths.apacheConfiguration.path, "-k", "start"])
        try waitUntilRunning(.apache)
    }

    private func reloadApache(binaries: RuntimeBinaries) throws {
        guard let apache = binaries.apache else {
            throw RuntimeError.missingRuntime("Apache (Homebrew httpd)")
        }
        try runner.run(apache, arguments: ["-t", "-f", paths.apacheConfiguration.path])
        try runner.run(apache, arguments: ["-f", paths.apacheConfiguration.path, "-k", "graceful"])
    }

    private func startPHP(instance: PHPRuntimeInstance, binaries: RuntimeBinaries) throws {
        let pidURL = paths.phpPID(for: instance.formula)
        if let pid = readPID(pidURL), processExists(pid), processIsOwned(pid) { return }
        try ensurePortAvailable(instance.port)
        guard let phpFPM = binaries.phpFPM else { throw RuntimeError.missingRuntime("PHP-FPM") }
        let configurationURL = paths.phpConfiguration(for: instance.formula)
        try runner.run(phpFPM, arguments: ["--test", "--fpm-config", configurationURL.path])
        try runner.run(phpFPM, arguments: ["--fpm-config", configurationURL.path])
        try waitUntilProcessStarts(pidURL, service: RuntimeConfiguration.phpLabel(for: instance.formula))
    }

    private func startDatabase(configuration: RuntimeConfiguration, binaries: RuntimeBinaries) throws {
        if state(for: .database).isRunning { return }
        try ensurePortAvailable(configuration.databasePort)
        guard let server = binaries.mariaDBServer,
              let installer = binaries.mariaDBInstaller else {
            throw RuntimeError.missingRuntime("MariaDB")
        }
        if !FileManager.default.fileExists(atPath: paths.database.appendingPathComponent("mysql").path) {
            try runner.run(installer, arguments: [
                "--defaults-file=\(paths.databaseConfiguration.path)",
                "--auth-root-authentication-method=normal",
                "--skip-test-db"
            ])
        }
        try runner.launch(
            server,
            arguments: ["--defaults-file=\(paths.databaseConfiguration.path)"],
            outputURL: paths.databaseLog
        )
        try waitUntilDatabaseReady(binaries: binaries)
    }

    private func stopNginx(binaries: RuntimeBinaries) throws {
        guard state(for: .webServer).isRunning else { return }
        let pid = readPID(paths.nginxPID)
        guard let nginx = binaries.nginx else { throw RuntimeError.missingRuntime("nginx") }
        try runner.run(nginx, arguments: ["-p", paths.root.path + "/", "-c", paths.nginxConfiguration.path, "-s", "quit"])
        if let pid { try waitUntilProcessExits(pid, service: ManagedService.webServer.rawValue) }
    }

    private func stopApache(binaries: RuntimeBinaries) throws {
        guard state(for: .apache).isRunning else { return }
        let pid = readPID(paths.apachePID)
        if let apache = binaries.apache,
           FileManager.default.fileExists(atPath: paths.apacheConfiguration.path) {
            let result = try runner.run(
                apache,
                arguments: ["-f", paths.apacheConfiguration.path, "-k", "graceful-stop"],
                allowFailure: true
            )
            if result.succeeded {
                if let pid { try waitUntilProcessExits(pid, service: ManagedService.apache.rawValue) }
                return
            }
        }
        try stopUsingPID(paths.apachePID)
    }

    private func stopPHP() throws {
        let pidURLs = paths.phpPIDFiles
        let ports = pidURLs.compactMap(phpPort(forPIDFile:))
        var errors: [Error] = []
        for pidURL in pidURLs {
            do { try stopUsingPID(pidURL) } catch { errors.append(error) }
        }
        for port in ports {
            do { try waitUntilPortIsAvailable(port, service: ManagedService.php.rawValue) }
            catch { errors.append(error) }
        }
        if let first = errors.first { throw first }
    }

    private func stopDatabase(binaries: RuntimeBinaries) throws {
        guard state(for: .database).isRunning else { return }
        let pid = readPID(paths.databasePID)
        if let admin = binaries.mariaDBAdmin {
            let result = try runner.run(admin, arguments: [
                "--defaults-file=\(paths.databaseConfiguration.path)",
                "--user=root",
                "shutdown"
            ], allowFailure: true)
            if result.succeeded {
                if let pid { try waitUntilProcessExits(pid, service: ManagedService.database.rawValue) }
                return
            }
        }
        try stopUsingPID(paths.databasePID)
    }

    private func stopUsingPID(_ url: URL) throws {
        guard let pid = readPID(url), processExists(pid) else { return }
        guard processIsOwned(pid) else { throw RuntimeError.unsafeProcess(pid) }
        guard kill(pid, SIGTERM) == 0 else {
            throw CommandError.launchFailed("Could not stop PID \(pid).")
        }
        try waitUntilProcessExits(pid, service: "PID \(pid)")
    }

    private func waitUntilRunning(_ service: ManagedService, attempts: Int = 40) throws {
        for _ in 0..<attempts {
            if state(for: service).isRunning { return }
            usleep(100_000)
        }
        throw RuntimeError.startTimedOut(service.rawValue)
    }

    private func waitUntilProcessStarts(_ pidURL: URL, service: String, attempts: Int = 40) throws {
        for _ in 0..<attempts {
            if let pid = readPID(pidURL), processExists(pid), processIsOwned(pid) { return }
            usleep(100_000)
        }
        throw RuntimeError.startTimedOut(service)
    }

    private func waitUntilDatabaseReady(binaries: RuntimeBinaries) throws {
        guard let admin = binaries.mariaDBAdmin else {
            throw RuntimeError.missingRuntime("MariaDB admin client")
        }
        for _ in 0..<120 {
            if state(for: .database).isRunning,
               let result = try? runner.run(admin, arguments: [
                   "--defaults-file=\(paths.databaseConfiguration.path)",
                   "--user=root",
                   "ping"
               ], allowFailure: true),
               result.succeeded {
                return
            }
            usleep(100_000)
        }
        throw RuntimeError.startTimedOut(ManagedService.database.rawValue)
    }

    private func waitUntilProcessExits(_ pid: Int32, service: String) throws {
        for _ in 0..<80 {
            if !processExists(pid) { return }
            usleep(100_000)
        }
        throw RuntimeError.stopTimedOut(service)
    }

    private func waitUntilPortIsAvailable(_ port: Int, service: String) throws {
        for _ in 0..<80 {
            if isPortAvailable(port) { return }
            usleep(100_000)
        }
        throw RuntimeError.stopTimedOut(service)
    }

    private func ensurePortAvailable(_ port: Int) throws {
        if !isPortAvailable(port) { throw RuntimeError.portInUse(port) }
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return true }
        defer { close(socketFD) }
        var reuseAddress: Int32 = 1
        setsockopt(
            socketFD,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func phpPort(forPIDFile pidURL: URL) -> Int? {
        let configurationURL = paths.configuration.appendingPathComponent(
            pidURL.deletingPathExtension().lastPathComponent + ".conf"
        )
        guard let contents = try? String(contentsOf: configurationURL, encoding: .utf8) else { return nil }
        let prefix = "listen = 127.0.0.1:"
        guard let line = contents.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Int(line.dropFirst(prefix.count))
    }

    private func validatedDatabaseName(_ name: String) throws -> String {
        let pattern = #"^[A-Za-z0-9_]{1,64}$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw RuntimeError.invalidDatabaseName
        }
        return name
    }

    private func validate(snapshot: DatabaseSnapshot, for site: Site) throws {
        let parent = paths.snapshotDirectory(for: site.id)
            .resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let candidate = snapshot.fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard candidate.hasPrefix(parent),
              snapshot.fileURL.pathExtension.lowercased() == "sql",
              FileManager.default.isReadableFile(atPath: snapshot.fileURL.path) else {
            throw RuntimeError.unsafeSnapshot
        }
    }

    private func runWP(php: String, wp: String, arguments: [String]) throws {
        try runner.run(php, arguments: WordPressCLIInvocation.phpArguments(wpPath: wp, command: arguments), environment: [
            "WP_CLI_PHP": php,
            "WP_CLI_DISABLE_AUTO_CHECK_UPDATE": "1"
        ])
    }

    private func dropDatabase(named name: String, configuration: RuntimeConfiguration) throws {
        let safeName = try validatedDatabaseName(name)
        let binaries = discover(configuration: configuration)
        guard let client = binaries.mariaDBClient else { throw RuntimeError.missingRuntime("MariaDB client") }
        try requireRunningDatabase()
        try runner.run(client, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--execute=DROP DATABASE IF EXISTS `\(safeName)`;"
        ])
    }

    private func requireRunningDatabase() throws {
        guard state(for: .database).isRunning else {
            throw RuntimeError.missingRuntime("A running MariaDB service")
        }
    }

    private func readPID(_ url: URL) -> Int32? {
        guard FileManager.default.fileExists(atPath: url.path),
              let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(value) else { return nil }
        return pid
    }

    private func processExists(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func processIsOwned(_ pid: Int32) -> Bool {
        guard let result = try? runner.run("/bin/ps", arguments: ["-p", String(pid), "-o", "command="], allowFailure: true),
              result.succeeded else { return false }
        return result.output.contains(paths.root.path)
            || result.output.contains(paths.runtimeRoot.path)
            || result.output.contains("Lokalweb")
    }

    private func phpState() -> ServiceState {
        let runningPIDs = paths.phpPIDFiles.compactMap(readPID).filter(processExists)
        guard !runningPIDs.isEmpty else { return .stopped }
        return runningPIDs.allSatisfy(processIsOwned)
            ? .running
            : .failed("A PHP-FPM PID file points to a process Lokalweb does not own.")
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
