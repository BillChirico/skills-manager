import Foundation

public struct AgentSkill: Identifiable, Hashable, Codable, Sendable {
    public enum ManagementState: String, Hashable, Codable, CaseIterable, Sendable {
        case installed
        case updateAvailable
        case disabled
    }

    public let id: UUID
    public var name: String
    public var summary: String
    public var author: String?
    public var version: String?
    public var directoryURL: URL
    public var sourceID: SkillSource.ID
    public var managementState: ManagementState

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        author: String? = nil,
        version: String? = nil,
        directoryURL: URL,
        sourceID: SkillSource.ID,
        managementState: ManagementState = .installed
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.author = author
        self.version = version
        self.directoryURL = directoryURL
        self.sourceID = sourceID
        self.managementState = managementState
    }
}
