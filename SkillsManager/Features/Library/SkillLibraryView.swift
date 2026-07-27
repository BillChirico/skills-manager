import Foundation
import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    @Bindable var model: SkillLibraryModel
    @Bindable var catalogModel: SkillCatalogModel
    @State private var isChoosingDirectory = false
    @State private var sourceBeingRelocated: SkillSource.ID?
    @State private var isShowingCatalog = false

    var body: some View {
        NavigationSplitView {
            SkillSourceSidebar(model: model) { sourceID in
                chooseDirectory(for: sourceID)
            }
        } content: {
            SkillList(model: model)
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

            ToolbarItem(placement: .primaryAction) {
                settingsButton
            }
        }
        .fileImporter(
            isPresented: $isChoosingDirectory,
            allowedContentTypes: [.directory],
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
    private var settingsButton: some View {
        if #available(macOS 26.0, *) {
            settingsLink
                .buttonStyle(.glassProminent)
        } else {
            settingsLink
                .buttonStyle(.borderedProminent)
        }
    }

    private var settingsLink: some View {
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        .help("Manage skill folders and app settings")
    }

    private func chooseDirectory(for sourceID: SkillSource.ID) {
        sourceBeingRelocated = sourceID
        isChoosingDirectory = true
    }

    private func handleDirectoryImport(_ result: Result<[URL], any Error>) {
        guard let sourceID = sourceBeingRelocated else {
            return
        }

        Task { @MainActor in
            do {
                guard let directoryURL = try result.get().first else {
                    return
                }

                try await model.relocateSource(sourceID, to: directoryURL)
            } catch {
                model.report(error, title: "Unable to Relocate Directory")
            }
        }
    }
}
