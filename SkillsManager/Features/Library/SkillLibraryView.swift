import Foundation
import SkillsCore
import SwiftUI
import UniformTypeIdentifiers

struct SkillLibraryView: View {
    /// Wide enough for a typical skill name, narrow enough that the toolbar actions
    /// still read as the toolbar's primary content.
    private static let searchFieldWidth: CGFloat = 220
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
        .navigationTitle(model.scopeTitle)
        .navigationSubtitle(model.scopeSubtitle)
        .searchable(
            text: $model.searchText,
            placement: .toolbar,
            prompt: model.searchPrompt
        )
        .toolbarSearchFieldWidth(Self.searchFieldWidth)
        // Two groups, read left to right: discover or configure skills, then find
        // them. The search field is appended by `searchable` after the sort control.
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                discoverButton
                Color.clear
                    .frame(width: 12)
                    .accessibilityHidden(true)
                settingsButton
            }

            libraryViewToolbarContent
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

    private var discoverButton: some View {
        Button("Discover", systemImage: "globe") {
            isShowingCatalog = true
        }
        .labelStyle(.titleAndIcon)
        .help("Search and install skills from skills.sh")
    }

    private var sortMenu: some View {
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

    /// Splits display controls from discovery and configuration actions so the
    /// two groups read as separate Liquid Glass clusters.
    @ToolbarContentBuilder
    private var libraryViewToolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }

        ToolbarItem(placement: .primaryAction) {
            sortMenu
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
        .labelStyle(.titleAndIcon)
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
