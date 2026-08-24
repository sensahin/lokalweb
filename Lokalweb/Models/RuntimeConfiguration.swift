import Foundation

struct RuntimeConfiguration: Codable, Equatable {
    var httpPort = 8090
    var httpsEnabled = false
    var httpsPort = 8443
    var phpPort = 9083
    var apachePort = 10080
    var databasePort = 3307
    var phpFormula = "php@8.3"
    var stopServicesOnQuit = true

    static let `default` = RuntimeConfiguration()

    private enum CodingKeys: String, CodingKey {
        case httpPort, httpsEnabled, httpsPort, phpPort, apachePort, databasePort, phpFormula, stopServicesOnQuit
    }

    init(
        httpPort: Int = 8090,
        httpsEnabled: Bool = false,
        httpsPort: Int = 8443,
        phpPort: Int = 9083,
        apachePort: Int = 10_080,
        databasePort: Int = 3307,
        phpFormula: String = "php@8.3",
        stopServicesOnQuit: Bool = true
    ) {
        self.httpPort = httpPort
        self.httpsEnabled = httpsEnabled
        self.httpsPort = httpsPort
        self.phpPort = phpPort
        self.apachePort = apachePort
        self.databasePort = databasePort
        self.phpFormula = phpFormula
        self.stopServicesOnQuit = stopServicesOnQuit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        httpPort = try container.decodeIfPresent(Int.self, forKey: .httpPort) ?? 8090
        httpsEnabled = try container.decodeIfPresent(Bool.self, forKey: .httpsEnabled) ?? false
        httpsPort = try container.decodeIfPresent(Int.self, forKey: .httpsPort) ?? 8443
        phpPort = try container.decodeIfPresent(Int.self, forKey: .phpPort) ?? 9083
        apachePort = try container.decodeIfPresent(Int.self, forKey: .apachePort) ?? 10_080
        databasePort = try container.decodeIfPresent(Int.self, forKey: .databasePort) ?? 3307
        phpFormula = try container.decodeIfPresent(String.self, forKey: .phpFormula) ?? "php@8.3"
        stopServicesOnQuit = try container.decodeIfPresent(Bool.self, forKey: .stopServicesOnQuit) ?? true
        normalize()
    }

    mutating func normalize() {
        httpPort = Self.validPort(httpPort, fallback: 8090)
        httpsPort = Self.validPort(httpsPort, fallback: 8443)
        phpPort = Self.validPort(phpPort, fallback: 9083)
        apachePort = Self.validPort(apachePort, fallback: 10_080)
        databasePort = Self.validPort(databasePort, fallback: 3307)
        if phpFormula.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            phpFormula = "php@8.3"
        }
    }

    private static func validPort(_ port: Int, fallback: Int) -> Int {
        (1024...65_535).contains(port) ? port : fallback
    }

    static let supportedPHPFormulae = ["php@8.3", "php@8.4", "php"]

    static func phpLabel(for formula: String) -> String {
        switch formula {
        case "php@8.3": return "PHP 8.3"
        case "php@8.4": return "PHP 8.4"
        case "php": return "PHP 8.5"
        default: return formula
        }
    }

    func validate(sites: [Site]) throws {
        let phpInstances = PHPRuntimePlan(sites: sites, configuration: self).instances
        let namedPorts = [
            ("HTTP", httpPort),
            ("MariaDB", databasePort),
            ("Apache backend", apachePort)
        ] + (httpsEnabled ? [("HTTPS", httpsPort)] : [])
            + phpInstances.map { (RuntimeConfiguration.phpLabel(for: $0.formula), $0.port) }
        for (_, port) in namedPorts where !(1024...65_535).contains(port) {
            throw RuntimeConfigurationError.invalidPort(port)
        }
        let grouped = Dictionary(grouping: namedPorts, by: { $0.1 })
        if let collision = grouped.first(where: { $0.value.count > 1 }) {
            throw RuntimeConfigurationError.portCollision(
                collision.key,
                collision.value.map(\.0).sorted()
            )
        }
        guard RuntimeConfiguration.supportedPHPFormulae.contains(phpFormula) else {
            throw RuntimeConfigurationError.unsupportedPHPFormula
        }
    }
}

enum RuntimeConfigurationError: LocalizedError {
    case invalidPort(Int)
    case portCollision(Int, [String])
    case unsupportedPHPFormula

    var errorDescription: String? {
        switch self {
        case .invalidPort(let port): return "Port \(port) is outside Lokalweb's supported range of 1024–65535."
        case .portCollision(let port, let services):
            return "Port \(port) is assigned to more than one service: \(services.joined(separator: ", "))."
        case .unsupportedPHPFormula: return "Choose a supported global PHP runtime."
        }
    }
}

struct PHPRuntimeInstance: Equatable {
    let formula: String
    let port: Int
}

struct PHPRuntimePlan: Equatable {
    let instances: [PHPRuntimeInstance]

    init(sites: [Site], configuration: RuntimeConfiguration) {
        let requested = Set(sites.compactMap(\.phpFormula) + [configuration.phpFormula])
        let ordered = RuntimeConfiguration.supportedPHPFormulae.filter(requested.contains)
            + requested.filter { !RuntimeConfiguration.supportedPHPFormulae.contains($0) }.sorted()
        instances = ordered.enumerated().map {
            PHPRuntimeInstance(formula: $0.element, port: configuration.phpPort + $0.offset)
        }
    }

    func port(for site: Site, configuration: RuntimeConfiguration) -> Int {
        let formula = site.phpFormula ?? configuration.phpFormula
        return instances.first(where: { $0.formula == formula })?.port ?? configuration.phpPort
    }
}

enum ManagedService: String, CaseIterable, Identifiable {
    case webServer = "nginx"
    case apache = "Apache"
    case php = "PHP-FPM"
    case database = "MariaDB"

    var id: String { rawValue }
}

enum ServiceState: Equatable {
    case stopped
    case starting
    case running
    case stopping
    case unavailable(String)
    case failed(String)

    var label: String {
        switch self {
        case .stopped: return "Stopped"
        case .starting: return "Starting"
        case .running: return "Running"
        case .stopping: return "Stopping"
        case .unavailable: return "Not installed"
        case .failed: return "Needs attention"
        }
    }

    var isRunning: Bool { self == .running }
}
