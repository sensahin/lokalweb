import Foundation

enum WebServerKind: String, Codable, CaseIterable, Identifiable {
    case nginx
    case apache

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nginx: return "nginx"
        case .apache: return "Apache"
        }
    }
}

struct Site: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var rootPath: String
    var databaseName: String
    var phpFormula: String?
    var webServer: WebServerKind
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        slug: String,
        rootPath: String,
        databaseName: String? = nil,
        phpFormula: String? = nil,
        webServer: WebServerKind = .nginx,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.rootPath = rootPath
        self.databaseName = databaseName ?? slug.replacingOccurrences(of: "-", with: "_")
        self.phpFormula = phpFormula
        self.webServer = webServer
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, rootPath, databaseName, phpFormula, webServer, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decode(String.self, forKey: .slug)
        rootPath = try container.decode(String.self, forKey: .rootPath)
        databaseName = try container.decode(String.self, forKey: .databaseName)
        phpFormula = try container.decodeIfPresent(String.self, forKey: .phpFormula)
        webServer = try container.decodeIfPresent(WebServerKind.self, forKey: .webServer) ?? .nginx
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    static func makeSlug(from value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
        let allowed = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String((collapsed.isEmpty ? "site" : collapsed).prefix(48))
    }

    func url(httpPort: Int) -> URL? {
        URL(string: "http://\(slug).localhost:\(httpPort)")
    }

    func url(configuration: RuntimeConfiguration) -> URL? {
        let scheme = configuration.httpsEnabled ? "https" : "http"
        let port = configuration.httpsEnabled ? configuration.httpsPort : configuration.httpPort
        return URL(string: "\(scheme)://\(slug).localhost:\(port)")
    }
}
