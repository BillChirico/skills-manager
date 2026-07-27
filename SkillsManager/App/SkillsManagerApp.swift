import SkillsCore
import SwiftUI

@main
struct SkillsManagerApp: App {
    @State private var libraryModel: SkillLibraryModel
    @State private var catalogModel: SkillCatalogModel

    init() {
        let sourceStore: (any SkillSourceStore)? =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first.map {
                JSONSkillSourceStore(
                    fileURL:
                        $0
                        .appending(path: "ai.volvox.SkillsManager", directoryHint: .isDirectory)
                        .appending(path: "sources.json", directoryHint: .notDirectory)
                )
            }

        _libraryModel = State(
            initialValue: SkillLibraryModel(
                sourceStore: sourceStore,
                discoverer: FileSystemSkillDiscoverer(),
                bookmarker: SecurityScopedSkillSourceBookmarker(),
                sourceAccess: SecurityScopedSkillSourceAccess()
            )
        )
        _catalogModel = State(
            initialValue: SkillCatalogModel(
                catalog: SkillsShCatalogClient(),
                packageFetcher: GitHubSkillPackageFetcher(),
                packageInstaller: FileSystemSkillPackageInstaller()
            )
        )
    }

    var body: some Scene {
        WindowGroup("Skills Manager") {
            SkillLibraryView(
                model: libraryModel,
                catalogModel: catalogModel
            )
            .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1_120, height: 720)

        Settings {
            SettingsView(model: libraryModel)
        }
    }
}
