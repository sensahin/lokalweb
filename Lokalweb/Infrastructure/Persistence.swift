import Foundation

final class Persistence {
    private let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(paths: AppPaths) {
        self.paths = paths
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadSites() throws -> [Site] {
        guard FileManager.default.fileExists(atPath: paths.sitesJSON.path) else { return [] }
        return try decoder.decode([Site].self, from: Data(contentsOf: paths.sitesJSON))
    }

    func saveSites(_ sites: [Site]) throws {
        try paths.prepare()
        try encoder.encode(sites).write(to: paths.sitesJSON, options: .atomic)
    }

    func loadRuntimeConfiguration() throws -> RuntimeConfiguration {
        guard FileManager.default.fileExists(atPath: paths.runtimeJSON.path) else { return .default }
        var configuration = try decoder.decode(RuntimeConfiguration.self, from: Data(contentsOf: paths.runtimeJSON))
        configuration.normalize()
        return configuration
    }

    func saveRuntimeConfiguration(_ configuration: RuntimeConfiguration) throws {
        try paths.prepare()
        var normalized = configuration
        normalized.normalize()
        try encoder.encode(normalized).write(to: paths.runtimeJSON, options: .atomic)
    }
}
