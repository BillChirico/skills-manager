import SkillsCore
import SwiftUI

struct SkillSourceSidebar: View {
    @Bindable var model: SkillLibraryModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            Section {
                Label("All Skills", systemImage: "square.grid.2x2")
                    .tag(SkillLibraryModel.SidebarSelection.allSkills)
            }

            Section("Directories") {
                if model.sources.isEmpty {
                    Text("No directories added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sources) { source in
                        Label(source.displayName, systemImage: "folder")
                            .tag(SkillLibraryModel.SidebarSelection.source(source.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .navigationTitle("Library")
    }
}
