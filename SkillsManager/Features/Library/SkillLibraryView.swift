import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @Bindable var model: SkillLibraryModel
    @State private var isChoosingDirectory = false

    var body: some View {
        NavigationSplitView {
            SkillSourceSidebar(model: model)
        } content: {
            SkillList(model: model) {
                isChoosingDirectory = true
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
                isChoosingDirectory = true
            }
            .buttonStyle(.glassProminent)
            .labelStyle(.titleAndIcon)
            .help("Add a directory that contains agent skills")
        } else {
            Button("Add Directory", systemImage: "plus") {
                isChoosingDirectory = true
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.titleAndIcon)
            .help("Add a directory that contains agent skills")
        }
    }

    private func handleDirectoryImport(_ result: Result<[URL], any Error>) {
        Task { @MainActor in
            do {
                guard let directoryURL = try result.get().first else {
                    return
                }

                try await model.addSource(at: directoryURL)
            } catch {
                model.report(error, title: "Unable to Add Directory")
            }
        }
    }
}
