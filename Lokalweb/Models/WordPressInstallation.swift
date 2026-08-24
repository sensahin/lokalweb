import Foundation

struct WordPressCLIInvocation {
    static let memoryLimit = "512M"

    static func phpArguments(wpPath: String, command: [String]) -> [String] {
        ["-d", "memory_limit=\(memoryLimit)", wpPath] + command
    }
}

struct WordPressInstallationWorkspace {
    let root: URL
    private let preservedNames: Set<String>

    init(root: URL, fileManager: FileManager = .default) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeError.invalidWordPressTarget("Choose an existing empty folder for the new WordPress installation.")
        }
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: []
        )
        guard contents.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else {
            throw RuntimeError.invalidWordPressTarget("A new WordPress installation requires an empty project folder.")
        }
        preservedNames = Set(contents.map(\.lastPathComponent))
        self.root = root
    }

    func rollbackGeneratedContents(fileManager: FileManager = .default) -> [String] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: []
            )
            return contents.compactMap { item in
                guard !preservedNames.contains(item.lastPathComponent) else { return nil }
                do {
                    try fileManager.removeItem(at: item)
                    return nil
                } catch {
                    return "Could not remove \(item.lastPathComponent): \(error.localizedDescription)"
                }
            }
        } catch {
            return ["Could not inspect the installation folder during cleanup: \(error.localizedDescription)"]
        }
    }
}
