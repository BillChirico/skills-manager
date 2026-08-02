import Foundation
import SkillsCore

struct ResolvedSkillSourceBookmark: Sendable {
    let url: URL
    let isStale: Bool
}

protocol SkillSourceBookmarking: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> ResolvedSkillSourceBookmark
}

@MainActor
protocol SkillSourceAccessing: AnyObject {
    func beginAccessing(_ url: URL, for sourceID: SkillSource.ID) -> Bool
    func stopAccessing(sourceID: SkillSource.ID)
}
