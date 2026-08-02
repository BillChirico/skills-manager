import SkillsCore
import SwiftUI

@main
struct SkillsManagerApp: App {
    @State private var libraryModel: SkillLibraryModel
    @State private var catalogModel: SkillCatalogModel

    init() {
        let skillsCLIManager = SkillsCLIManager(homeDirectory: UserHomeDirectory.current)
        let sourceStore: (any SkillSourceStore)? =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first.map {
                let currentURL = $0.appending(path: "ai.volvox.SkillsManager/sources.json")
                let oldURL = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: "Library/Containers/ai.volvox.SkillsManager/Data/Library/Application Support/ai.volvox.SkillsManager/sources.json")
                if !FileManager.default.fileExists(atPath: currentURL.path),
                   FileManager.default.fileExists(atPath: oldURL.path) {
                    try? FileManager.default.createDirectory(at: currentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.copyItem(at: oldURL, to: currentURL)
                }
                return JSONSkillSourceStore(fileURL: currentURL)
            }

        _libraryModel = State(
            initialValue: SkillLibraryModel(
                sourceStore: sourceStore,
                discoverer: FileSystemSkillDiscoverer(),
                skillManager: skillsCLIManager
            )
        )
        _catalogModel = State(
            initialValue: SkillCatalogModel(
                catalog: SkillsShCatalogClient(),
                skillManager: skillsCLIManager
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
        .windowResizability(.contentMinSize)
    }
}
