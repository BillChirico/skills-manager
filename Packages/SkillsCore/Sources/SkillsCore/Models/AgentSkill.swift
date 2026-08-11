import Foundation

/// The authoritative availability state assigned by a completed CLI probe.
public enum SkillUpdateStatus: String, Codable, Sendable {
    case unknown
    case current
    case available
}

public struct AgentSkill: Identifiable, Hashable, Codable, Sendable {
    public let id: SkillIdentifier
    public var name: String
    public var summary: String
    public var author: String?
    public var installedVersion: String?
    public var availableVersion: String?
    /// `nil` preserves legacy version comparison before a probe; `.unknown`
    /// explicitly suppresses it when the latest probe did not cover this skill.
    public var updateStatus: SkillUpdateStatus?
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
        updateStatus: SkillUpdateStatus? = nil,
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
        self.updateStatus = updateStatus
        self.directoryURL = directoryURL
        self.sourceID = sourceID
        self.isEnabled = isEnabled
        self.addedAt = addedAt
        self.overview = overview ?? summary
        self.lastScannedAt = lastScannedAt
    }

    /// Markdown-styled overview text with every manifest-supplied destination removed.
    ///
    /// Installed manifests are untrusted. Preserving inline emphasis is useful, but a link
    /// must not become an interactive app action merely because it appeared in `SKILL.md`.
    public var attributedOverview: AttributedString {
        var attributed =
            (try? AttributedString(markdown: overview))
            ?? AttributedString(overview)
        attributed.link = nil
        return attributed
    }

    public var hasUpdate: Bool {
        if let updateStatus {
            return updateStatus == .available
        }

        guard let installedVersion, let availableVersion else {
            return false
        }

        return installedVersion != availableVersion
    }
}
