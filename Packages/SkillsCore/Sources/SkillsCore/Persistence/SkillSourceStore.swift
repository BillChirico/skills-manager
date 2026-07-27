import Foundation

public protocol SkillSourceStore: Sendable {
    func loadSources() async throws -> [SkillSource]
    func save(_ sources: [SkillSource]) async throws
}

public actor JSONSkillSourceStore: SkillSourceStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func loadSources() throws -> [SkillSource] {
        let fileManager = FileManager()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([SkillSource].self, from: data)
    }

    public func save(_ sources: [SkillSource]) throws {
        let fileManager = FileManager()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sources)
        try data.write(to: fileURL, options: .atomic)
    }
}
