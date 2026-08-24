import XCTest
@testable import Lokalweb

final class ConfigurationGeneratorTests: XCTestCase {
    func testNginxConfigurationContainsWordPressRoutingAndEscapedRoot() throws {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/Lokalweb Tests"))
        let generator = ConfigurationGenerator(paths: paths)
        let site = Site(name: "Demo", slug: "demo", rootPath: "/tmp/My \"Site\"")
        let binaries = RuntimeBinaries(nginxConfigurationDirectory: "/opt/homebrew/etc/nginx")

        let output = try generator.nginxConfiguration(
            sites: [site],
            configuration: .default,
            binaries: binaries
        )

        XCTAssertTrue(output.contains("server_name demo.localhost;"))
        XCTAssertTrue(output.contains("try_files $uri $uri/ /index.php?$args;"))
        XCTAssertTrue(output.contains("fastcgi_pass 127.0.0.1:9083;"))
        XCTAssertTrue(output.contains("include \"/opt/homebrew/etc/nginx/fastcgi_params\";"))
        XCTAssertTrue(output.contains("root \"/tmp/My \\\"Site\\\"\";"))
    }

    func testRuntimeConfigurationNormalizesUnsafePorts() {
        var configuration = RuntimeConfiguration(httpPort: 80, phpPort: 0, databasePort: 70_000, phpFormula: "")
        configuration.normalize()
        XCTAssertEqual(configuration, .default)
    }

    func testDatabaseConfigurationQuotesApplicationSupportPaths() throws {
        let paths = AppPaths(root: URL(fileURLWithPath: "/Users/example/Library/Application Support/Lokalweb"))
        let binaries = RuntimeBinaries(mariaDBPrefix: "/opt/homebrew/opt/mariadb")

        let output = try ConfigurationGenerator(paths: paths).databaseConfiguration(
            configuration: .default,
            binaries: binaries
        )

        XCTAssertTrue(output.contains("datadir = \"/Users/example/Library/Application Support/Lokalweb/database\""))
        XCTAssertTrue(output.contains("socket = \"/Users/example/Library/Application Support/Lokalweb/run/mariadb.sock\""))
    }

    func testNginxConfigurationAddsIsolatedHTTPSListener() throws {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/Lokalweb HTTPS", isDirectory: true))
        let configuration = RuntimeConfiguration(httpsEnabled: true, httpsPort: 18_443)
        let binaries = RuntimeBinaries(
            nginxConfigurationDirectory: "/opt/homebrew/etc/nginx"
        )
        let site = Site(name: "Secure", slug: "secure", rootPath: "/tmp/secure")
        let value = try ConfigurationGenerator(paths: paths).nginxConfiguration(
            sites: [site],
            configuration: configuration,
            binaries: binaries
        )
        XCTAssertTrue(value.contains("listen 127.0.0.1:18443 ssl;"))
        XCTAssertTrue(value.contains("ssl_certificate \"/tmp/Lokalweb HTTPS/certificates/localhost.pem\";"))
        XCTAssertTrue(value.contains("ssl_protocols TLSv1.2 TLSv1.3;"))
    }

    func testNginxRoutesSitesToTheirAssignedPHPRuntime() throws {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/Lokalweb PHP", isDirectory: true))
        let binaries = RuntimeBinaries(nginxConfigurationDirectory: "/opt/homebrew/etc/nginx")
        let legacy = Site(name: "Legacy", slug: "legacy", rootPath: "/tmp/legacy")
        let modern = Site(name: "Modern", slug: "modern", rootPath: "/tmp/modern", phpFormula: "php@8.4")
        let value = try ConfigurationGenerator(paths: paths).nginxConfiguration(
            sites: [legacy, modern],
            configuration: .default,
            binaries: binaries
        )
        let legacyBlock = value.components(separatedBy: "server_name legacy.localhost;")[1]
            .components(separatedBy: "server_name modern.localhost;")[0]
        let modernBlock = value.components(separatedBy: "server_name modern.localhost;")[1]
        XCTAssertTrue(legacyBlock.contains("fastcgi_pass 127.0.0.1:9083;"))
        XCTAssertTrue(modernBlock.contains("fastcgi_pass 127.0.0.1:9084;"))
    }

    func testNginxProxiesOnlyApacheSelectedSites() throws {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/Lokalweb Servers", isDirectory: true))
        let binaries = RuntimeBinaries(nginxConfigurationDirectory: "/opt/homebrew/etc/nginx")
        let nginxSite = Site(name: "nginx", slug: "nginx", rootPath: "/tmp/nginx")
        let apacheSite = Site(
            name: "Apache",
            slug: "apache",
            rootPath: "/tmp/apache",
            webServer: .apache
        )
        let configuration = RuntimeConfiguration(apachePort: 10_180)
        let value = try ConfigurationGenerator(paths: paths).nginxConfiguration(
            sites: [nginxSite, apacheSite],
            configuration: configuration,
            binaries: binaries
        )

        let nginxBlock = value.components(separatedBy: "server_name nginx.localhost;")[1]
            .components(separatedBy: "server_name apache.localhost;")[0]
        let apacheBlock = value.components(separatedBy: "server_name apache.localhost;")[1]
        XCTAssertTrue(nginxBlock.contains("fastcgi_pass 127.0.0.1:9083;"))
        XCTAssertFalse(nginxBlock.contains("proxy_pass"))
        XCTAssertTrue(apacheBlock.contains("proxy_pass http://127.0.0.1:10180;"))
        XCTAssertTrue(apacheBlock.contains("proxy_set_header Host $http_host;"))
        XCTAssertTrue(apacheBlock.contains("proxy_set_header X-Forwarded-Proto $scheme;"))
    }

    func testApacheConfigurationEnablesHtaccessAndSelectedPHPPool() throws {
        let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/Lokalweb Apache", isDirectory: true))
        let binaries = RuntimeBinaries(
            apachePrefix: "/opt/homebrew/opt/httpd",
            apacheModuleDirectory: "/opt/homebrew/opt/httpd/lib/httpd/modules",
            apacheMimeTypes: "/opt/homebrew/etc/httpd/mime.types"
        )
        let apacheSite = Site(
            name: "Apache",
            slug: "apache",
            rootPath: "/tmp/Apache Site",
            phpFormula: "php@8.4",
            webServer: .apache
        )
        let value = try ConfigurationGenerator(paths: paths).apacheConfiguration(
            sites: [apacheSite],
            configuration: .default,
            binaries: binaries
        )

        XCTAssertTrue(value.contains("Listen 127.0.0.1:10080"))
        XCTAssertTrue(value.contains("<VirtualHost 127.0.0.1:10080>"))
        XCTAssertTrue(value.contains("ServerName apache.localhost"))
        XCTAssertTrue(value.contains("DocumentRoot \"/tmp/Apache Site\""))
        XCTAssertTrue(value.contains("AllowOverride All"))
        XCTAssertTrue(value.contains("SetHandler \"proxy:fcgi://127.0.0.1:9084\""))
        XCTAssertTrue(value.contains("LoadModule rewrite_module"))
    }
}
