import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    private enum DirectoryImportPurpose {
        case add
        case relocate(SkillSource.ID)
    }

    @Bindable var model: SkillLibraryModel
    @State private var isChoosingDirectory = false
    @State private var directoryImportPurpose = DirectoryImportPurpose.add

    var body: some View {
        NavigationSplitView {
            SkillSourceSidebar(model: model) { sourceID in
                chooseDirectory(for: .relocate(sourceID))
            }
        } content: {
            SkillList(model: model) {
                chooseDirectory(for: .add)
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
    }

    @ViewBuilder
    private var addDirectoryButton: some View {
        if #available(macOS 26.0, *) {
            Button("Add Directory", systemImage: "plus") {
                chooseDirectory(for: .add)
            }
            .buttonStyle(.glassProminent)
            .labelStyle(.titleAndIcon)
            .help("Add a directory that contains agent skills")
        } else {
            Button("Add Directory", systemImage: "plus") {
                chooseDirectory(for: .add)
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.titleAndIcon)
            .help("Add a directory that contains agent skills")
        }
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
                case .add:
                    try await model.addSource(at: directoryURL)
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
