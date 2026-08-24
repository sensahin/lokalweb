import Foundation

enum SitePlatform: Equatable {
    case wordpress
    case wordpressNeedsConfiguration
    case php
    case unsupported
    case missing

    var label: String {
        switch self {
        case .wordpress: return "WordPress"
        case .wordpressNeedsConfiguration: return "WordPress needs configuration"
        case .php: return "PHP"
        case .unsupported: return "No PHP entry point"
        case .missing: return "Folder missing"
        }
    }

    var systemImage: String {
        switch self {
        case .wordpress, .wordpressNeedsConfiguration: return "w.circle"
        case .php: return "chevron.left.forwardslash.chevron.right"
        case .unsupported: return "questionmark.folder"
        case .missing: return "exclamationmark.folder"
        }
    }
}

struct WordPressDatabaseConfiguration: Equatable {
    var databaseName: String?
    var user: String?
    var host: String?
}

struct SiteInspection: Equatable {
    var platform: SitePlatform
    var databaseConfiguration: WordPressDatabaseConfiguration?
    var notes: [String]
}

struct SiteInspector {
    private let fileManager = FileManager.default

    func inspect(site: Site, configuration: RuntimeConfiguration) -> SiteInspection {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: site.rootPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return SiteInspection(platform: .missing, databaseConfiguration: nil, notes: ["Choose an existing project folder."])
        }

        let root = URL(fileURLWithPath: site.rootPath, isDirectory: true)
        let wordpressMarkers = ["wp-admin", "wp-includes", "wp-content", "wp-load.php"]
        let isWordPress = wordpressMarkers.allSatisfy {
            fileManager.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        guard isWordPress else {
            let hasPHPEntryPoint = fileManager.fileExists(atPath: root.appendingPathComponent("index.php").path)
            return SiteInspection(
                platform: hasPHPEntryPoint ? .php : .unsupported,
                databaseConfiguration: nil,
                notes: hasPHPEntryPoint ? [] : ["This folder does not contain index.php or a complete WordPress installation."]
            )
        }

        let configURL = root.appendingPathComponent("wp-config.php")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return SiteInspection(
                platform: .wordpressNeedsConfiguration,
                databaseConfiguration: nil,
                notes: ["Create wp-config.php or copy your existing MAMP configuration before opening this site."]
            )
        }

        let discovered = WordPressDatabaseConfiguration(
            databaseName: constant("DB_NAME", in: contents),
            user: constant("DB_USER", in: contents),
            host: constant("DB_HOST", in: contents)
        )
        let expectedHost = "127.0.0.1:\(configuration.databasePort)"
        var notes: [String] = []
        if discovered.databaseName != site.databaseName {
            notes.append("wp-config.php uses database \(display(discovered.databaseName)); Lokalweb is set to \(site.databaseName).")
        }
        if discovered.user != "root" {
            notes.append("wp-config.php uses database user \(display(discovered.user)); Lokalweb currently uses root.")
        }
        if discovered.host != expectedHost {
            notes.append("wp-config.php uses host \(display(discovered.host)); Lokalweb listens at \(expectedHost).")
        }
        return SiteInspection(platform: .wordpress, databaseConfiguration: discovered, notes: notes)
    }

    private func constant(_ name: String, in contents: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"define\s*\(\s*['\"]"# + escaped + #"['\"]\s*,\s*['\"]([^'\"]*)['\"]\s*\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        guard let match = expression.firstMatch(in: contents, range: range),
              let valueRange = Range(match.range(at: 1), in: contents) else { return nil }
        return String(contents[valueRange])
    }

    private func display(_ value: String?) -> String {
        value.map { "“\($0)”" } ?? "an unreadable value"
    }
}

enum SiteValidationError: LocalizedError {
    case missingName
    case invalidSlug
    case duplicateSlug
    case invalidRoot(String)
    case invalidDatabaseName
    case unsupportedPHPFormula

    var errorDescription: String? {
        switch self {
        case .missingName: return "Enter a site name."
        case .invalidSlug: return "The hostname slug may contain lowercase letters, numbers, and single hyphens only."
        case .duplicateSlug: return "Another Lokalweb site already uses this hostname slug."
        case .invalidRoot(let path): return "The project folder does not exist or is not a directory: \(path)"
        case .invalidDatabaseName: return "The database name must be 1–64 letters, numbers, or underscores."
        case .unsupportedPHPFormula: return "Choose a supported Lokalweb PHP runtime."
        }
    }
}

struct SiteValidator {
    func validate(_ site: Site, among sites: [Site]) throws {
        guard !site.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SiteValidationError.missingName
        }
        let slugPattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#
        guard site.slug.range(of: slugPattern, options: .regularExpression) != nil else {
            throw SiteValidationError.invalidSlug
        }
        guard !sites.contains(where: { $0.id != site.id && $0.slug == site.slug }) else {
            throw SiteValidationError.duplicateSlug
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: site.rootPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw SiteValidationError.invalidRoot(site.rootPath)
        }
        let databasePattern = #"^[A-Za-z0-9_]{1,64}$"#
        guard site.databaseName.range(of: databasePattern, options: .regularExpression) != nil else {
            throw SiteValidationError.invalidDatabaseName
        }
        guard site.phpFormula == nil || RuntimeConfiguration.supportedPHPFormulae.contains(site.phpFormula!) else {
            throw SiteValidationError.unsupportedPHPFormula
        }
    }
}
