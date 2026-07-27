import Foundation

public struct SkillSource: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var directoryURL: URL
    public var isEnabled: Bool
    public var bookmarkData: Data?

    public init(
        id: UUID = UUID(),
        name: String,
        directoryURL: URL,
        isEnabled: Bool = true,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.directoryURL = directoryURL
        self.isEnabled = isEnabled
        self.bookmarkData = bookmarkData
    }

    public var displayName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? directoryURL.lastPathComponent : trimmedName
    }
}
