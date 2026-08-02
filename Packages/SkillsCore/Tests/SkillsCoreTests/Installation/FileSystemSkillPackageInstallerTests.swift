import Foundation
import Testing

@testable import SkillsCore

struct FileSystemSkillPackageInstallerTests {
    @Test("Installing a package writes its complete directory tree")
    func installsCompletePackage() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = SkillPackage(
            skillID: "example/skills/test-skill",
            files: [
                SkillPackageFile(
                    path: "SKILL.md",
                    contents: Data("---\nname: test-skill\n---\n".utf8)
                ),
                SkillPackageFile(
                    path: "references/guide.md",
                    contents: Data("# Guide\n".utf8)
                ),
            ]
        )

        let installedURL = try FileSystemSkillPackageInstaller().install(
            package,
            directoryName: "test-skill",
            into: root
        )

        #expect(installedURL == root.appending(path: "test-skill", directoryHint: .isDirectory))
        #expect(
            try String(
                contentsOf: installedURL.appending(path: "SKILL.md"),
                encoding: .utf8
            ) == "---\nname: test-skill\n---\n"
        )
        #expect(
            try String(
                contentsOf: installedURL.appending(path: "references/guide.md"),
                encoding: .utf8
            ) == "# Guide\n"
        )
    }

    @Test("Installation rejects paths that could escape the selected directory")
    func rejectsTraversalPaths() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = SkillPackage(
            skillID: "example/skills/unsafe",
            files: [
                SkillPackageFile(path: "SKILL.md", contents: Data("safe".utf8)),
                SkillPackageFile(path: "../escaped.txt", contents: Data("unsafe".utf8)),
            ]
        )

        #expect(throws: SkillPackageInstallError.invalidFilePath) {
            try FileSystemSkillPackageInstaller().install(
                package,
                directoryName: "unsafe",
                into: root
            )
        }
        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(path: "escaped.txt").path
            ) == false
        )
        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(path: "unsafe").path
            ) == false
        )
    }

    @Test("Installation rejects a hidden skill directory")
    func rejectsHiddenDirectoryName() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = SkillPackage(
            skillID: "example/skills/hidden",
            files: [SkillPackageFile(path: "SKILL.md", contents: Data("safe".utf8))]
        )

        #expect(throws: SkillPackageInstallError.invalidDirectoryName) {
            try FileSystemSkillPackageInstaller().install(
                package,
                directoryName: ".hidden",
                into: root
            )
        }
        #expect(
            FileManager.default.fileExists(
                atPath: root.appending(path: ".hidden").path
            ) == false
        )
    }

    @Test("Installation never overwrites an existing skill directory")
    func preservesExistingDirectory() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let existingURL = root.appending(path: "existing", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: existingURL,
            withIntermediateDirectories: true
        )
        let existingManifest = existingURL.appending(path: "SKILL.md")
        try Data("original".utf8).write(to: existingManifest)
        let package = SkillPackage(
            skillID: "example/skills/existing",
            files: [SkillPackageFile(path: "SKILL.md", contents: Data("replacement".utf8))]
        )

        #expect(throws: SkillPackageInstallError.destinationExists) {
            try FileSystemSkillPackageInstaller().install(
                package,
                directoryName: "existing",
                into: root
            )
        }
        #expect(try String(contentsOf: existingManifest, encoding: .utf8) == "original")
    }

    private func makeTemporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(
            path: "FileSystemSkillPackageInstallerTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    }
}
