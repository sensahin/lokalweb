import XCTest
@testable import Lokalweb

final class WordPressInstallationTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("lokalweb-wordpress-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testWPCLIUsesScopedMemoryLimit() {
        let arguments = WordPressCLIInvocation.phpArguments(
            wpPath: "/opt/homebrew/bin/wp",
            command: ["--path=/tmp/site", "core", "download"]
        )

        XCTAssertEqual(arguments, [
            "-d", "memory_limit=512M", "/opt/homebrew/bin/wp",
            "--path=/tmp/site", "core", "download"
        ])
    }

    @MainActor
    func testHostedTestProcessCannotStopRealLokalwebServicesOnQuit() {
        XCTAssertFalse(LokalwebAppDelegate.shouldStopServicesOnTermination(environment: [
            "XCTestConfigurationFilePath": "/tmp/LokalwebTests.xctestconfiguration"
        ]))
        XCTAssertTrue(LokalwebAppDelegate.shouldStopServicesOnTermination(environment: [:]))
    }

    func testRollbackRemovesGeneratedFilesAndPreservesExistingFinderMetadata() throws {
        let finderMetadata = temporaryRoot.appendingPathComponent(".DS_Store")
        try Data().write(to: finderMetadata)
        let workspace = try WordPressInstallationWorkspace(root: temporaryRoot)

        try "<?php".write(
            to: temporaryRoot.appendingPathComponent("index.php"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: temporaryRoot.appendingPathComponent("wp-admin", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(workspace.rollbackGeneratedContents().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderMetadata.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("index.php").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("wp-admin").path))
    }

    func testWorkspaceRejectsAProjectContainingUserFiles() throws {
        try "keep me".write(
            to: temporaryRoot.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try WordPressInstallationWorkspace(root: temporaryRoot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryRoot.appendingPathComponent("notes.txt").path))
    }

    @MainActor
    func testFailedNewInstallationIsNotRegisteredBeforeCompletion() async throws {
        let paths = AppPaths(root: temporaryRoot.appendingPathComponent("app-data", isDirectory: true))
        let siteRoot = temporaryRoot.appendingPathComponent("new-site", isDirectory: true)
        try FileManager.default.createDirectory(at: siteRoot, withIntermediateDirectories: true)
        let model = AppModel(paths: paths)

        let succeeded = await withCheckedContinuation { continuation in
            model.createWordPressSite(
                name: "Deferred Site",
                rootPath: siteRoot.path,
                adminUser: "admin",
                adminPassword: "Lokalweb-Test-2026!",
                adminEmail: "admin@example.test"
            ) { result in
                continuation.resume(returning: result)
            }
        }

        XCTAssertFalse(succeeded)
        XCTAssertTrue(model.sites.isEmpty)
        XCTAssertTrue(try Persistence(paths: paths).loadSites().isEmpty)
    }
}
