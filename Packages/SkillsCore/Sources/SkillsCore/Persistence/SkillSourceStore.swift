import Foundation
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public struct SkillSourceConfiguration: Equatable, Sendable, Codable {
    public var sources: [SkillSource]
    public var excludedAutomaticDirectoryURLs: Set<URL>

    public init(
        sources: [SkillSource] = [],
        excludedAutomaticDirectoryURLs: Set<URL> = []
    ) {
        self.sources = sources
        self.excludedAutomaticDirectoryURLs = excludedAutomaticDirectoryURLs
    }

    private enum CodingKeys: String, CodingKey {
        case sources
        case excludedAutomaticDirectoryURLs
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sources = try container.decode([SkillSource].self, forKey: .sources)
        excludedAutomaticDirectoryURLs = Set(
            try container.decodeIfPresent(
                [URL].self,
                forKey: .excludedAutomaticDirectoryURLs
            ) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sources, forKey: .sources)
        try container.encode(
            excludedAutomaticDirectoryURLs.sorted {
                $0.path(percentEncoded: false) < $1.path(percentEncoded: false)
            },
            forKey: .excludedAutomaticDirectoryURLs
        )
    }
}

public protocol SkillSourceStore: Sendable {
    func loadSources() async throws -> [SkillSource]
    func save(_ sources: [SkillSource]) async throws
    func loadConfiguration() async throws -> SkillSourceConfiguration
    func save(_ configuration: SkillSourceConfiguration) async throws
}

public extension SkillSourceStore {
    func loadConfiguration() async throws -> SkillSourceConfiguration {
        SkillSourceConfiguration(sources: try await loadSources())
    }

    func save(_ configuration: SkillSourceConfiguration) async throws {
        try await save(configuration.sources)
    }
}

public actor JSONSkillSourceStore: SkillSourceStore {
    /// The store holds the full map of the user's skill directories and may retain
    /// legacy bookmark data, so it is kept owner-only rather than inheriting the
    /// process umask. Unsigned builds land outside an app container, where the
    /// default `0644` would be readable by every process running as the user.
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    private let fileURL: URL
    private let commitFile: @Sendable (URL, URL) throws -> Void

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.commitFile = { temporaryURL, destinationURL in
            try Self.commitTemporaryFile(temporaryURL, destinationURL)
        }
    }

    init(
        fileURL: URL,
        commitFile: @escaping @Sendable (URL, URL) throws -> Void
    ) {
        self.fileURL = fileURL
        self.commitFile = commitFile
    }

    public func loadSources() throws -> [SkillSource] {
        try loadConfigurationFromDisk().sources
    }

    public func loadConfiguration() async throws -> SkillSourceConfiguration {
        try loadConfigurationFromDisk()
    }

    public func save(_ sources: [SkillSource]) throws {
        let configuration: SkillSourceConfiguration
        do {
            configuration = try loadConfigurationFromDisk()
        } catch is DecodingError {
            configuration = SkillSourceConfiguration()
        } catch {
            throw error
        }

        try saveConfigurationToDisk(
            SkillSourceConfiguration(
                sources: sources,
                excludedAutomaticDirectoryURLs:
                    configuration.excludedAutomaticDirectoryURLs
            )
        )
    }

    public func save(_ configuration: SkillSourceConfiguration) async throws {
        try saveConfigurationToDisk(configuration)
    }

    private func loadConfigurationFromDisk() throws -> SkillSourceConfiguration {
        let fileManager = FileManager()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return SkillSourceConfiguration()
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()

        if let configuration = try? decoder.decode(
            SkillSourceConfiguration.self,
            from: data
        ) {
            return configuration
        }

        return SkillSourceConfiguration(
            sources: try decoder.decode([SkillSource].self, from: data)
        )
    }

    private func saveConfigurationToDisk(
        _ configuration: SkillSourceConfiguration
    ) throws {
        let fileManager = FileManager()
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try fileManager.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: directoryURL.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        let temporaryURL = directoryURL.appending(
            path: ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp",
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }

        guard
            fileManager.createFile(
                atPath: temporaryURL.path,
                contents: data,
                attributes: [.posixPermissions: Self.filePermissions]
            )
        else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSFilePathErrorKey: temporaryURL.path]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: temporaryURL.path
        )
        try commitFile(temporaryURL, fileURL)
    }

    private static func commitTemporaryFile(
        _ temporaryURL: URL,
        _ destinationURL: URL
    ) throws {
        #if canImport(Darwin) || canImport(Glibc)
            let result = temporaryURL.withUnsafeFileSystemRepresentation { temporaryPath in
                guard let temporaryPath else {
                    errno = EINVAL
                    return Int32(-1)
                }

                return destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                    guard let destinationPath else {
                        errno = EINVAL
                        return Int32(-1)
                    }

                    #if canImport(Darwin)
                        return Darwin.rename(temporaryPath, destinationPath)
                    #else
                        return Glibc.rename(temporaryPath, destinationPath)
                    #endif
                }
            }
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        #else
            let fileManager = FileManager()
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: .usingNewMetadataOnly
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        #endif
    }
}
