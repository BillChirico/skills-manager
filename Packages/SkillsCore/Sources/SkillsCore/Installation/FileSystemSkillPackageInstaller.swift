import Foundation

public enum SkillPackageInstallError: LocalizedError, Equatable {
    case invalidDirectoryName
    case invalidFilePath
    case missingManifest
    case destinationExists

    public var errorDescription: String? {
        switch self {
        case .invalidDirectoryName:
            "The skill has an invalid installation directory name."
        case .invalidFilePath:
            "The skill package contains an unsafe file path."
        case .missingManifest:
            "The skill package does not contain a SKILL.md manifest."
        case .destinationExists:
            "A skill with this directory name is already installed."
        }
    }
}

public struct FileSystemSkillPackageInstaller: SkillPackageInstalling {
    public init() {}

    public func install(
        _ package: SkillPackage,
        directoryName: String,
        into rootDirectory: URL
    ) throws -> URL {
        let directoryName = directoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            directoryName.isEmpty == false,
            directoryName.hasPrefix(".") == false,
            directoryName.contains("/") == false,
            directoryName.contains("\\") == false
        else {
            throw SkillPackageInstallError.invalidDirectoryName
        }

        var validatedFiles: [(components: [String], file: SkillPackageFile)] = []
        var paths = Set<String>()
        for file in package.files {
            let components = try validatedPathComponents(file.path)
            guard paths.insert(components.joined(separator: "/")).inserted else {
                throw SkillPackageInstallError.invalidFilePath
            }
            validatedFiles.append((components, file))
        }
        guard validatedFiles.contains(where: { $0.components == ["SKILL.md"] }) else {
            throw SkillPackageInstallError.missingManifest
        }

        let fileManager = FileManager()
        let destinationURL = rootDirectory.appending(
            path: directoryName,
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: destinationURL.path) == false else {
            throw SkillPackageInstallError.destinationExists
        }

        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let stagingURL = rootDirectory.appending(
            path: ".\(directoryName).installing-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: true
        )
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        for validatedFile in validatedFiles {
            let fileURL = validatedFile.components.reduce(stagingURL) {
                $0.appending(path: $1)
            }
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try validatedFile.file.contents.write(to: fileURL, options: .atomic)
        }

        try fileManager.moveItem(at: stagingURL, to: destinationURL)
        return destinationURL
    }

    private func validatedPathComponents(_ path: String) throws -> [String] {
        guard path.hasPrefix("/") == false, path.contains("\\") == false else {
            throw SkillPackageInstallError.invalidFilePath
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard
            components.isEmpty == false,
            components.allSatisfy({
                $0.isEmpty == false && $0 != "." && $0 != ".."
            })
        else {
            throw SkillPackageInstallError.invalidFilePath
        }

        return components.map(String.init)
    }
}
