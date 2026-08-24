import XCTest
@testable import Lokalweb

final class SiteInspectorTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lokalweb-inspector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testDetectsPHPProject() throws {
        try "<?php echo 'ok';".write(
            to: temporaryRoot.appendingPathComponent("index.php"),
            atomically: true,
            encoding: .utf8
        )
        let inspection = inspect(databaseName: "demo")
        XCTAssertEqual(inspection.platform, .php)
        XCTAssertTrue(inspection.notes.isEmpty)
    }

    func testDetectsWordPressWithoutConfiguration() throws {
        try createWordPressMarkers()
        let inspection = inspect(databaseName: "demo")
        XCTAssertEqual(inspection.platform, .wordpressNeedsConfiguration)
        XCTAssertTrue(inspection.notes.first?.contains("wp-config.php") == true)
    }

    func testReadsWordPressConnectionValuesAndReportsMAMPMismatch() throws {
        try createWordPressMarkers()
        try """
        <?php
        define('DB_NAME', 'mamp_database');
        define("DB_USER", "mamp");
        define('DB_PASSWORD', 'secret-value-must-not-appear');
        define('DB_HOST', '127.0.0.1:8889');
        """.write(
            to: temporaryRoot.appendingPathComponent("wp-config.php"),
            atomically: true,
            encoding: .utf8
        )

        let inspection = inspect(databaseName: "lokal_database")
        XCTAssertEqual(inspection.platform, .wordpress)
        XCTAssertEqual(inspection.databaseConfiguration?.databaseName, "mamp_database")
        XCTAssertEqual(inspection.databaseConfiguration?.user, "mamp")
        XCTAssertEqual(inspection.databaseConfiguration?.host, "127.0.0.1:8889")
        XCTAssertEqual(inspection.notes.count, 3)
        XCTAssertFalse(inspection.notes.joined().contains("secret-value-must-not-appear"))
    }

    func testMissingFolderIsRejectedByValidation() {
        let missing = temporaryRoot.appendingPathComponent("missing", isDirectory: true)
        let site = Site(name: "Demo", slug: "demo", rootPath: missing.path)
        XCTAssertThrowsError(try SiteValidator().validate(site, among: [])) { error in
            XCTAssertEqual((error as? SiteValidationError)?.localizedDescription, SiteValidationError.invalidRoot(missing.path).localizedDescription)
        }
    }

    func testPluginLinkingCreatesSymlinkAndRefusesOverwrite() throws {
        try createWordPressMarkers()
        let plugins = temporaryRoot.appendingPathComponent("wp-content/plugins", isDirectory: true)
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        let source = temporaryRoot.deletingLastPathComponent()
            .appendingPathComponent("plugin-source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }

        let site = Site(name: "Demo", slug: "demo", rootPath: temporaryRoot.path)
        let manager = RuntimeManager(paths: AppPaths(root: temporaryRoot.appendingPathComponent("runtime")))
        try manager.linkPlugin(from: source, to: site)

        let destination = plugins.appendingPathComponent(source.lastPathComponent)
        let linkedPath = try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
        XCTAssertEqual(linkedPath, source.standardizedFileURL.path)
        XCTAssertThrowsError(try manager.linkPlugin(from: source, to: site))
    }

    func testRecoveryRemovesOnlyStaleAppOwnedPIDFile() throws {
        let paths = AppPaths(root: temporaryRoot.appendingPathComponent("recovery-runtime", isDirectory: true))
        try paths.prepare()
        try "2147483647\n".write(to: paths.databasePID, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.databasePID.path))

        RuntimeManager(paths: paths).recoverStaleState()

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.databasePID.path))
    }

    private func inspect(databaseName: String) -> SiteInspection {
        let site = Site(name: "Demo", slug: "demo", rootPath: temporaryRoot.path, databaseName: databaseName)
        return SiteInspector().inspect(site: site, configuration: .default)
    }

    private func createWordPressMarkers() throws {
        for directory in ["wp-admin", "wp-includes", "wp-content"] {
            try FileManager.default.createDirectory(
                at: temporaryRoot.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try "<?php".write(
            to: temporaryRoot.appendingPathComponent("wp-load.php"),
            atomically: true,
            encoding: .utf8
        )
    }
}
