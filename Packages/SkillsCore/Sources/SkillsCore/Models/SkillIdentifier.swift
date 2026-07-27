import Foundation

public struct SkillIdentifier: Hashable, Codable, Sendable {
    public let sourceID: SkillSource.ID
    public let relativePath: String

    public init(sourceID: SkillSource.ID, relativePath: String) {
        self.sourceID = sourceID
        self.relativePath =
            relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .joined(separator: "/")
            .precomposedStringWithCanonicalMapping
    }
}
