import Foundation

public protocol SkillSourceStore: Sendable {
    func loadSources() async throws -> [SkillSource]
    func save(_ sources: [SkillSource]) async throws
}

public actor JSONSkillSourceStore: SkillSourceStore {
    /// The store holds the full map of the user's skill directories and may retain
    /// legacy bookmark data, so it is kept owner-only rather than inheriting the
    /// process umask. Unsigned builds land outside an app container, where the
    /// default `0644` would be readable by every process running as the user.
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

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
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sources)
        try data.write(to: fileURL, options: .atomic)

        // An atomic write replaces the file, so permissions are applied afterwards.
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: fileURL.path
        )
    }
}
