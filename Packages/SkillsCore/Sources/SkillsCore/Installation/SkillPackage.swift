import Foundation

public struct SkillPackageFile: Hashable, Sendable {
    public let path: String
    public let contents: Data

    public init(path: String, contents: Data) {
        self.path = path
        self.contents = contents
    }
}

public struct SkillPackage: Hashable, Sendable {
    public let skillID: String
    public let files: [SkillPackageFile]

    public init(skillID: String, files: [SkillPackageFile]) {
        self.skillID = skillID
        self.files = files
    }
}

public protocol SkillPackageFetching: Sendable {
    func fetchPackage(for skill: CatalogSkill) async throws -> SkillPackage
}

public protocol SkillPackageInstalling: Sendable {
    func install(
        _ package: SkillPackage,
        directoryName: String,
        into rootDirectory: URL
    ) throws -> URL
}
