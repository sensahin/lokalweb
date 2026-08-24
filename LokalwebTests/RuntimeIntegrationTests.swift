import XCTest
@testable import Lokalweb

final class RuntimeIntegrationTests: XCTestCase {
    func testFullPHPAndDatabaseStack() async throws {
        let temporaryRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("lw-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let siteRoot = temporaryRoot.appendingPathComponent("site", isDirectory: true)
        let configuration = RuntimeConfiguration(
            httpPort: 18_090,
            phpPort: 19_083,
            databasePort: 13_307,
            phpFormula: "php@8.3"
        )
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)
        try """
        <?php
        $db = new mysqli('127.0.0.1', 'root', '', 'lokalweb_integration', \(configuration.databasePort));
        if ($db->connect_error) { http_response_code(500); exit($db->connect_error); }
        $db->query('CREATE TABLE IF NOT EXISTS migration_probe (id INT PRIMARY KEY, value VARCHAR(64) NOT NULL)');
        $db->query("REPLACE INTO migration_probe (id, value) VALUES (1, 'phase-one-ready')");
        echo 'lokalweb:' . PHP_VERSION . ':' . $db->server_info;
        """
            .write(to: siteRoot.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)

        let paths = AppPaths(root: temporaryRoot.appendingPathComponent("runtime", isDirectory: true))
        let manager = RuntimeManager(paths: paths)
        let site = Site(
            name: "Integration",
            slug: "integration",
            rootPath: siteRoot.path,
            databaseName: "lokalweb_integration"
        )

        let binaries = manager.discover(configuration: configuration)
        guard binaries.isComplete else {
            throw XCTSkip("Missing local runtimes: \(binaries.missingFormulae.joined(separator: ", "))")
        }

        defer {
            try? manager.stopAll(configuration: configuration)
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        do {
            try manager.startAll(sites: [site], configuration: configuration)
        } catch {
            XCTFail("Stack start failed: \(error.localizedDescription)\n\(manager.combinedLogs())")
            throw error
        }
        try manager.createDatabase(named: "lokalweb_integration", configuration: configuration)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(configuration.httpPort)")!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("integration.localhost", forHTTPHeaderField: "Host")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(body.hasPrefix("lokalweb:8.3"))
        XCTAssertTrue(body.contains("MariaDB"))

        let exportURL = temporaryRoot.appendingPathComponent("migration.sql")
        try manager.exportDatabase(named: "lokalweb_integration", to: exportURL, configuration: configuration)
        XCTAssertGreaterThan((try Data(contentsOf: exportURL)).count, 100)

        try manager.importDatabase(named: "lokalweb_imported", from: exportURL, configuration: configuration)
        let importedStatus = try manager.databaseStatus(named: "lokalweb_imported", configuration: configuration)
        XCTAssertTrue(importedStatus.exists)
        XCTAssertGreaterThanOrEqual(importedStatus.tableCount, 1)

        let compressedURL = temporaryRoot.appendingPathComponent("migration.sql.gz")
        try CommandRunner().run("/usr/bin/gzip", arguments: ["-c", exportURL.path], writingOutputTo: compressedURL)
        try manager.importDatabase(named: "lokalweb_imported_gzip", from: compressedURL, configuration: configuration)

        guard let client = binaries.mariaDBClient else {
            XCTFail("MariaDB client disappeared during the integration test")
            return
        }

        let snapshot: DatabaseSnapshot
        do {
            snapshot = try manager.createSnapshot(for: site, configuration: configuration)
        } catch {
            XCTFail("Snapshot creation failed: \(error.localizedDescription)")
            throw error
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.fileURL.path))
        try CommandRunner().run(client, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "lokalweb_integration",
            "--execute=UPDATE migration_probe SET value='changed-after-snapshot' WHERE id=1;"
        ])
        do {
            try manager.restoreSnapshot(snapshot, for: site, configuration: configuration)
        } catch {
            XCTFail("Snapshot restore failed: \(error.localizedDescription)")
            throw error
        }
        let restored = try CommandRunner().run(client, arguments: [
            "--defaults-file=\(paths.databaseConfiguration.path)",
            "--user=root",
            "--batch",
            "--skip-column-names",
            "lokalweb_integration",
            "--execute=SELECT value FROM migration_probe WHERE id=1;"
        ])
        XCTAssertEqual(restored.output.trimmingCharacters(in: .whitespacesAndNewlines), "phase-one-ready")
        try manager.deleteSnapshot(snapshot, for: site)
        XCTAssertTrue(manager.snapshots(for: site).isEmpty)

        for database in ["lokalweb_imported", "lokalweb_imported_gzip"] {
            let query = try CommandRunner().run(client, arguments: [
                "--defaults-file=\(paths.databaseConfiguration.path)",
                "--user=root",
                "--batch",
                "--skip-column-names",
                database,
                "--execute=SELECT value FROM migration_probe WHERE id=1;"
            ])
            XCTAssertEqual(query.output.trimmingCharacters(in: .whitespacesAndNewlines), "phase-one-ready")
        }

        if binaries.wpCLI != nil {
            let wordPressRoot = temporaryRoot.appendingPathComponent("fresh-wordpress", isDirectory: true)
            try FileManager.default.createDirectory(at: wordPressRoot, withIntermediateDirectories: true)
            let wordPressSite = Site(
                name: "Fresh WordPress",
                slug: "fresh-wordpress",
                rootPath: wordPressRoot.path,
                databaseName: "lokalweb_fresh_wordpress"
            )
            do {
                try manager.installWordPress(
                    site: wordPressSite,
                    title: "Lokalweb Integration",
                    adminUser: "lokalweb_admin",
                    adminPassword: "Lokalweb-Test-2026!",
                    adminEmail: "lokalweb@example.test",
                    configuration: configuration
                )
            } catch {
                XCTFail("Fresh WordPress installation failed: \(error.localizedDescription)")
                throw error
            }
            XCTAssertTrue(FileManager.default.fileExists(atPath: wordPressRoot.appendingPathComponent("index.php").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: wordPressRoot.appendingPathComponent("wp-config.php").path))
            let wordPressStatus = try manager.databaseStatus(
                named: wordPressSite.databaseName,
                configuration: configuration
            )
            XCTAssertGreaterThan(wordPressStatus.tableCount, 5)

            try manager.reloadWeb(sites: [site, wordPressSite], configuration: configuration)
            let wordPressStatusCode = try CommandRunner().run("/usr/bin/curl", arguments: [
                "--silent",
                "--show-error",
                "--location",
                "--max-time", "10",
                "--resolve", "fresh-wordpress.localhost:\(configuration.httpPort):127.0.0.1",
                "--output", "/dev/null",
                "--write-out", "%{http_code}",
                "http://fresh-wordpress.localhost:\(configuration.httpPort)/"
            ])
            XCTAssertEqual(wordPressStatusCode.output, "200")
        }

        try manager.stopAll(configuration: configuration)
        for service in ManagedService.allCases {
            XCTAssertEqual(manager.state(for: service), .stopped)
        }
    }

    func testMixedNginxAndApacheSitesCanSwitchWhileRunning() async throws {
        let temporaryRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("lw-servers-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let nginxRoot = temporaryRoot.appendingPathComponent("nginx-site", isDirectory: true)
        let apacheRoot = temporaryRoot.appendingPathComponent("apache-site", isDirectory: true)
        let configuration = RuntimeConfiguration(
            httpPort: 18_091,
            phpPort: 19_086,
            apachePort: 10_181,
            databasePort: 13_308,
            phpFormula: "php@8.3"
        )
        try FileManager.default.createDirectory(at: nginxRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apacheRoot, withIntermediateDirectories: true)
        try "<?php echo 'nginx:' . PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;"
            .write(to: nginxRoot.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "<?php echo isset($_GET['rewritten']) ? 'apache-rewrite' : 'apache:' . PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;"
            .write(to: apacheRoot.appendingPathComponent("index.php"), atomically: true, encoding: .utf8)
        try "RewriteEngine On\nRewriteRule ^rewritten$ index.php?rewritten=1 [L,QSA]\n"
            .write(to: apacheRoot.appendingPathComponent(".htaccess"), atomically: true, encoding: .utf8)

        let paths = AppPaths(root: temporaryRoot.appendingPathComponent("runtime", isDirectory: true))
        let manager = RuntimeManager(paths: paths)
        let nginxSite = Site(name: "nginx", slug: "nginx-integration", rootPath: nginxRoot.path)
        var apacheSite = Site(
            name: "Apache",
            slug: "apache-integration",
            rootPath: apacheRoot.path,
            webServer: .apache
        )
        let binaries = manager.discover(configuration: configuration)
        guard binaries.isComplete else {
            throw XCTSkip("Missing core local runtimes: \(binaries.missingFormulae.joined(separator: ", "))")
        }
        guard binaries.apache != nil,
              binaries.apacheModuleDirectory != nil,
              binaries.apacheMimeTypes != nil else {
            throw XCTSkip("Homebrew httpd is not installed")
        }

        defer {
            try? manager.stopAll(configuration: configuration)
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        do {
            try manager.startAll(sites: [nginxSite, apacheSite], configuration: configuration)
        } catch {
            XCTFail("Mixed web stack start failed: \(error.localizedDescription)\n\(manager.combinedLogs())")
            throw error
        }
        XCTAssertEqual(manager.state(for: .apache), .running)
        let nginxBody = try await responseBody(slug: nginxSite.slug, path: "/", port: configuration.httpPort)
        let apacheBody = try await responseBody(slug: apacheSite.slug, path: "/", port: configuration.httpPort)
        let rewriteBody = try await responseBody(slug: apacheSite.slug, path: "/rewritten", port: configuration.httpPort)
        XCTAssertEqual(nginxBody, "nginx:8.3")
        XCTAssertEqual(apacheBody, "apache:8.3")
        XCTAssertEqual(rewriteBody, "apache-rewrite")

        apacheSite.webServer = .nginx
        try manager.reloadWeb(sites: [nginxSite, apacheSite], configuration: configuration)
        XCTAssertEqual(manager.state(for: .apache), .stopped)
        let switchedToNginxBody = try await responseBody(slug: apacheSite.slug, path: "/", port: configuration.httpPort)
        XCTAssertEqual(switchedToNginxBody, "apache:8.3")

        apacheSite.webServer = .apache
        try manager.reloadWeb(sites: [nginxSite, apacheSite], configuration: configuration)
        XCTAssertEqual(manager.state(for: .apache), .running)
        let switchedBackBody = try await responseBody(slug: apacheSite.slug, path: "/rewritten", port: configuration.httpPort)
        XCTAssertEqual(switchedBackBody, "apache-rewrite")
    }

    private func responseBody(slug: String, path: String, port: Int) async throws -> String {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("\(slug).localhost", forHTTPHeaderField: "Host")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return String(decoding: data, as: UTF8.self)
    }
}
