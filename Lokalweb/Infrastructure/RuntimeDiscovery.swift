import Foundation

struct RuntimeBinaries: Equatable {
    var brew: String?
    var nginx: String?
    var apache: String?
    var phpFPM: String?
    var phpCLI: String?
    var mariaDBServer: String?
    var mariaDBClient: String?
    var mariaDBAdmin: String?
    var mariaDBDump: String?
    var mariaDBInstaller: String?
    var mariaDBPrefix: String?
    var mkcert: String?
    var wpCLI: String?
    var nginxConfigurationDirectory: String?
    var apachePrefix: String?
    var apacheModuleDirectory: String?
    var apacheMimeTypes: String?
    var selectedPHPFormula = "php@8.3"

    var missingFormulae: [String] {
        var values: [String] = []
        if nginx == nil { values.append("nginx") }
        if phpFPM == nil { values.append(selectedPHPFormula) }
        if mariaDBServer == nil { values.append("mariadb") }
        return values
    }

    var isComplete: Bool { missingFormulae.isEmpty }
}

struct RuntimeDiscovery {
    private let fileManager = FileManager.default
    private let runner = CommandRunner()

    func discover(configuration: RuntimeConfiguration) -> RuntimeBinaries {
        let brew = firstExecutable(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
        let brewPrefix = brew.flatMap { try? runner.run($0, arguments: ["--prefix"]).output.trimmingCharacters(in: .whitespacesAndNewlines) }
        let phpFormula = resolveFormula(configuration.phpFormula, brew: brew)
        let nginxFormula = resolveFormula("nginx", brew: brew)
        let apacheFormula = resolveFormula("httpd", brew: brew)
        let mariaDBFormula = resolveFormula("mariadb", brew: brew)
        let wpCLIFormula = resolveFormula("wp-cli", brew: brew)
        let apache = firstExecutable([apacheFormula.map { "\($0)/bin/httpd" }].compactMap { $0 })

        return RuntimeBinaries(
            brew: brew,
            nginx: firstExecutable([nginxFormula.map { "\($0)/bin/nginx" }, brewPrefix.map { "\($0)/bin/nginx" }].compactMap { $0 }),
            apache: apache,
            phpFPM: firstExecutable([phpFormula.map { "\($0)/sbin/php-fpm" }].compactMap { $0 }),
            phpCLI: firstExecutable([phpFormula.map { "\($0)/bin/php" }].compactMap { $0 }),
            mariaDBServer: firstExecutable([
                mariaDBFormula.map { "\($0)/bin/mariadbd" },
                mariaDBFormula.map { "\($0)/bin/mysqld" }
            ].compactMap { $0 }),
            mariaDBClient: firstExecutable([mariaDBFormula.map { "\($0)/bin/mariadb" }].compactMap { $0 }),
            mariaDBAdmin: firstExecutable([mariaDBFormula.map { "\($0)/bin/mariadb-admin" }].compactMap { $0 }),
            mariaDBDump: firstExecutable([mariaDBFormula.map { "\($0)/bin/mariadb-dump" }].compactMap { $0 }),
            mariaDBInstaller: firstExecutable([
                mariaDBFormula.map { "\($0)/bin/mariadb-install-db" },
                mariaDBFormula.map { "\($0)/scripts/mariadb-install-db" }
            ].compactMap { $0 }),
            mariaDBPrefix: mariaDBFormula,
            mkcert: firstExecutable([brewPrefix.map { "\($0)/bin/mkcert" }].compactMap { $0 }),
            wpCLI: firstExecutable([
                wpCLIFormula.map { "\($0)/bin/wp" },
                brewPrefix.map { "\($0)/bin/wp" }
            ].compactMap { $0 }),
            nginxConfigurationDirectory: brewPrefix.map { "\($0)/etc/nginx" },
            apachePrefix: apache == nil ? nil : apacheFormula,
            apacheModuleDirectory: apacheFormula.flatMap { prefix in
                let path = "\(prefix)/lib/httpd/modules"
                return fileManager.fileExists(atPath: path) ? path : nil
            },
            apacheMimeTypes: apacheFormula.flatMap { prefix in
                let candidates = ["\(prefix)/conf/mime.types", "\(brewPrefix ?? "")/etc/httpd/mime.types"]
                return candidates.first(where: { fileManager.fileExists(atPath: $0) })
            },
            selectedPHPFormula: configuration.phpFormula
        )
    }

    private func resolveFormula(_ formula: String, brew: String?) -> String? {
        guard let brew else { return nil }
        let result = try? runner.run(brew, arguments: ["--prefix", formula], allowFailure: true)
        guard result?.succeeded == true else { return nil }
        let value = result?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func firstExecutable(_ paths: [String]) -> String? {
        paths.first { fileManager.isExecutableFile(atPath: $0) }
    }
}
