import Foundation

struct AppPaths {
    let root: URL
    let runtimeRoot: URL

    init(root: URL? = nil, runtimeRoot: URL? = nil) {
        if let root {
            self.root = root
            self.runtimeRoot = runtimeRoot ?? root
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.root = applicationSupport.appendingPathComponent("Lokalweb", isDirectory: true)
            self.runtimeRoot = runtimeRoot ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".lokalweb/runtime", isDirectory: true)
        }
    }

    var configuration: URL { runtimeRoot.appendingPathComponent("config", isDirectory: true) }
    var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    var run: URL { runtimeRoot.appendingPathComponent("run", isDirectory: true) }
    var database: URL { runtimeRoot.appendingPathComponent("database", isDirectory: true) }
    var landing: URL { root.appendingPathComponent("landing", isDirectory: true) }
    var certificates: URL { runtimeRoot.appendingPathComponent("certificates", isDirectory: true) }
    var snapshots: URL { root.appendingPathComponent("snapshots", isDirectory: true) }
    var sitesJSON: URL { root.appendingPathComponent("sites.json") }
    var runtimeJSON: URL { root.appendingPathComponent("runtime.json") }
    var nginxConfiguration: URL { configuration.appendingPathComponent("nginx.conf") }
    var apacheConfiguration: URL { configuration.appendingPathComponent("httpd.conf") }
    var phpConfiguration: URL { phpConfiguration(for: "php@8.3") }
    var databaseConfiguration: URL { configuration.appendingPathComponent("my.cnf") }
    var nginxPID: URL { run.appendingPathComponent("nginx.pid") }
    var apachePID: URL { run.appendingPathComponent("httpd.pid") }
    var phpPID: URL { phpPID(for: "php@8.3") }
    var databasePID: URL { run.appendingPathComponent("mariadb.pid") }
    var databaseSocket: URL { run.appendingPathComponent("mariadb.sock") }
    var certificate: URL { certificates.appendingPathComponent("localhost.pem") }
    var certificateKey: URL { certificates.appendingPathComponent("localhost-key.pem") }
    var nginxLog: URL { logs.appendingPathComponent("nginx-error.log") }
    var accessLog: URL { logs.appendingPathComponent("nginx-access.log") }
    var apacheLog: URL { logs.appendingPathComponent("apache-error.log") }
    var apacheAccessLog: URL { logs.appendingPathComponent("apache-access.log") }
    var phpLog: URL { phpLog(for: "php@8.3") }
    var databaseLog: URL { logs.appendingPathComponent("mariadb.log") }

    func phpConfiguration(for formula: String) -> URL {
        configuration.appendingPathComponent("php-fpm-\(phpKey(formula)).conf")
    }

    func phpPID(for formula: String) -> URL {
        run.appendingPathComponent("php-fpm-\(phpKey(formula)).pid")
    }

    func phpLog(for formula: String) -> URL {
        logs.appendingPathComponent("php-fpm-\(phpKey(formula)).log")
    }

    var phpPIDFiles: [URL] {
        matchingFiles(in: run, prefix: "php-fpm-", suffix: ".pid")
    }

    var phpLogFiles: [URL] {
        matchingFiles(in: logs, prefix: "php-fpm-", suffix: ".log")
    }

    func snapshotDirectory(for siteID: UUID) -> URL {
        snapshots.appendingPathComponent(siteID.uuidString.lowercased(), isDirectory: true)
    }

    func prepare() throws {
        for directory in [root, runtimeRoot, configuration, logs, run, database, landing, certificates, snapshots] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func phpKey(_ formula: String) -> String {
        formula.replacingOccurrences(of: "@", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    private func matchingFiles(in directory: URL, prefix: String, suffix: String) -> [URL] {
        let values = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return values.filter {
            $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix)
        }
    }
}
