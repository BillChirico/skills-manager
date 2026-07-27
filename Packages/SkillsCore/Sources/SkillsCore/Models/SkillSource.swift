import Foundation

public struct SkillSource: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var directoryURL: URL
    public var agent: SkillAgent
    public var isEnabled: Bool
    public var bookmarkData: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        directoryURL: URL,
        agent: SkillAgent = .other,
        isEnabled: Bool = true,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryURL = directoryURL
        self.agent = agent
        self.isEnabled = isEnabled
        self.bookmarkData = bookmarkData
    }

    public var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? directoryURL.lastPathComponent : trimmedName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case directoryURL
        case agent
        case isEnabled
        case bookmarkData
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        directoryURL = try container.decode(URL.self, forKey: .directoryURL)
        agent = try container.decodeIfPresent(SkillAgent.self, forKey: .agent) ?? .other
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(directoryURL, forKey: .directoryURL)
        try container.encode(agent, forKey: .agent)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
    }
}
