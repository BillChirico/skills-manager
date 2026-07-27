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

struct SecurityScopedSkillSourceBookmarker: SkillSourceBookmarking {
    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> ResolvedSkillSourceBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return ResolvedSkillSourceBookmark(url: url, isStale: isStale)
    }
}

@MainActor
protocol SkillSourceAccessing: AnyObject {
    func beginAccessing(_ url: URL, for sourceID: SkillSource.ID) -> Bool
    func stopAccessing(sourceID: SkillSource.ID)
}

@MainActor
final class SecurityScopedSkillSourceAccess: SkillSourceAccessing {
    private var activeURLs: [SkillSource.ID: URL] = [:]

    func beginAccessing(_ url: URL, for sourceID: SkillSource.ID) -> Bool {
        stopAccessing(sourceID: sourceID)

        guard url.startAccessingSecurityScopedResource() else {
            return false
        }

        activeURLs[sourceID] = url
        return true
    }

    func stopAccessing(sourceID: SkillSource.ID) {
        activeURLs.removeValue(forKey: sourceID)?.stopAccessingSecurityScopedResource()
    }

    deinit {
        for url in activeURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
