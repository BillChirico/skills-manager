import Foundation

public struct AgentSkill: Identifiable, Hashable, Codable, Sendable {
    public let id: SkillIdentifier
    public var name: String
    public var summary: String
    public var author: String?
    public var installedVersion: String?
    public var availableVersion: String?
    public var directoryURL: URL
    public var sourceID: SkillSource.ID
    public var isEnabled: Bool
    public var addedAt: Date
    public var overview: String
    public var lastScannedAt: Date?

    public init(
        id: SkillIdentifier? = nil,
        name: String,
        summary: String,
        author: String? = nil,
        installedVersion: String? = nil,
        availableVersion: String? = nil,
        directoryURL: URL,
        sourceID: SkillSource.ID,
        relativePath: String? = nil,
        isEnabled: Bool = true,
        addedAt: Date = .now,
        overview: String? = nil,
        lastScannedAt: Date? = nil
    ) {
        self.id =
            id
            ?? SkillIdentifier(
                sourceID: sourceID,
                relativePath: relativePath ?? directoryURL.lastPathComponent
            )
        self.name = name
        self.summary = summary
        self.author = author
        self.installedVersion = installedVersion
        self.availableVersion = availableVersion
        self.directoryURL = directoryURL
        self.sourceID = sourceID
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.overview = overview ?? summary
        self.lastScannedAt = lastScannedAt
    }

    public var hasUpdate: Bool {
        guard let installedVersion, let availableVersion else {
            return false
        }

        return installedVersion != availableVersion
    }
}
