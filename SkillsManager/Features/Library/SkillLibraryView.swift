import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @Bindable var model: SkillLibraryModel
    @State private var isChoosingDirectory = false
    @State private var importFailure: ImportFailure?

    var body: some View {
        NavigationSplitView {
            SkillSourceSidebar(model: model)
        } content: {
            SkillList(model: model) {
                isChoosingDirectory = true
            }
        } detail: {
            SkillDetail(skill: model.selectedSkill)
        }
        .navigationTitle("Skills Manager")
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: "Search skills"
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
        .alert(item: $importFailure) { failure in
            Alert(
                title: Text("Unable to Add Directory"),
                message: Text(failure.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var addDirectoryButton: some View {
        if #available(macOS 26.0, *) {
            Button("Add Skill Directory", systemImage: "folder.badge.plus") {
                isChoosingDirectory = true
            }
            .buttonStyle(.glassProminent)
            .help("Add a directory that contains agent skills")
        } else {
            Button("Add Skill Directory", systemImage: "folder.badge.plus") {
                isChoosingDirectory = true
            }
            .buttonStyle(.borderedProminent)
            .help("Add a directory that contains agent skills")
        }
    }

    private func handleDirectoryImport(_ result: Result<[URL], any Error>) {
        do {
            guard let directoryURL = try result.get().first else {
                return
            }

            model.addSource(at: directoryURL)
        } catch {
            importFailure = ImportFailure(message: error.localizedDescription)
        }
    }
}

private struct ImportFailure: Identifiable {
    let id = UUID()
    let message: String
}
