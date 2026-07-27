import SkillsCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: SkillLibraryModel

    var body: some View {
        Form {
            Section("Agent Directories") {
                if model.sources.isEmpty {
                    Text("Add a directory from the Library window to configure an agent.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sources) { source in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(source.displayName)
                                Text(source.directoryURL.path(percentEncoded: false))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        } label: {
                            Label(source.agent.displayName, systemImage: source.agent.systemImage)
                        }
                    }
                }
            }

            Section("Discovery") {
                LabeledContent("Catalog") {
                    Text("skills.sh")
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Search results come from skills.sh. Installations copy the selected skill into an enabled agent directory."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 360)
    }
}

struct FolderSettingsSelection {
    var sourceID: SkillSource.ID?

    mutating func reconcile(with sources: [SkillSource]) {
        guard
            let sourceID,
            sources.contains(where: { $0.id == sourceID })
        else {
            sourceID = sources.first?.id
            return
        }
    }
}
