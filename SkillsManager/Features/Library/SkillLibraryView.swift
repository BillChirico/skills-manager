import Foundation
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
    @State private var directoryDialogDefaultDirectory: URL?
    @State private var isShowingCatalog = false

    var body: some View {
        NavigationSplitView {
            SkillSourceSidebar(model: model) { sourceID in
                chooseDirectory(for: .relocate(sourceID))
            }
        } content: {
            SkillList(model: model) { agent, defaultDirectory in
                chooseDirectory(
                    for: .add(agent),
                    defaultDirectory: defaultDirectory
                )
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
            allowedContentTypes: [.directory],
            allowsMultipleSelection: false,
            onCompletion: handleDirectoryImport
        )
        .fileDialogDefaultDirectory(directoryDialogDefaultDirectory)
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
            AgentDirectoryMenuContent { agent, defaultDirectory in
                chooseDirectory(
                    for: .add(agent),
                    defaultDirectory: defaultDirectory
                )
            }
        }
        .labelStyle(.titleAndIcon)
        .help("Add a directory that contains an agent’s skills")
    }

    private func chooseDirectory(
        for purpose: DirectoryImportPurpose,
        defaultDirectory: URL? = nil
    ) {
        directoryImportPurpose = purpose
        directoryDialogDefaultDirectory = defaultDirectory
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

struct AgentDirectoryMenuContent: View {
    let chooseDirectory: (SkillAgent, URL?) -> Void
    private let homeDirectory = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        Section("Suggested Locations") {
            ForEach(agentsWithDefaultDirectory) { agent in
                if let relativePath = agent.defaultSkillsDirectoryRelativePath {
                    Button {
                        chooseDirectory(
                            agent,
                            agent.defaultSkillsDirectory(in: homeDirectory)
                        )
                    } label: {
                        Label(
                            "\(agent.displayName) — ~/\(relativePath)",
                            systemImage: agent.systemImage
                        )
                    }
                }
            }
        }

        Section("Choose Another Location") {
            ForEach(SkillAgent.allCases) { agent in
                Button {
                    chooseDirectory(agent, nil)
                } label: {
                    Label(agent.displayName, systemImage: agent.systemImage)
                }
            }
        }
    }

    private var agentsWithDefaultDirectory: [SkillAgent] {
        SkillAgent.allCases.filter {
            $0.defaultSkillsDirectoryRelativePath != nil
        }
    }
}
