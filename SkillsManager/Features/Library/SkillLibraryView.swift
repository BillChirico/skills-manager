import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    private enum DirectoryImportPurpose {
        case add(SkillAgent)
        case relocate(SkillSource.ID)
    }

    @Bindable var model: SkillLibraryModel
    @Bindable var catalogModel: SkillCatalogModel
    @State private var isChoosingDirectory = false
    @State private var directoryImportPurpose = DirectoryImportPurpose.add(.other)
    @State private var isShowingCatalog = false

    var body: some View {
        NavigationSplitView {
            SkillSourceSidebar(model: model) { sourceID in
                chooseDirectory(for: .relocate(sourceID))
            }
        } content: {
            SkillList(model: model) { agent in
                chooseDirectory(for: .add(agent))
            }
        } detail: {
            SkillDetail(model: model)
        }
        .navigationTitle("Skills Manager")
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: model.searchPrompt
        )
        .toolbar {
            ToolbarItem {
                Button("Discover Skills", systemImage: "globe") {
                    isShowingCatalog = true
                }
                .help("Search and install skills from skills.sh")
            }

            ToolbarItem {
                Menu {
                    Picker("Sort Skills", selection: $model.sortOrder) {
                        ForEach(SkillSortOrder.allCases) { order in
                            Text(order.displayName)
                                .tag(order)
                        }
                    }
                } label: {
                    Label("Sort by \(model.sortOrder.displayName)", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort skills by name, date added, or agent")
            }

            ToolbarItem {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Skills Manager settings")
            }

            ToolbarItem(placement: .primaryAction) {
                addDirectoryButton
            }
        }
        .fileImporter(
            isPresented: $isChoosingDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleDirectoryImport
        )
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            await model.restoreSources()
        }
        .sheet(isPresented: $isShowingCatalog) {
            SkillCatalogView(
                catalogModel: catalogModel,
                libraryModel: model
            )
            .frame(minWidth: 820, minHeight: 580)
        }
    }

    @ViewBuilder
    private var addDirectoryButton: some View {
        if #available(macOS 26.0, *) {
            addDirectoryMenu
                .buttonStyle(.glassProminent)
        } else {
            addDirectoryMenu
                .buttonStyle(.borderedProminent)
        }
    }

    private var addDirectoryMenu: some View {
        Menu("Add Directory", systemImage: "folder.badge.plus") {
            ForEach(SkillAgent.allCases) { agent in
                Button {
                    chooseDirectory(for: .add(agent))
                } label: {
                    Label(agent.displayName, systemImage: agent.systemImage)
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .help("Add a directory that contains an agent’s skills")
    }

    private func chooseDirectory(for purpose: DirectoryImportPurpose) {
        directoryImportPurpose = purpose
        isChoosingDirectory = true
    }

    private func handleDirectoryImport(_ result: Result<[URL], any Error>) {
        let purpose = directoryImportPurpose

        Task { @MainActor in
            do {
                guard let directoryURL = try result.get().first else {
                    return
                }

                switch purpose {
                case .add(let agent):
                    try await model.addSource(at: directoryURL, agent: agent)
                case .relocate(let sourceID):
                    try await model.relocateSource(sourceID, to: directoryURL)
                }
            } catch {
                let title =
                    switch purpose {
                    case .add:
                        "Unable to Add Directory"
                    case .relocate:
                        "Unable to Relocate Directory"
                    }
                model.report(error, title: title)
            }
        }
    }
}
