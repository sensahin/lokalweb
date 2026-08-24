import XCTest
@testable import Lokalweb

final class SiteTests: XCTestCase {
    func testSlugNormalizesNamesForLocalhost() {
        XCTAssertEqual(Site.makeSlug(from: "  My Çool Plugin!  "), "my-cool-plugin")
        XCTAssertEqual(Site.makeSlug(from: "---"), "site")
    }

    func testURLUsesConfiguredPort() {
        let site = Site(name: "Demo", slug: "demo", rootPath: "/tmp/demo")
        XCTAssertEqual(site.url(httpPort: 8090)?.absoluteString, "http://demo.localhost:8090")
    }

    func testURLUsesHTTPSWhenEnabled() {
        let site = Site(name: "Demo", slug: "demo", rootPath: "/tmp/demo")
        let configuration = RuntimeConfiguration(httpsEnabled: true, httpsPort: 8443)
        XCTAssertEqual(site.url(configuration: configuration)?.absoluteString, "https://demo.localhost:8443")
    }

    func testPerSitePHPRuntimesReceiveStablePorts() {
        let defaultSite = Site(name: "Default", slug: "default", rootPath: "/tmp/default")
        let modernSite = Site(name: "Modern", slug: "modern", rootPath: "/tmp/modern", phpFormula: "php@8.4")
        let configuration = RuntimeConfiguration(phpPort: 9_083, phpFormula: "php@8.3")
        let plan = PHPRuntimePlan(sites: [modernSite, defaultSite], configuration: configuration)

        XCTAssertEqual(plan.instances, [
            PHPRuntimeInstance(formula: "php@8.3", port: 9_083),
            PHPRuntimeInstance(formula: "php@8.4", port: 9_084)
        ])
        XCTAssertEqual(plan.port(for: modernSite, configuration: configuration), 9_084)
        XCTAssertEqual(plan.port(for: defaultSite, configuration: configuration), 9_083)
    }

    func testRuntimeConfigurationRejectsPortCollisions() {
        let configuration = RuntimeConfiguration(httpPort: 8_090, httpsEnabled: true, httpsPort: 8_090)
        XCTAssertThrowsError(try configuration.validate(sites: [])) { error in
            XCTAssertTrue(error.localizedDescription.contains("more than one service"))
        }
    }

    func testLegacySiteJSONLoadsWithoutPHPOverride() throws {
        let id = UUID()
        let data = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "slug": "legacy",
          "rootPath": "/tmp/legacy",
          "databaseName": "legacy",
          "createdAt": "2026-08-19T10:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let site = try decoder.decode(Site.self, from: data)
        XCTAssertNil(site.phpFormula)
        XCTAssertEqual(site.webServer, .nginx)
        XCTAssertEqual(site.id, id)
    }

    func testApacheSelectionRoundTripsThroughPersistenceJSON() throws {
        let site = Site(
            name: "Apache Site",
            slug: "apache-site",
            rootPath: "/tmp/apache-site",
            webServer: .apache
        )
        let data = try JSONEncoder().encode(site)
        let decoded = try JSONDecoder().decode(Site.self, from: data)
        XCTAssertEqual(decoded.webServer, .apache)
    }

    func testLegacyRuntimeJSONReceivesSafeNewDefaults() throws {
        let data = #"{"httpPort":8090,"phpPort":9083,"databasePort":3307,"phpFormula":"php@8.3"}"#.data(using: .utf8)!
        let configuration = try JSONDecoder().decode(RuntimeConfiguration.self, from: data)
        XCTAssertFalse(configuration.httpsEnabled)
        XCTAssertEqual(configuration.httpsPort, 8_443)
        XCTAssertEqual(configuration.apachePort, 10_080)
        XCTAssertTrue(configuration.stopServicesOnQuit)
    }

    func testApacheBackendPortParticipatesInCollisionValidation() {
        let apacheSite = Site(
            name: "Apache",
            slug: "apache",
            rootPath: "/tmp/apache",
            webServer: .apache
        )
        let configuration = RuntimeConfiguration(httpPort: 8_090, apachePort: 8_090)
        XCTAssertThrowsError(try configuration.validate(sites: [apacheSite])) { error in
            XCTAssertTrue(error.localizedDescription.contains("Apache backend"))
        }
    }
}
